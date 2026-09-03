const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { ActivityLedger, SessionActivityReader } = require(path.join(__dirname, 'activity-state.js'));
const { dataDirectory, macCodexCandidates, desktopLogDirectories } = require(path.join(__dirname, 'platform-paths.js'));

let nextId = 10;
let initialized = false;
let shuttingDown = false;
let buffer = '';
let appServer = null;
let quotaInFlight = false;
let threadsInFlight = false;
let lastStatePayload = '';
let currentLogPath = null;
let currentLogOffset = 0;
let logCarry = '';

const pending = new Map();
const activity = new Map();
const ledger = new ActivityLedger(activity);
const observedThreads = new Set();
const monitorStartedAt = Date.now();
const threadMetadata = new Map();
const READY_TTL_MS = 10 * 60 * 1000;
const ACTIVE_STALE_MS = 12 * 60 * 60 * 1000;
const LOG_SCAN_BYTES = 4 * 1024 * 1024;
const dataRoot = dataDirectory();
const stateFile = path.join(dataRoot, 'bridge-state.json');
const combinedState = { pet: null, quota: null, error: null, updatedAt: 0 };
const profileRoot = process.env.CODEX_HOME || path.join(process.env.USERPROFILE || process.env.HOME || require('os').homedir(), '.codex');
const sessionReader = new SessionActivityReader(path.join(profileRoot, 'sessions'), ledger);
let sessionSourceAvailable = false;
let lastHeartbeatAt = 0;

function findCodexExecutable() {
  if (process.env.CODEX_EXE && fs.existsSync(process.env.CODEX_EXE)) return process.env.CODEX_EXE;
  if (process.platform === 'darwin') {
    for (const candidate of macCodexCandidates()) {
      try { fs.accessSync(candidate, fs.constants.X_OK); return candidate; } catch {}
    }
  }
  if (process.platform === 'win32' && process.env.LOCALAPPDATA) {
    const binRoot = path.join(process.env.LOCALAPPDATA, 'OpenAI', 'Codex', 'bin');
    try {
      const candidates = fs.readdirSync(binRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => path.join(binRoot, entry.name, 'codex.exe'))
        .filter((candidate) => fs.existsSync(candidate))
        .map((candidate) => ({ candidate, mtime: fs.statSync(candidate).mtimeMs }))
        .sort((a, b) => b.mtime - a.mtime);
      if (candidates.length) return candidates[0].candidate;
    } catch {}
  }
  return 'codex';
}

function persist(payload) {
  if (payload.type === 'pet-state') {
    combinedState.pet = payload;
    if (combinedState.error?.scope === 'activity') combinedState.error = null;
  }
  else if (payload.type === 'snapshot') {
    combinedState.quota = payload;
    if (combinedState.error?.scope === 'quota') combinedState.error = null;
  }
  else if (payload.type === 'error') combinedState.error = payload;
  combinedState.updatedAt = Date.now();
  try {
    fs.mkdirSync(dataRoot, { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify(combinedState), 'utf8');
  } catch {}
  if (process.parentPort) process.parentPort.postMessage(payload);
  else process.stdout.write(JSON.stringify(payload) + '\n');
}

function send(message) {
  if (appServer && appServer.stdin && appServer.stdin.writable) {
    appServer.stdin.write(JSON.stringify(message) + '\n');
  }
}
function request(method, params, kind) {
  if (!initialized) return;
  const id = nextId++;
  pending.set(id, kind);
  send({ id, method, ...(params === undefined ? {} : { params }) });
}
function readRateLimits() {
  if (!initialized || quotaInFlight) return;
  quotaInFlight = true;
  request('account/rateLimits/read', undefined, 'quota');
}
function readThreads() {
  if (!initialized || threadsInFlight) return;
  threadsInFlight = true;
  request('thread/list', {
    limit: 100,
    archived: false,
    sortKey: 'updated_at',
    sortDirection: 'desc',
    useStateDbOnly: true,
  }, 'threads');
}

function normalizeQuota(result) {
  const snapshot = (result.rateLimitsByLimitId && result.rateLimitsByLimitId.codex) || result.rateLimits || {};
  const resetSummary = result.rateLimitResetCredits || null;
  const credits = Array.isArray(resetSummary && resetSummary.credits) ? resetSummary.credits : [];
  const availableCredits = credits.filter((credit) => credit.status === 'available');
  const expirations = availableCredits.map((credit) => credit.expiresAt).filter(Number.isFinite);
  return {
    type: 'snapshot',
    fetchedAt: Math.floor(Date.now() / 1000),
    planType: snapshot.planType || null,
    primary: snapshot.primary || null,
    secondary: snapshot.secondary || null,
    resetCredits: resetSummary ? {
      availableCount: resetSummary && Number.isFinite(resetSummary.availableCount)
        ? resetSummary.availableCount : availableCredits.length,
      expiresAt: expirations.length ? Math.min(...expirations) : null,
      titles: availableCredits.map((credit) => credit.title).filter(Boolean),
    } : null,
  };
}

function extractConversationId(line) {
  const match = line.match(/(?:conversationId|threadId)=([0-9a-f-]{20,})/i);
  return match ? match[1] : null;
}
function lineTimestamp(line) {
  const value = Date.parse(line.slice(0, 24));
  return Number.isFinite(value) ? value : Date.now();
}
function markActive(threadId, timestamp) {
  ledger.start(threadId, timestamp);
}
function markWaiting(threadId, timestamp) {
  ledger.wait(threadId, timestamp);
}
function markReady(threadId, timestamp, turnId) {
  ledger.finish(threadId, 'ready', timestamp, turnId);
}
function markFailed(threadId, timestamp, turnId) {
  ledger.finish(threadId, 'failed', timestamp, turnId);
}

function cleanTitle(value) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, 80);
}
function rememberThreads(result) {
  if (!result || !Array.isArray(result.data)) return;
  for (const thread of result.data) {
    if (!thread || !thread.id) continue;
    const scope = sessionReader.classify(thread.id, thread);
    // macOS desktop log paths vary by client. Recent local root sessions provide
    // lifecycle-only fallback; sub-agent sessions are not separate tray tasks.
    if (process.platform === 'darwin' && Number.isFinite(thread.updatedAt)
        && Date.now() - thread.updatedAt * 1000 < ACTIVE_STALE_MS
        && scope === 'root') observedThreads.add(thread.id);
    const existing = threadMetadata.get(thread.id);
    const title = cleanTitle(thread.name)
      || (existing && existing.title)
      || cleanTitle(thread.preview);
    threadMetadata.set(thread.id, {
      title: title || ('任务 ' + String(thread.id).slice(-6)),
      updatedAt: Number.isFinite(thread.updatedAt) ? thread.updatedAt * 1000 : 0,
    });
  }
}
function readSessionIndexTitles() {
  const profile = process.env.USERPROFILE || process.env.HOME;
  if (!profile) return;
  const indexPath = path.join(process.env.CODEX_HOME || path.join(profile, '.codex'), 'session_index.jsonl');
  try {
    const lines = fs.readFileSync(indexPath, 'utf8').split(/\r?\n/);
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const entry = JSON.parse(line);
        if (!entry.id || !cleanTitle(entry.thread_name)) continue;
        const updatedAt = Date.parse(entry.updated_at || '') || 0;
        const previous = threadMetadata.get(entry.id);
        if (!previous || updatedAt >= previous.updatedAt) {
          threadMetadata.set(entry.id, { title: cleanTitle(entry.thread_name), updatedAt });
        }
      } catch {}
    }
  } catch {}
}

function processLogLine(line) {
  if (!line) return;
  const threadId = extractConversationId(line);
  const timestamp = lineTimestamp(line);
  const turnId = line.match(/(?:turnId|latestTurnId)=([0-9a-f-]{20,})/i)?.[1] || null;
  const requestId = line.match(/(?:serverRequestId|requestId)=([^\s]+)/i)?.[1] || null;

  const isStart = line.includes('Reasoning summary turn-start config resolved')
    || line.includes('Received turn/started for unknown conversation');
  const isComplete = line.includes('[desktop-notifications] show turn-complete')
    || line.includes('Received turn/completed for unknown conversation');
  const isFailure = line.includes('[desktop-notifications] show turn-failed')
    || line.includes('[desktop-notifications] show turn-error');
  const isWaiting = /item\/(?:commandExecution|fileChange|permissions)\/requestApproval/i.test(line)
    || line.includes('item/tool/requestUserInput')
    || line.includes('request_user_input');
  const isResolved = line.includes('serverRequest/resolved');
  const isStopped = line.includes('method=turn/interrupt') && line.includes('errorCode=null');
  const isProgress = line.includes('Reasoning summary item completed')
    || line.includes('Reasoning summary part added');
  if (threadId && (isStart || isComplete || isFailure || isWaiting || isStopped || line.includes('maybe_resume_success'))) {
    observedThreads.add(threadId);
  }

  if (sessionReader.scopes.get(threadId) === 'excluded') return;
  if (isStart) ledger.start(threadId, timestamp, turnId);
  else if (isStopped) ledger.finish(threadId, 'stopped', timestamp, turnId);
  else if (isFailure) ledger.finish(threadId, 'failed', timestamp, turnId, timestamp < monitorStartedAt);
  else if (isComplete) {
    // Untagged notifications must not complete a newer, session-identified turn.
    if (turnId || !ledger.latest.get(threadId)?.confirmed) ledger.finish(threadId, 'ready', timestamp, turnId, timestamp < monitorStartedAt);
  }
  else if (line.includes('maybe_resume_success') && turnId && /latestTurnStatus=(completed|interrupted|failed)\b/.test(line)) {
    // A resumed thread can expose a terminal status even after an app crash
    // prevented its final session event from being flushed.
    const status = line.match(/latestTurnStatus=(\w+)/)[1];
    ledger.reconcile(threadId, status === 'completed' ? 'ready' : status === 'failed' ? 'failed' : 'stopped', timestamp, turnId);
  }
  else if (isWaiting) ledger.wait(threadId, timestamp, requestId);
  else if (isResolved || isProgress) {
    ledger.progress(threadId, timestamp, isResolved, requestId);
  }
}

function logDirectories() {
  return desktopLogDirectories();
}
function latestDesktopLog() {
  const candidates = [];
  for (const directory of logDirectories()) {
    try {
      for (const name of fs.readdirSync(directory)) {
        if (!/^(?:codex-desktop-.*-t0-.*|main)\.log$/i.test(name)) continue;
        const filePath = path.join(directory, name);
        const stat = fs.statSync(filePath);
        candidates.push({ filePath, mtime: stat.mtimeMs });
      }
    } catch {}
  }
  candidates.sort((a, b) => b.mtime - a.mtime);
  return candidates.length ? candidates[0].filePath : null;
}
function parseText(text, discardFirstPartial) {
  let content = text;
  if (discardFirstPartial) {
    const firstNewline = content.indexOf('\n');
    content = firstNewline >= 0 ? content.slice(firstNewline + 1) : '';
  }
  const lines = content.split(/\r?\n/);
  logCarry = lines.pop() || '';
  for (const line of lines) processLogLine(line);
}
function loadLog(filePath) {
  const stat = fs.statSync(filePath);
  const start = Math.max(0, stat.size - LOG_SCAN_BYTES);
  const length = stat.size - start;
  const buffer = Buffer.alloc(length);
  const fd = fs.openSync(filePath, 'r');
  try { fs.readSync(fd, buffer, 0, length, start); } finally { fs.closeSync(fd); }
  // Keep per-turn watermarks across log rotation/replay.
  logCarry = '';
  parseText(buffer.toString('utf8'), start > 0);
  currentLogPath = filePath;
  currentLogOffset = stat.size;
}
function readLogAppend(filePath) {
  const stat = fs.statSync(filePath);
  if (stat.size < currentLogOffset) {
    loadLog(filePath);
    return;
  }
  const length = stat.size - currentLogOffset;
  if (length <= 0) return;
  const buffer = Buffer.alloc(length);
  const fd = fs.openSync(filePath, 'r');
  try { fs.readSync(fd, buffer, 0, length, currentLogOffset); } finally { fs.closeSync(fd); }
  currentLogOffset = stat.size;
  const text = logCarry + buffer.toString('utf8');
  logCarry = '';
  parseText(text, false);
}

function pruneActivity() {
  const now = Date.now();
  for (const [threadId, item] of activity) {
    if ((item.state === 'ready' || item.state === 'failed') && now - item.lastEventAt > READY_TTL_MS) activity.delete(threadId);
    else if (item.state === 'active' && now - item.lastEventAt > ACTIVE_STALE_MS) activity.delete(threadId);
    else if (item.state === 'waiting' && now - item.lastEventAt > ACTIVE_STALE_MS) activity.delete(threadId);
  }
}
function emitPetState() {
  pruneActivity();
  let active = 0;
  let waiting = 0;
  let ready = 0;
  let failed = 0;
  // Log "unknown conversation" events also belong to title generation,
  // ambient suggestions and subagents. Never expose provisional/child entries.
  const visibleActivity = Array.from(activity.entries()).filter(([id]) => sessionReader.isRoot(id));
  for (const [, item] of visibleActivity) {
    if (item.state === 'active') active += 1;
    else if (item.state === 'waiting') waiting += 1;
    else if (item.state === 'ready') ready += 1;
    else if (item.state === 'failed') failed += 1;
  }

  const statePriority = { waiting: 0, failed: 1, ready: 2, active: 3 };
  const stateLabels = { waiting: '需要确认', failed: '出错', ready: '已完成', active: '执行中' };
  const tasks = visibleActivity.map(([threadId, item]) => {
    const metadata = threadMetadata.get(threadId);
    return {
      id: threadId,
      title: metadata ? metadata.title : ('任务 ' + String(threadId).slice(-6)),
      state: item.state,
      label: stateLabels[item.state] || '进行中',
      updatedAt: Math.floor(item.lastEventAt / 1000),
    };
  }).sort((a, b) => {
    const priority = (statePriority[a.state] ?? 9) - (statePriority[b.state] ?? 9);
    return priority || b.updatedAt - a.updatedAt;
  });

  let petState = 'idle';
  let label = '空闲中';
  if (waiting > 0) { petState = 'waiting'; label = '需要确认'; }
  else if (failed > 0) { petState = 'failed'; label = '任务出错'; }
  else if (ready > 0) { petState = 'review'; label = '任务完成'; }
  else if (active > 0) { petState = 'running'; label = '思考中'; }

  const payload = {
    type: 'pet-state', bridgeVersion: '0.2.2', petState, label,
    counts: { total: tasks.length, active: active + waiting, running: active, waiting, ready, failed },
    tasks,
    source: sessionSourceAvailable ? 'session-events+desktop-log' : currentLogPath ? 'desktop-log' : 'unavailable',
    fetchedAt: Math.floor(Date.now() / 1000),
  };
  const semantic = JSON.stringify({ petState, label, counts: payload.counts, tasks, source: payload.source });
  if (semantic !== lastStatePayload || Date.now() - lastHeartbeatAt >= 5000) {
    lastStatePayload = semantic;
    lastHeartbeatAt = Date.now();
    persist(payload);
  }
}
function pollDesktopActivity() {
  try {
    const filePath = latestDesktopLog();
    if (filePath) {
      if (filePath !== currentLogPath) loadLog(filePath);
      else readLogAppend(filePath);
    }
    sessionSourceAvailable = sessionReader.poll(new Set([...observedThreads, ...ledger.latest.keys()])) > 0;
    emitPetState();
  } catch (error) {
    persist({ type: 'error', scope: 'activity', message: '无法读取 Codex 活动记录: ' + error.message });
  }
}

function handleMessage(message) {
  if (message.id === 1 && message.result) {
    initialized = true;
    send({ method: 'initialized' });
    readRateLimits();
    readThreads();
    return;
  }
  if (message.id && pending.has(message.id)) {
    const kind = pending.get(message.id);
    pending.delete(message.id);
    if (kind === 'quota') quotaInFlight = false;
    if (kind === 'threads') threadsInFlight = false;
    if (message.error) {
      persist({ type: 'error', scope: kind, message: message.error.message || 'Codex 返回了未知错误' });
      return;
    }
    if (kind === 'quota' && message.result) persist(normalizeQuota(message.result));
    if (kind === 'threads' && message.result) {
      rememberThreads(message.result);
      readSessionIndexTitles();
      lastStatePayload = '';
      emitPetState();
    }
    return;
  }
  if (message.method === 'account/rateLimits/updated') readRateLimits();
  if (message.method === 'thread/name/updated' || message.method === 'thread/started') readThreads();
}

function startAppServer() {
  appServer = spawn(findCodexExecutable(), ['app-server', '--stdio'], {
    stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true,
  });
  appServer.stdout.setEncoding('utf8');
  appServer.stdout.on('data', (chunk) => {
    buffer += chunk;
    let newline;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      try { handleMessage(JSON.parse(line)); } catch {}
    }
  });
  appServer.stderr.setEncoding('utf8');
  // Drain diagnostics without copying account or conversation details into the UI.
  appServer.stderr.on('data', () => {});
  appServer.on('error', (error) => persist({ type: 'error', scope: 'bridge', message: error.message }));
  appServer.on('exit', (code) => {
    if (!shuttingDown) persist({ type: 'error', scope: 'bridge', message: 'Codex 额度桥已退出 (' + (code == null ? 'unknown' : code) + ')' });
  });
  send({
    id: 1, method: 'initialize',
    params: {
      clientInfo: { name: 'bjut-yanxiaobei-codex-pet', title: 'BJUT YanXiaoBei Codex Pet', version: '0.2.2' },
      capabilities: { experimentalApi: true, requestAttestation: false, optOutNotificationMethods: [] },
    },
  });
}

function handleCommand(command) {
  if (command === 'shutdown') { shutdown(); return; }
  if (command === 'refresh') { readRateLimits(); readThreads(); pollDesktopActivity(); }
  if (command === 'clear-ready') {
    for (const [threadId, item] of activity) {
      if (item.state === 'ready' || item.state === 'failed') activity.delete(threadId);
    }
    lastStatePayload = '';
    emitPetState();
  }
}

// Keep this marker for the isolated bridge tests (no process startup in tests).
process.stdin.setEncoding('utf8');
if (process.parentPort) process.parentPort.on('message', event => handleCommand(event.data));
else process.stdin.on('data', chunk => {
  for (const command of chunk.toLowerCase().split(/\r?\n/)) handleCommand(command.trim());
});

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  clearInterval(quotaTimer);
  clearInterval(activityTimer);
  clearInterval(threadTimer);
  try { if (appServer && appServer.stdin) appServer.stdin.end(); } catch {}
  setTimeout(() => {
    try { if (appServer) appServer.kill(); } catch {}
    process.exit(0);
  }, 150);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
if (!process.parentPort) process.stdin.on('end', shutdown);
process.on('exit', () => { try { if (appServer) appServer.kill(); } catch {} });

readSessionIndexTitles();
pollDesktopActivity();
startAppServer();
const quotaTimer = setInterval(readRateLimits, 60_000);
const activityTimer = setInterval(pollDesktopActivity, 1_000);
const threadTimer = setInterval(() => {
  readSessionIndexTitles();
  readThreads();
  lastStatePayload = '';
  emitPetState();
}, 20_000);
