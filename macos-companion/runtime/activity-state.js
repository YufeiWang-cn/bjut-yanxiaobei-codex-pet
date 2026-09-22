'use strict';
const fs = require('fs');
const path = require('path');
const { StringDecoder } = require('string_decoder');

// Keep terminal watermarks even after a reminder is dismissed/expired. Replaying
// a rotated log must not resurrect a completed turn or refresh its reminder TTL.
class ActivityLedger {
  constructor(activity) { this.activity = activity; this.latest = new Map(); }
  put(id, value) {
    this.latest.set(id, value);
    if (value.state === 'stopped') this.activity.delete(id);
    else this.activity.set(id, value);
  }
  start(id, at, turnId = null, source = 'log') {
    if (!id || !Number.isFinite(at)) return;
    const previous = this.latest.get(id);
    if (previous) {
      if (turnId && turnId === previous.turnId) return;
      // The renderer logs a start just before the corresponding session event.
      if (source === 'session' && !previous.terminal && !previous.turnId && at >= previous.startedAt && at - previous.startedAt < 2000) {
        previous.turnId = turnId;
        previous.confirmed = true;
        return;
      }
      if (at <= previous.lastEventAt || previous.retired?.has(turnId)) return;
    }
    const retired = new Set(previous?.retired || []);
    if (previous?.turnId) retired.add(previous.turnId);
    while (retired.size > 32) retired.delete(retired.values().next().value);
    this.put(id, { state: 'active', startedAt: at, lastEventAt: at, turnId,
      confirmed: source === 'session', retired, approvals: new Set(), terminal: false });
  }
  finish(id, state, at, turnId = null, silent = false) {
    if (!id || !Number.isFinite(at)) return;
    const previous = this.latest.get(id);
    if (previous) {
      if (at < previous.startedAt || (turnId && previous.retired?.has(turnId))) return;
      if (turnId && previous.turnId && turnId !== previous.turnId) return;
      if (previous.terminal) return;
    }
    this.put(id, { ...previous, state, turnId: turnId || previous?.turnId || null,
      startedAt: previous?.startedAt ?? at, lastEventAt: at, terminal: true, approvals: new Set() });
    if (silent) this.activity.delete(id);
  }
  reconcile(id, state, at, turnId) {
    const previous = this.latest.get(id);
    // Hydration is a state snapshot, not a new completion. An untagged new
    // turn must never be finished by an older latestTurnId from thread/resume.
    if (!turnId || (previous && !previous.terminal && previous.turnId !== turnId)) return;
    this.finish(id, state, at, turnId, true);
  }
  wait(id, at, requestId = null) {
    let item = this.latest.get(id);
    if (!item) { this.start(id, at); item = this.latest.get(id); }
    if (!item || item.terminal || at < item.lastEventAt) return;
    item.approvals.add(requestId || 'unknown');
    if (item.state !== 'waiting') item.waitingSince = at;
    item.state = 'waiting'; item.lastEventAt = at;
    this.activity.set(id, item);
  }
  progress(id, at, resolved = false, requestId = null) {
    const item = this.latest.get(id);
    if (!item || item.terminal || at < item.lastEventAt) return;
    if (resolved) {
      if (requestId) item.approvals.delete(requestId);
      // Unidentified resolutions cannot clear other identified approvals.
      item.approvals.delete('unknown');
    }
    // Ordinary reasoning/tool progress is not proof that an approval was answered.
    if (item.approvals.size === 0) { item.state = 'active'; item.waitingSince = null; }
    item.lastEventAt = at;
    this.activity.set(id, item);
  }
}

function sessionEvent(line) {
  // Do not retain prompts, reasoning, tool output, or assistant message text.
  if (!/"type"\s*:\s*"(?:task_started|task_complete|turn_aborted|task_failed|custom_tool_call|custom_tool_call_output|function_call|function_call_output)"/.test(line)) return null;
  try {
    const record = JSON.parse(line);
    const at = Date.parse(record.timestamp);
    if (!Number.isFinite(at)) return null;
    const event = record.payload;
    if (record.type === 'response_item') {
      const requestId = event?.call_id;
      if (!requestId) return null;
      const isCall = event.type === 'custom_tool_call' || event.type === 'function_call';
      const input = typeof event.input === 'string' ? event.input
        : typeof event.arguments === 'string' ? event.arguments : '';
      // An escalated command may be handled by Codex's automatic reviewer and
      // must stay active unless the desktop actually reveals an approval UI.
      // Explicit permission/input tools always require a user response.
      const promptType = event.name === 'request_user_input' || /\btools\.request_user_input\s*\(/.test(input)
        ? 'input' : event.name === 'request_permissions' || /\btools\.request_permissions\s*\(/.test(input)
          ? 'permission' : null;
      if (isCall && promptType) return { state: 'waiting', at, requestId, promptType };
      if (event.type === 'custom_tool_call_output' || event.type === 'function_call_output') {
        return { state: 'resolved', at, requestId };
      }
      return null;
    }
    if (record.type !== 'event_msg' || !event?.turn_id) return null;
    if (event.type === 'task_started') return { state: 'active', at, turnId: event.turn_id };
    if (event.type === 'turn_aborted') return { state: 'stopped', at, turnId: event.turn_id };
    if (event.type === 'task_failed') return { state: 'failed', at, turnId: event.turn_id };
    if (event.type === 'task_complete') return {
      state: event.status === 'failed' || event.error ? 'failed' : 'ready', at, turnId: event.turn_id,
    };
  } catch { /* Incomplete/invalid JSON is never a state change. */ }
  return null;
}

function threadScope(metadata) {
  if (!metadata || typeof metadata !== 'object') return 'unknown';
  const source = JSON.stringify(metadata.source || '').toLowerCase();
  if (metadata.ephemeral === true || metadata.parent_thread_id || metadata.parentThreadId
      || /sub.?agent|ephemeral|internal|guardian|title.?gen|suggestion|review|compact/.test(source)) return 'excluded';
  // Source names have changed between Codex Desktop/CLI releases. A persisted
  // session with a non-empty, non-internal string source is a top-level thread;
  // child/ephemeral markers above still take precedence. For structured source
  // values, accept only known top-level producer keys.
  if (typeof metadata.source === 'string' && metadata.source.trim()) return 'root';
  if (typeof metadata.sourceKind === 'string' && /^(?:cli|vscode|exec|appserver)$/i.test(metadata.sourceKind)) return 'root';
  if (metadata.thread_source === 'user' || metadata.threadSource === 'user') return 'root';
  if (metadata.source && typeof metadata.source === 'object'
      && Object.keys(metadata.source).some(key => /^(?:cli|vscode|exec|appserver|desktop|codex|chatgpt|cloud)$/i.test(key))) {
    return 'root';
  }
  return 'unknown';
}

class SessionActivityReader {
  constructor(root, ledger, io = fs, shouldWait = () => true) {
    this.roots = [...new Set((Array.isArray(root) ? root : [root]).filter(Boolean))];
    this.root = this.roots[0] || null; this.ledger = ledger; this.io = io;
    this.shouldWait = shouldWait;
    this.files = new Map(); this.cursors = new Map(); this.scannedAt = 0;
    this.limit = 4 * 1024 * 1024;
    this.startedAt = Date.now();
    this.scopes = new Map(); this.metadataCache = new Map();
    this.recentCache = []; this.recentCacheAt = 0;
  }
  addRoot(root) {
    if (!root || this.roots.includes(root)) return false;
    this.roots.push(root); this.root = this.roots[0]; this.scannedAt = 0; this.recentCacheAt = 0;
    return true;
  }
  classify(id, metadata) {
    const scope = threadScope(metadata);
    // Negative provenance always wins, including when thread/list arrives late.
    if (this.scopes.get(id) !== 'excluded' && scope !== 'unknown') this.scopes.set(id, scope);
    if (this.scopes.get(id) === 'excluded') {
      this.ledger.activity.delete(id); this.ledger.latest.delete(id);
    }
    return this.scopes.get(id) || 'unknown';
  }
  isRoot(id) { return this.scopes.get(id) === 'root'; }
  readScope(file, id) {
    const stat = this.io.statSync(file);
    const cached = this.metadataCache.get(file);
    if (cached && cached.ino === stat.ino && stat.size >= cached.size) return cached.scope;
    const bytes = Buffer.alloc(Math.min(stat.size, 256 * 1024));
    const fd = this.io.openSync(file, 'r');
    let length;
    try { length = this.io.readSync(fd, bytes, 0, bytes.length, 0); }
    finally { this.io.closeSync(fd); }
    const text = bytes.subarray(0, length).toString('utf8');
    const newline = text.indexOf('\n');
    if (newline < 0) return 'unknown';
    try {
      const record = JSON.parse(text.slice(0, newline));
      const recordId = record.payload?.id || record.payload?.session_id;
      if (record.type !== 'session_meta' || recordId !== id) return 'unknown';
      const scope = this.classify(id, record.payload);
      if (scope !== 'unknown') this.metadataCache.set(file, { ino: stat.ino, size: length, scope });
      return scope;
    } catch { return 'unknown'; }
  }
  discover(now) {
    if (!this.root || (this.scannedAt && now - this.scannedAt < 20000)) return;
    this.scannedAt = now;
    const found = new Map();
    const visit = directory => {
      let entries;
      try { entries = this.io.readdirSync(directory, { withFileTypes: true }); } catch { return; }
      for (const entry of entries) {
        if (entry.isSymbolicLink()) continue;
        const file = path.join(directory, entry.name);
        if (entry.isDirectory()) { visit(file); continue; }
        const match = entry.name.match(/^rollout-.*?([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})(?:_[0-9a-f-]+)?\.jsonl$/i);
        if (!entry.isFile() || !match) continue;
        const id = match[1];
        if (!found.has(id)) found.set(id, []);
        found.get(id).push(file);
      }
    };
    for (const root of this.roots) visit(root);
    this.files = found;
  }
  recentIds(now = Date.now(), maxAgeMs = 12 * 60 * 60 * 1000, limit = 64) {
    this.discover(now);
    if (this.recentCacheAt && now - this.recentCacheAt < 20000) return this.recentCache.slice(0, limit);
    const recent = [];
    for (const [id, files] of this.files) {
      let mtime = 0;
      for (const file of files) {
        try { mtime = Math.max(mtime, this.io.statSync(file).mtimeMs); } catch {}
      }
      if (mtime && now - mtime <= maxAgeMs) recent.push({ id, mtime });
    }
    recent.sort((a, b) => b.mtime - a.mtime);
    this.recentCache = recent.map(item => item.id);
    this.recentCacheAt = now;
    return this.recentCache.slice(0, limit);
  }
  read(file, id) {
    const stat = this.io.statSync(file);
    let cursor = this.cursors.get(file);
    if (cursor && cursor.offset === stat.size && cursor.mtime === stat.mtimeMs) return;
    if (!cursor || cursor.ino !== stat.ino || stat.size < cursor.offset || (stat.size === cursor.offset && cursor.mtime !== stat.mtimeMs)) {
      // Read only a bounded tail at startup; a completion is at the tail even
      // when an earlier tool result was many megabytes long.
      const offset = Math.max(0, stat.size - this.limit);
      const previous = this.ledger.latest.get(id);
      const live = previous && !previous.terminal && previous.startedAt >= this.startedAt;
      cursor = { offset, ino: stat.ino, carry: '', skipPartial: offset > 0, decoder: new StringDecoder('utf8'),
        baselineEnd: stat.size, silentBaseline: !live };
      this.cursors.set(file, cursor);
    }
    const length = Math.min(this.limit, stat.size - cursor.offset);
    if (!length) return;
    const bytes = Buffer.alloc(length);
    const fd = this.io.openSync(file, 'r');
    let read;
    try { read = this.io.readSync(fd, bytes, 0, length, cursor.offset); }
    finally { this.io.closeSync(fd); }
    cursor.offset += read;
    cursor.mtime = stat.mtimeMs;
    let text = cursor.carry + cursor.decoder.write(bytes.subarray(0, read));
    if (cursor.skipPartial) {
      const newline = text.indexOf('\n');
      if (newline < 0) { cursor.carry = ''; return; }
      text = text.slice(newline + 1); cursor.skipPartial = false;
    }
    const lines = text.split(/\r?\n/);
    cursor.carry = lines.pop() || '';
    if (cursor.carry.length > this.limit) { cursor.carry = ''; cursor.skipPartial = true; }
    for (const line of lines) {
      const event = sessionEvent(line);
      if (!event) continue;
      if (event.state === 'waiting') {
        if (this.shouldWait(id, event)) this.ledger.wait(id, event.at, event.requestId);
      }
      else if (event.state === 'resolved') {
        const approvals = this.ledger.latest.get(id)?.approvals;
        if (approvals?.has(event.requestId)) this.ledger.progress(id, event.at, true, event.requestId);
      }
      else if (event.state === 'active') this.ledger.start(id, event.at, event.turnId, 'session');
      else this.ledger.finish(id, event.state, event.at, event.turnId, cursor.silentBaseline);
    }
    if (cursor.offset >= cursor.baselineEnd && !cursor.carry) cursor.silentBaseline = false;
  }
  poll(ids, now = Date.now()) {
    this.discover(now);
    let available = 0;
    for (const id of ids) {
      // Only read sessions already observed in desktop activity, not every task.
      const candidates = [];
      for (const file of this.files.get(id) || []) {
        try { candidates.push({ file, mtime: this.io.statSync(file).mtimeMs }); } catch {}
      }
      candidates.sort((a, b) => b.mtime - a.mtime);
      if (!candidates.length) continue;
      try {
        // Inspect provenance before reading ANY lifecycle event, on both OSes.
        const scope = this.readScope(candidates[0].file, id);
        if (scope !== 'root') continue;
        this.read(candidates[0].file, id); available++;
      } catch { /* Log fallback remains usable for independently known roots. */ }
    }
    return available;
  }
}

module.exports = { ActivityLedger, SessionActivityReader, sessionEvent, threadScope };
