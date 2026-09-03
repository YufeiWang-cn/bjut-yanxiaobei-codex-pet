'use strict';
const path = require('path');
const os = require('os');
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
function desktopLogDirectories(platform = process.platform, env = process.env, home = os.homedir(), now = Date.now()) {
  const bases = env.CODEX_LOG_DIR ? [env.CODEX_LOG_DIR] : platform === 'darwin'
    ? ['Codex','com.openai.codex','ChatGPT','com.openai.chat'].map(name => path.join(home,'Library','Logs',name))
    : env.LOCALAPPDATA ? [path.join(env.LOCALAPPDATA,'Codex','Logs')] : [];
  const dates = [0,1].map(days => {
    const d = new Date(now-days*86400000);
    return [String(d.getFullYear()),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')];
  });
  return bases.flatMap(base => [base, ...dates.map(parts=>path.join(base,...parts))]);
}
module.exports = { dataDirectory, macCodexCandidates, desktopLogDirectories };
