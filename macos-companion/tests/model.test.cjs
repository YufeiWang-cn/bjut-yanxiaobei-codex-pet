'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const root=path.resolve(__dirname,'..');
const model=require('../lib/model.cjs');
const paths=require('../runtime/platform-paths.js');
test('settings preserve explicit false, discard unknown and invalid values',()=>{
  const p=model.preferences({quotaVisible:false,tasksVisible:true,x:-1.4,y:NaN,codexApp:'a\0b',extra:'unsafe'});
  assert.equal(p.quotaVisible,false);assert.equal(p.tasksVisible,true);assert.equal(p.x,-1);assert.equal(p.y,null);assert.equal(p.codexApp,'');assert.equal(p.extra,undefined);
  assert.equal(model.preferences().followCodex,true);assert.equal(model.preferences().launchAtLogin,true);
  assert.equal(model.preferences({followCodex:false,launchAtLogin:false}).followCodex,false);
  assert.equal(model.preferences({followCodex:false,launchAtLogin:false}).launchAtLogin,false);
  assert.equal(model.preferences().notify,false);
});
test('four panel visibility combinations have bounded explicit sizes',()=>{
  assert.deepEqual(model.sizeFor({quotaVisible:false,tasksVisible:false}),{width:132,height:182});
  assert.deepEqual(model.sizeFor({quotaVisible:true,tasksVisible:false}),{width:410,height:190});
  assert.deepEqual(model.sizeFor({quotaVisible:false,tasksVisible:true}),{width:410,height:256});
  assert.deepEqual(model.sizeFor({quotaVisible:true,tasksVisible:true}),{width:410,height:374});
});
test('all edges, negative-coordinate monitor and removed display clamp safely',()=>{
  for(const area of [{x:0,y:24,width:1440,height:840},{x:-1920,y:-800,width:1920,height:1080},{x:0,y:0,width:200,height:120}])
    for(const x of [-5000,-10,0,100,9999])for(const y of [-5000,0,500,9999]){
      const b=model.clampBounds({x,y,width:410,height:374},area);
      assert.ok(b.x>=area.x&&b.y>=area.y&&b.x+b.width<=area.x+area.width&&b.y+b.height<=area.y+area.height);
    }
});
test('vertical dragging never invents left or right animation',()=>{
  assert.equal(model.dragState(0,-30),null);assert.equal(model.dragState(0,30),null);assert.equal(model.dragState(5,30),null);
  assert.equal(model.dragState(-15,2),'running-left');assert.equal(model.dragState(15,2),'running-right');
});
test('UUID deep links reject arbitrary URLs, shell strings and malformed IDs',()=>{
  assert.equal(model.threadURI('00000000-0000-4000-8000-000000000001'),'codex://threads/00000000-0000-4000-8000-000000000001');
  for(const value of ['https://example.com','bad;open','../../foo','',null,{},'00000000-0000-4000-8000-000000000001?x=1'])assert.throws(()=>model.threadURI(value));
});
test('missing quota is unknown, distinct from exhausted and full quota',()=>{
  assert.equal(model.remaining(null),null);assert.equal(model.remaining({usedPercent:0}),100);
  assert.equal(model.remaining({usedPercent:100}),0);assert.equal(model.remaining({usedPercent:103}),0);assert.equal(model.remaining({usedPercent:-2}),100);
});
test('heartbeat expiry and bridge exit clear thinking without inventing completion',()=>{
  const now=100000,pet={fetchedAt:99,petState:'running',label:'思考中',counts:{running:1},tasks:[{}]};
  assert.equal(model.safeSnapshot(pet,now,true).petState,'running');
  for(const [stamp,alive] of [[now+16000,true],[now,false],[0,true]]){
    const p=model.safeSnapshot(pet,stamp,alive);assert.equal(p.label,'状态离线');assert.equal(p.counts,null);assert.deepEqual(p.tasks,[]);assert.equal(p.petState,'idle');
  }
});
test('restored fresh snapshots resume all supported task states',()=>{
  for(const name of ['idle','running','waiting','failed','review'])assert.equal(model.safeSnapshot({fetchedAt:100,petState:name},100000,true).petState,name);
  assert.equal(model.safeSnapshot({fetchedAt:100,petState:'../../bad'},100000,true).petState,'idle');
});
test('macOS data paths and explicit overrides; Windows default unchanged',()=>{
  assert.equal(paths.dataDirectory('darwin',{},'/Users/test'),path.join('/Users/test','Library','Application Support','BJUT-YanXiaoBei'));
  assert.equal(paths.dataDirectory('darwin',{YANXIAOBEI_DATA_DIR:'chosen'},'/Users/test'),'chosen');
  assert.equal(paths.dataDirectory('win32',{LOCALAPPDATA:'local'},'home'),path.join('local','BJUT-YanXiaoBei'));
  assert.equal(paths.macCodexCandidates({CODEX_EXE:'chosen',CODEX_APP_PATH:'/Custom/Codex.app'},'/Users/test')[0],'chosen');
  assert.ok(paths.macCodexCandidates({CODEX_APP_PATH:'/Custom/Codex.app'},'/Users/test').includes(path.join('/Custom/Codex.app','Contents','Resources','codex')));
});
test('Mac log fallback and override include flat and dated paths',()=>{
  const list=paths.desktopLogDirectories('darwin',{CODEX_LOG_DIR:'logs'},'/Users/test',new Date(2026,8,3).getTime());
  assert.deepEqual(list,['logs',path.join('logs','2026','09','03'),path.join('logs','2026','09','02')]);
  assert.ok(paths.desktopLogDirectories('darwin',{},'/Users/test').some(p=>p.includes(path.join('Library','Logs','Codex'))));
});
test('all 63 bundled resources match their checksums and shared source',()=>{
  const manifest=JSON.parse(fs.readFileSync(path.join(root,'assets/manifest.json')));
  assert.equal(Object.keys(manifest).length,63);
  for(const [name,hash] of Object.entries(manifest))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex'),hash,name);
  for(const name of ['quota-bridge.js','activity-state.js','platform-paths.js']){
    const canonical=path.join(root,'../windows-companion',name);
    if(fs.existsSync(canonical))assert.ok(fs.readFileSync(canonical).equals(fs.readFileSync(path.join(root,'runtime',name))),name);
  }
  const timing=JSON.parse(fs.readFileSync(path.join(root,'assets/animation-timing.json')));
  assert.equal(timing.companion.failed.reduce((a,b)=>a+b,0),3600);
});
test('utility-process payload transport; recent root session discovery, no subagents',()=>{
  const runtime=path.join(root,'runtime'),out=[];
  const context=vm.createContext({__dirname:runtime,Buffer,Date,require:name=>name==='fs'?{mkdirSync(){},writeFileSync(){}}:require(name),
    process:{platform:'darwin',env:{},parentPort:{postMessage:data=>out.push(data)}}});
  vm.runInContext(fs.readFileSync(path.join(runtime,'quota-bridge.js'),'utf8').split("process.stdin.setEncoding('utf8');")[0],context);
  vm.runInContext(`rememberThreads({data:[{id:'recent',source:'vscode',updatedAt:Date.now()/1000},{id:'old',source:'vscode',updatedAt:1},{id:'unknown',updatedAt:Date.now()/1000},{id:'agent',updatedAt:Date.now()/1000,source:{subAgent:{}}}]});persist({type:'snapshot',primary:null});`,context);
  assert.equal(out[0].type,'snapshot');assert.equal(vm.runInContext('observedThreads.has("recent")',context),true);
  assert.equal(vm.runInContext('observedThreads.has("old")||observedThreads.has("agent")||observedThreads.has("unknown")',context),false);
});
