'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),repo=path.dirname(root);
test('current project versions agree without changing native sprite format',()=>{
  const version=fs.readFileSync(path.join(repo,'VERSION.txt'),'utf8').trim();
  const pkg=JSON.parse(fs.readFileSync(path.join(root,'package.json'))),lock=JSON.parse(fs.readFileSync(path.join(root,'package-lock.json')));
  assert.equal(pkg.version,version);assert.equal(lock.version,version);assert.equal(lock.packages[''].version,version);
  assert.ok(fs.readFileSync(path.join(root,'runtime/quota-bridge.js'),'utf8').includes("version: '"+version+"'"));
  const native=path.join(repo,'codex-native/bjut-yanxiaobei/pet.json');
  if(fs.existsSync(native))assert.equal(JSON.parse(fs.readFileSync(native)).spriteVersionNumber,2);
});
test('offline beginner page is present, script-free and generated from the same guide',()=>{
  const html=fs.readFileSync(path.join(repo,'START-HERE.html'),'utf8');
  assert.ok(html.includes('v'+fs.readFileSync(path.join(repo,'VERSION.txt'),'utf8').trim()));assert.ok(!/<script\b/i.test(html));
  for(const entry of ['Start.vbs','pack:arm64','pack:x64','node --version'])assert.ok(html.includes(entry));
  const renderer=path.join(repo,'scripts/Render-StartHere.cjs');
  if(fs.existsSync(renderer))assert.equal(html,require(renderer).render(fs.readFileSync(path.join(repo,'docs/BEGINNER.md'),'utf8'),fs.readFileSync(path.join(repo,'VERSION.txt'),'utf8').trim()));
});
function files(dir){return fs.existsSync(dir)?fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>['node_modules','dist','.test-output','.git'].includes(e.name)?[]:e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]):[];}
test('documentation links resolve and personal attribution is consistent',()=>{
  const markdown=[...files(path.join(repo,'docs')),...files(path.join(repo,'licenses')),...files(root),...['README.md','LICENSE.md','CHANGELOG.md'].map(n=>path.join(repo,n))].filter(p=>p.endsWith('.md')&&fs.existsSync(p));
  for(const file of markdown){
    const text=fs.readFileSync(file,'utf8');assert.doesNotMatch(text,/社区制作|社区项目|Mac 只能尝试|目前没有 Mac 增强版/);
    const targets=[...text.matchAll(/\]\(([^)\s]+)(?:\s+[^)]*)?\)/g),...text.matchAll(/<img[^>]+src="([^"]+)"/g)].map(m=>m[1]);
    for(const target of targets){if(/^(?:https?:|mailto:|#)/.test(target))continue;assert.ok(fs.existsSync(path.resolve(path.dirname(file),decodeURIComponent(target.split('#')[0]))),file+' -> '+target);}
  }
});
test('Mac entrypoints use LF and the required Electron OS/runtime floor',()=>{
  assert.ok(!fs.readFileSync(path.join(root,'Start.command'),'utf8').includes('\r'));
  const pkg=JSON.parse(fs.readFileSync(path.join(root,'package.json'))),lock=JSON.parse(fs.readFileSync(path.join(root,'package-lock.json')));
  assert.equal(pkg.engines.node,'>=22.12.0');assert.equal(pkg.build.mac.minimumSystemVersion,'13.0');assert.equal(pkg.build.mac.identity,null);
  assert.equal(pkg.devDependencies.electron,lock.packages['node_modules/electron'].version);
  assert.equal(pkg.engines.node,lock.packages[''].engines.node);
  assert.equal(pkg.build.extraResources[0].to,'runtime');assert.ok(pkg.build.files.includes('assets/**'));
  assert.ok(pkg.build.extraResources.some(item=>item.to==='START-HERE.html'));
  const main=fs.readFileSync(path.join(root,'main.cjs'),'utf8');
  assert.ok(main.includes("{label:'使用说明'"));
  assert.ok(!main.includes("{label:'卸载燕小北"));
  const menuOrder=['刷新额度与状态','清除完成 / 错误提醒','使用说明','检查更新'].map(label=>main.indexOf(`{label:'${label}'`));
  assert.ok(menuOrder.every(index=>index>=0)&&menuOrder.every((index,i)=>i===0||menuOrder[i-1]<index));
  assert.ok(main.includes('if(demo||watching||quitting)return;'));
  assert.doesNotMatch(main,/function toggleFollowCodex\(\)\s*\{[^}]*codexWasRunning=null/s);
});
test('renderer isolation, CSP and restricted navigation stay enabled',()=>{
  const main=fs.readFileSync(path.join(root,'main.cjs'),'utf8'),html=fs.readFileSync(path.join(root,'ui/index.html'),'utf8'),renderer=fs.readFileSync(path.join(root,'ui/renderer.js'),'utf8');
  for(const flag of ['contextIsolation:true','sandbox:true','nodeIntegration:false','webSecurity:true'])assert.ok(main.includes(flag));
  assert.ok(main.includes("setWindowOpenHandler(()=>({action:'deny'}))"));assert.ok(main.includes('senderFrame?.url!==entry'));
  assert.ok(html.includes("default-src 'none'"));assert.ok(!renderer.includes('innerHTML'));assert.ok(!html.includes('unsafe-inline'));
  assert.match(renderer,/task\.kindLabel\|\|'Codex'/,'Task rows must display the Codex source label');
});
