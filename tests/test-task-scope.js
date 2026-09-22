'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { ActivityLedger, SessionActivityReader, threadScope } = require('../windows-companion/activity-state');
const appRoot = path.resolve(__dirname, '../windows-companion');
const source = fs.readFileSync(path.join(appRoot, 'quota-bridge.js'), 'utf8').split("process.stdin.setEncoding('utf8');")[0];
let cases = 0;
function test(name, fn) { fn(); cases++; console.log('PASS: ' + name); }
function bridge(platform = 'win32') {
  const context = vm.createContext({ require: n => n === 'fs' ? {mkdirSync(){},writeFileSync(){}} : require(n),
    __dirname: appRoot, Buffer, Date, process: {env:{},platform,stdout:{write(){}}} });
  vm.runInContext(source, context);
  return code => vm.runInContext(code, context);
}
const root = '00000000-0000-4000-8000-000000000001';
const child = '00000000-0000-4000-8000-000000000002';
const turn = '00000000-0000-4000-8000-000000000003';
function log(run, message, at = Date.now()) { run(`processLogLine(${JSON.stringify(new Date(at).toISOString()+' info '+message)});emitPetState()`); }
function trust(run, id = root) { run(`rememberThreads({data:[{id:'${id}',source:'vscode',updatedAt:Date.now()/1000}]})`); }

test('provenance rejects child/guardian/review/compact/internal/ephemeral sessions', () => {
  for (const source of [{subagent:{thread_spawn:{parent_thread_id:root}}},{subagent:{other:'guardian'}},'subAgentReview','subAgentCompact','ephemeral','internal','titleGeneration','ambientSuggestion']) {
    assert.equal(threadScope({source}), 'excluded');
  }
  assert.equal(threadScope({source:'vscode',parent_thread_id:root}), 'excluded');
  assert.equal(threadScope({source:'vscode',parentThreadId:root}), 'excluded');
  assert.equal(threadScope({source:'vscode',ephemeral:true}), 'excluded');
  assert.equal(threadScope({name:'Looks like a real task'}), 'unknown');
  assert.equal(threadScope({source:'new-unknown-format'}), 'root');
  assert.equal(threadScope({source:{desktop:{channel:'beta'}},originator:'Codex Desktop'}), 'root');
  assert.equal(threadScope({source:{unknown:true}}), 'unknown');
  for (const source of ['cli','vscode','exec','appServer','codex-desktop-v2']) assert.equal(threadScope({source}), 'root');
});
test('rename/title and background suggestion unknown-conversation events are invisible', () => {
  const run = bridge();
  log(run, 'Received turn/started for unknown conversation conversationId='+child);
  assert.equal(run('combinedState.pet.counts.total'), 0);
  log(run, 'Received turn/completed for unknown conversation conversationId='+child);
  assert.equal(run('combinedState.pet.petState'), 'idle');
});
test('a title alone never promotes an internal event into a user task', () => {
  const run = bridge(); run(`threadMetadata.set('${child}',{title:'Background task'})`);
  log(run, 'Received turn/started for unknown conversation conversationId='+child);
  assert.equal(run('combinedState.pet.tasks.length'), 0);
});
test('late root identification exposes an already-running real turn', () => {
  const run = bridge();
  log(run, 'Received turn/started for unknown conversation conversationId='+root);
  assert.equal(run('combinedState.pet.counts.total'), 0);
  trust(run); run('emitPetState()');
  assert.equal(run('combinedState.pet.counts.running'), 1);
});
for (const platform of ['win32','darwin']) test(platform+' shows only the parent while child/guardian runs or completes', () => {
  const run = bridge(platform); trust(run);
  run(`rememberThreads({data:[{id:'${child}',source:{subagent:{other:'guardian'}},parentThreadId:'${root}',updatedAt:Date.now()/1000}]})`);
  log(run, 'Reasoning summary turn-start config resolved conversationId='+root);
  log(run, 'Received turn/started for unknown conversation conversationId='+child);
  log(run, 'Received turn/completed for unknown conversation conversationId='+child);
  assert.equal(run('combinedState.pet.counts.total'), 1);
  assert.equal(run('combinedState.pet.petState'), 'running');
  assert.equal(run(`observedThreads.has('${child}') && sessionReader.isRoot('${child}')`), false);
});
test('late negative metadata removes provisional child activity and cannot be overwritten by a title', () => {
  const run = bridge(); trust(run, child); log(run, 'Received turn/started for unknown conversation conversationId='+child);
  run(`rememberThreads({data:[{id:'${child}',source:'vscode',parentThreadId:'${root}'}]});emitPetState()`);
  assert.equal(run('combinedState.pet.counts.total'), 0);
  trust(run, child); run('emitPetState()'); assert.equal(run('combinedState.pet.counts.total'), 0);
});
test('opening finished/failed/interrupted history never creates a fresh reminder', () => {
  for (const status of ['completed','failed','interrupted']) {
    const run = bridge(); trust(run);
    log(run, `maybe_resume_success conversationId=${root} latestTurnId=${turn} latestTurnStatus=${status}`);
    run(`ledger.start('${root}',Date.now()-10000,'${turn}','session');emitPetState()`);
    assert.equal(run('combinedState.pet.petState'), 'idle');
  }
});
test('a resume snapshot clears a matching stuck turn without a new completion notification', () => {
  const run = bridge(); trust(run);
  run(`ledger.start('${root}',Date.now()-1000,'${turn}','session')`);
  log(run, `maybe_resume_success conversationId=${root} latestTurnId=${turn} latestTurnStatus=completed`);
  assert.equal(run('combinedState.pet.counts.total'), 0);
});
test('old resume cannot finish a new turn awaiting its session ID', () => {
  const run = bridge(); trust(run); run(`ledger.start('${root}',Date.now())`);
  log(run, `maybe_resume_success conversationId=${root} latestTurnId=${turn} latestTurnStatus=completed`);
  assert.equal(run('combinedState.pet.petState'), 'running');
});
test('genuine completion still notifies and reopened history does not renew its timestamp', () => {
  const run = bridge(); trust(run);
  run(`ledger.start('${root}',Date.now(), '${turn}', 'session');ledger.finish('${root}','ready',Date.now()+1,'${turn}');emitPetState()`);
  const at=run(`activity.get('${root}').lastEventAt`);
  log(run, `maybe_resume_success conversationId=${root} latestTurnId=${turn} latestTurnStatus=completed`, Date.now()+1000);
  assert.equal(run('combinedState.pet.petState'), 'review');
  assert.equal(run(`activity.get('${root}').lastEventAt`), at);
  run(`activity.delete('${root}')`);
  log(run, `maybe_resume_success conversationId=${root} latestTurnId=${turn} latestTurnStatus=completed`, Date.now()+2000);
  assert.equal(run('combinedState.pet.counts.total'), 0);
});
test('replaying pre-launch desktop completion does not display a new notification', () => {
  const run = bridge(); trust(run);
  log(run, 'Received turn/started for unknown conversation conversationId='+root, Date.now()-5000);
  log(run, 'Received turn/completed for unknown conversation conversationId='+root, Date.now()-3000);
  assert.equal(run('combinedState.pet.counts.total'), 0);
});

const temp=fs.mkdtempSync(path.join(os.tmpdir(),'yanxiaobei-scope-test-'));
function fileFor(id){return path.join(temp,'rollout-2026-09-03T10-00-00-'+id+'.jsonl');}
function header(id,extra={}){return JSON.stringify({type:'session_meta',payload:{id,source:'vscode',...extra}})+'\n';}
function event(type,at,turnId=turn){return JSON.stringify({type:'event_msg',timestamp:new Date(at).toISOString(),payload:{type,turn_id:turnId}})+'\n';}
try {
  test('session metadata excludes all child lifecycles before they can modify the parent', () => {
    for(const extra of [{source:{subagent:{other:'guardian'}}},{parent_thread_id:root},{ephemeral:true}]){
      fs.writeFileSync(fileFor(child),header(child,extra)+event('task_started',100)+event('task_complete',200));
      const activity=new Map(),ledger=new ActivityLedger(activity),reader=new SessionActivityReader(temp,ledger);
      ledger.start(root,100,turn); reader.poll([child]);
      assert.equal(activity.size,1);assert.equal(activity.get(root).state,'active');assert.equal(reader.isRoot(child),false);
    }
  });
  test('opening a recently finished session silently baselines its historical lifecycle', () => {
    fs.writeFileSync(fileFor(root),header(root)+event('task_started',Date.now()-100)+event('task_complete',Date.now()-10));
    const activity=new Map(),ledger=new ActivityLedger(activity),reader=new SessionActivityReader(temp,ledger);
    assert.equal(reader.poll([root]),1);assert.equal(activity.size,0);assert.equal(ledger.latest.get(root).state,'ready');
    reader.poll([root]);assert.equal(activity.size,0);
  });
  test('a running session survives baseline and later completion is displayed', () => {
    fs.writeFileSync(fileFor(root),header(root)+event('task_started',100));
    const activity=new Map(),ledger=new ActivityLedger(activity),reader=new SessionActivityReader(temp,ledger);
    reader.poll([root]);assert.equal(activity.get(root).state,'active');
    fs.appendFileSync(fileFor(root),event('task_complete',Date.now()));reader.poll([root]);
    assert.equal(activity.get(root).state,'ready');
  });
  test('quick real turn completed before first session scan retains its live reminder', () => {
    const activity=new Map(),ledger=new ActivityLedger(activity),reader=new SessionActivityReader(temp,ledger);
    const at=Date.now()+10;ledger.start(root,at,turn);
    fs.writeFileSync(fileFor(root),header(root)+event('task_started',at)+event('task_complete',at+1));
    reader.poll([root]);assert.equal(activity.get(root).state,'ready');
  });
  test('recent session discovery finds running roots without desktop logs', () => {
    const recent='00000000-0000-4000-8000-000000000009';
    fs.writeFileSync(fileFor(recent),header(recent,{source:'codex-desktop-v2'})+event('task_started',Date.now(),turn));
    const activity=new Map(),ledger=new ActivityLedger(activity),reader=new SessionActivityReader(temp,ledger);
    const ids=reader.recentIds(Date.now(),60_000);
    assert.ok(ids.includes(recent));reader.poll(new Set(ids));
    assert.equal(reader.isRoot(recent),true);assert.equal(activity.get(recent).state,'active');
  });
  test('partial or mismatched session metadata is never accepted as a root', () => {
    for(const prefix of ['{"type":"session_meta"',header(child),JSON.stringify({type:'session_meta',payload:{id:root}})+'\n']){
      fs.writeFileSync(fileFor(root),prefix+event('task_started',100));
      const activity=new Map(),ledger=new ActivityLedger(activity),reader=new SessionActivityReader(temp,ledger);
      assert.equal(reader.poll([root]),0);assert.equal(activity.size,0);
    }
  });
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
console.log(`Task scope regression: ${cases} cases passed; no account or real task changed.`);
