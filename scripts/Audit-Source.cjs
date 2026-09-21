'use strict';
// Read-only by default. Optional --report writes a per-file inventory outside releases.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { TextDecoder } = require('node:util');
const excludedDirs = new Set(['.git', '.codex', '.test-output', 'node_modules', 'dist', 'logs', 'sessions', '__pycache__', '.release-backups']);
const topDirs = new Set(['codex-native', 'windows-companion', 'macos-companion', '.github', 'docs', 'scripts', 'tests']);
const topFiles = new Set(['README.md', 'CHANGELOG.md', 'LICENSE.md', '.gitignore', '.gitattributes', 'VERSION.txt', 'START-HERE.html']);
const binaryExtensions = new Set(['.png', '.gif', '.webp']);
const textExtensions = new Set(['.md', '.txt', '.json', '.js', '.cjs', '.ps1', '.xaml', '.html', '.css', '.vbs', '.cmd', '.command', '.yml', '.yaml', '.py']);
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
function privateFile(name) {
  return /^(?:auth\.json|bridge-state\.json|badge-position\.json|ui-settings\.json|mac-settings\.json|update-preferences\.json|autostart-.*\.flag|\.env.*)$/i.test(name) ||
    /(?:\.(?:log|zip|dmg|db|sqlite|lnk|p12|pfx|pem|key|pyc)|\.(?:db|sqlite)-[^.]+)$/i.test(name) || /^(?:Thumbs\.db|Desktop\.ini|\.DS_Store)$/i.test(name);
}
function secretLike(text) {
  return /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,})\b/.test(text) ||
    /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text);
}
function localTargets(text) {
  // Do not interpret code samples as links.
  const prose = text.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, '').replace(/`[^`\n]+`/g, '');
  return [...prose.matchAll(/\]\(([^)\s]+)(?:\s+[^)]*)?\)/g), ...prose.matchAll(/\b(?:src|href)=["']([^"']+)["']/g)]
    .map(m => m[1]).filter(target => !/^(?:[a-z][a-z\d+.-]*:|#|\/\/)/i.test(target));
}
function audit(root, { syntax = true, complete = true } = {}) {
  root = path.resolve(root);
  const files = [], excluded = [], errors = [], texts = new Map();
  const fail = (file, issue) => errors.push({ file, issue });
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a,b)=>a.name.localeCompare(b.name))) {
      const absolute = path.join(dir, entry.name), relative = path.relative(root, absolute).split(path.sep).join('/');
      if (entry.isSymbolicLink()) { fail(relative, 'symlink/reparse point is not publishable'); continue; }
      if (entry.isDirectory()) {
        if (excludedDirs.has(entry.name.toLowerCase())) { excluded.push(relative + '/'); continue; }
        if (dir === root && !topDirs.has(entry.name)) fail(relative, 'unlisted top-level directory would be omitted from release');
        walk(absolute); continue;
      }
      if (!entry.isFile()) { fail(relative, 'unsupported filesystem entry'); continue; }
      if (privateFile(entry.name)) { excluded.push(relative); continue; }
      if (dir === root && !topFiles.has(entry.name)) fail(relative, 'unlisted top-level file would be omitted from release');
      const data = fs.readFileSync(absolute), ext = path.extname(entry.name).toLowerCase();
      const item = { path: relative, bytes: data.length, sha256: sha256(data), checks: ['read', 'sha256'] }; files.push(item);
      if (binaryExtensions.has(ext)) {
        const valid = ext === '.png' ? data.length > 24 && data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) :
          ext === '.gif' ? /^GIF8[79]a$/.test(data.subarray(0,6).toString('ascii')) : data.subarray(0,4).toString() === 'RIFF' && data.subarray(8,12).toString() === 'WEBP';
        if (!valid) fail(relative, 'invalid image signature'); else item.checks.push('image-signature');
        continue;
      }
      if (!textExtensions.has(ext) && !['.gitignore','.gitattributes','.npmrc'].includes(entry.name)) { fail(relative, 'unrecognized public file type'); continue; }
      let text;
      try { text = new TextDecoder('utf-8', { fatal: true }).decode(data); } catch { fail(relative, 'invalid UTF-8'); continue; }
      texts.set(relative, text); item.checks.push('utf8', 'credential-pattern-scan');
      if (text.includes('\0')) fail(relative, 'NUL byte in text');
      if (secretLike(text)) fail(relative, 'possible credential/private key (value redacted)');
      if (ext === '.json') {
        try { JSON.parse(text); item.checks.push('json-parse'); } catch { fail(relative, 'invalid JSON'); }
      }
      if (syntax && ['.js','.cjs'].includes(ext)) {
        const check = spawnSync(process.execPath, ['--check', absolute], { encoding: 'utf8', windowsHide: true });
        if (check.status !== 0) fail(relative, 'JavaScript syntax check failed'); else item.checks.push('node-check');
      }
      if (['.md','.html'].includes(ext)) {
        for (const target of localTargets(text)) {
          let dest;
          try {
            // main.cjs serves pet://app/assets/* from the app's assets, not ui/assets.
            const base = relative === 'macos-companion/ui/index.html' && target.startsWith('assets/') ? path.dirname(path.dirname(absolute)) : path.dirname(absolute);
            dest = path.resolve(base, decodeURIComponent(target.split(/[?#]/)[0]));
          } catch { fail(relative, 'invalid local URL'); continue; }
          if (!fs.existsSync(dest)) fail(relative, 'broken local link: ' + target);
        }
        item.checks.push('local-links');
      }
    }
  }
  walk(root);
  if (complete) {
    for (const name of [...topFiles, ...topDirs]) if (!fs.existsSync(path.join(root,name))) fail(name, 'required source entry missing');
  }
  function json(relative) {
    try { return JSON.parse(texts.get(relative)); } catch { fail(relative,'required metadata missing/invalid'); return null; }
  }
  const version = texts.get('VERSION.txt')?.trim();
  if (!/^\d+\.\d+\.\d+$/.test(version || '')) fail('VERSION.txt','invalid version');
  if (complete && texts.has('docs/BEGINNER.md') && texts.has('START-HERE.html')) {
    const { render } = require('./Render-StartHere.cjs');
    if (texts.get('START-HERE.html') !== render(texts.get('docs/BEGINNER.md'),version)) fail('START-HERE.html','offline guide is stale; regenerate from BEGINNER.md');
  }
  if (fs.existsSync(path.join(root,'macos-companion'))) {
    const pkg=json('macos-companion/package.json'), lock=json('macos-companion/package-lock.json');
    if (pkg?.version !== version || lock?.version !== version || lock?.packages?.['']?.version !== version) fail('macos-companion/package.json','version mismatch');
    const manifest=json('macos-companion/assets/manifest.json');
    if (manifest && Object.keys(manifest).length !== 63) fail('macos-companion/assets/manifest.json','expected 63 shared resources');
    for (const [relative, expected] of Object.entries(manifest || {})) {
      if (!/^(?:runtime\/(?:quota-bridge|activity-state|platform-paths|update-check)\.js|assets\/(?:LICENSE\.md|animation-timing\.json|frames\/[a-z-]+\/\d{2}\.png))$/.test(relative)) { fail(relative,'unexpected shared resource'); continue; }
      const bundled = files.find(f=>f.path === 'macos-companion/'+relative);
      if (bundled?.sha256 !== expected) fail(relative,'bundled resource hash mismatch');
      const canonical = relative.startsWith('runtime/') ? 'windows-companion/'+relative.slice(8) : relative==='assets/LICENSE.md' ? 'LICENSE.md' : 'windows-companion/'+relative.slice(7);
      if (complete || fs.existsSync(path.join(root,canonical))) {
        if (files.find(f=>f.path===canonical)?.sha256 !== expected) fail(relative,'canonical resource hash mismatch');
      }
    }
    const declared = new Set(Object.keys(manifest || {}).map(f=>'macos-companion/'+f));
    for (const file of files) if (/^macos-companion\/(?:runtime|assets)\//.test(file.path) && file.path !== 'macos-companion/assets/manifest.json' && !declared.has(file.path)) fail(file.path,'untracked/stale bundled resource');
  }
  for (const runtime of ['windows-companion/quota-bridge.js','macos-companion/runtime/quota-bridge.js']) {
    if (texts.has(runtime) && (!texts.get(runtime).includes("version: '"+version+"'") || !texts.get(runtime).includes("bridgeVersion: '"+version+"'"))) fail(runtime,'bridge version mismatch');
  }
  if (texts.has('codex-native/bjut-yanxiaobei/pet.json') && json('codex-native/bjut-yanxiaobei/pet.json')?.spriteVersionNumber !== 2) fail('codex-native/bjut-yanxiaobei/pet.json','expected v2 sprite format');
  return { version, fileCount: files.length, excluded, errors, files, note: 'Static checks and per-file hashes; not a security certification or Mac hardware test.' };
}
if (require.main === module) {
  try {
    const args=process.argv.slice(2); let root=path.resolve(__dirname,'..'), reportPath, complete=true;
    while (args.length) { const flag=args.shift(); if(flag==='--root' && args[0]) root=args.shift(); else if(flag==='--report' && args[0]) reportPath=args.shift(); else if(flag==='--packaged') complete=false; else throw new Error('Usage: node Audit-Source.cjs [--root directory] [--packaged] [--report file.json]'); }
    const result=audit(root,{complete});
    if(reportPath) { fs.mkdirSync(path.dirname(path.resolve(reportPath)),{recursive:true}); fs.writeFileSync(reportPath,JSON.stringify(result,null,2)+'\n'); }
    for(const error of result.errors) console.error('FAIL '+error.file+': '+error.issue);
    console.log(`${result.errors.length ? 'FAIL' : 'PASS'} v${result.version}: ${result.fileCount} public files read/hashed; ${result.excluded.length} generated/private paths excluded; ${result.errors.length} errors.`);
    process.exitCode=result.errors.length?1:0;
  } catch(error) { console.error(error.message); process.exitCode=1; }
}
module.exports={audit,privateFile,secretLike,localTargets};
