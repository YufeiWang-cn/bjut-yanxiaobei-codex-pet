'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');
function dataDirectory(platform = process.platform, env = process.env, home = os.homedir()) {
  if (env.YANXIAOBEI_DATA_DIR) return env.YANXIAOBEI_DATA_DIR;
  return platform === 'darwin' ? path.join(home, 'Library', 'Application Support', 'BJUT-YanXiaoBei')
    : path.join(env.LOCALAPPDATA || os.tmpdir(), 'BJUT-YanXiaoBei');
}
function macCodexCandidates(env = process.env, home = os.homedir()) {
  const apps = [env.CODEX_APP_PATH, '/Applications/Codex.app', path.join(home,'Applications','Codex.app'),
    '/Applications/ChatGPT.app', path.join(home,'Applications','ChatGPT.app')].filter(Boolean);
  return [...(env.CODEX_EXE ? [env.CODEX_EXE] : []), ...apps.flatMap(app => [
    path.join(app,'Contents','Resources','codex'), path.join(app,'Contents','Resources','bin','codex'),
  ]), '/opt/homebrew/bin/codex', '/usr/local/bin/codex', path.join(home,'.local','bin','codex')];
}
function codexProfileRoots(platform = process.platform, env = process.env, home = os.homedir()) {
  const candidates = [env.CODEX_HOME];
  if (env.USERPROFILE) candidates.push(path.join(env.USERPROFILE, '.codex'));
  if (env.HOME) candidates.push(path.join(env.HOME, '.codex'));
  if (!env.USERPROFILE && !env.HOME && home) candidates.push(path.join(home, '.codex'));
  if (platform === 'win32' && env.LOCALAPPDATA) candidates.push(path.join(env.LOCALAPPDATA, 'OpenAI', 'Codex'));
  return [...new Set(candidates.filter(Boolean).map(value => path.resolve(value)))];
}
function desktopLogDirectories(platform = process.platform, env = process.env, home = os.homedir(), now = Date.now(), io = fs) {
  const bases = env.CODEX_LOG_DIR ? [env.CODEX_LOG_DIR] : platform === 'darwin'
    ? ['Codex','com.openai.codex','ChatGPT','com.openai.chat'].map(name => path.join(home,'Library','Logs',name))
    : [
      env.LOCALAPPDATA && path.join(env.LOCALAPPDATA,'Codex','Logs'),
      env.LOCALAPPDATA && path.join(env.LOCALAPPDATA,'OpenAI','Codex','Logs'),
      env.APPDATA && path.join(env.APPDATA,'Codex','Logs'),
      env.APPDATA && path.join(env.APPDATA,'OpenAI','Codex','Logs'),
    ].filter(Boolean);
  if (!env.CODEX_LOG_DIR && platform === 'win32' && env.LOCALAPPDATA) {
    const packages = path.join(env.LOCALAPPDATA, 'Packages');
    try {
      for (const entry of io.readdirSync(packages, {withFileTypes:true})) {
        if (!entry.isDirectory() || !/^OpenAI\.Codex_/i.test(entry.name)) continue;
        for (const relative of [['LocalState','Logs'],['LocalCache','Local','Codex','Logs'],['LocalCache','Roaming','Codex','Logs']]) {
          bases.push(path.join(packages, entry.name, ...relative));
        }
      }
    } catch {}
  }
  const dates = [0,1].map(days => {
    const d = new Date(now-days*86400000);
    return [String(d.getFullYear()),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')];
  });
  return [...new Set(bases.flatMap(base => [base, ...dates.map(parts=>path.join(base,...parts))]))];
}
module.exports = { dataDirectory, codexProfileRoots, macCodexCandidates, desktopLogDirectories };
