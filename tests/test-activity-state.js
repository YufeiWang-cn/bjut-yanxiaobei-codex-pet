'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { ActivityLedger, SessionActivityReader, sessionEvent } = require('../windows-companion/activity-state');
let cases = 0;
function test(name, run) { run(); cases++; console.log('PASS: ' + name); }
function setup() { const map = new Map(); return { map, ledger: new ActivityLedger(map) }; }
function event(type, at, turn = 'turn-a', extra = {}) {
  return JSON.stringify({ type: 'event_msg', timestamp: new Date(at).toISOString(), payload: { type, turn_id: turn, ...extra } }) + '\n';
}
test('13:13:40 completion without desktop notification overrides thinking', () => {
  const {map, ledger} = setup();
  const start = Date.parse('2026-09-03T05:08:08.949Z');
  ledger.start('task', start);
  ledger.progress('task', Date.parse('2026-09-03T05:13:25Z'));
  ledger.start('task', start + 165, 'turn-a', 'session');
  const e = sessionEvent(event('task_complete', Date.parse('2026-09-03T05:13:40.118Z')));
  ledger.finish('task', e.state, e.at, e.turnId);
  assert.equal(map.get('task').state, 'ready');
});
test('completion also wins over a late reasoning progress event', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a');
  ledger.progress('task', 900); ledger.finish('task', 'ready', 800, 'a');
  ledger.progress('task', 1000); assert.equal(map.get('task').state, 'ready');
});
test('abort clears running and does not create a success/error reminder', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a'); ledger.wait('task', 200);
  ledger.finish('task', 'stopped', 300, 'a'); ledger.progress('task', 400);
  assert.equal(map.size, 0);
});
test('old terminal events cannot finish a newer turn, even when delivered late', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a'); ledger.start('task', 200, 'b');
  ledger.finish('task', 'failed', 900, 'a'); assert.equal(map.get('task').state, 'active');
  ledger.finish('task', 'ready', 300, 'b'); assert.equal(map.get('task').state, 'ready');
});
test('new renderer start remains active before its session ID arrives', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a'); ledger.finish('task', 'ready', 200, 'a');
  ledger.start('task', 300); ledger.finish('task', 'ready', 400, 'a');
  assert.equal(map.get('task').state, 'active');
  ledger.start('task', 450, 'b', 'session'); assert.equal(map.get('task').turnId, 'b');
});
test('replayed start and completion never resurrect dismissed reminders', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a'); ledger.finish('task', 'ready', 200, 'a');
  map.delete('task'); ledger.start('task', 100, 'a', 'session'); ledger.finish('task', 'ready', 400, 'a');
  assert.equal(map.size, 0);
  ledger.start('task', 500, 'b'); assert.equal(map.get('task').state, 'active');
});
test('duplicate completion does not extend reminder expiry', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a'); ledger.finish('task', 'ready', 200, 'a');
  ledger.finish('task', 'ready', 800, 'a'); assert.equal(map.get('task').lastEventAt, 200);
});
test('waiting survives thinking updates; all identified approvals must resolve', () => {
  const {map, ledger} = setup(); ledger.start('task', 100, 'a');
  ledger.wait('task', 200, 'one'); ledger.wait('task', 201, 'two'); ledger.progress('task', 300);
  assert.equal(map.get('task').state, 'waiting'); ledger.progress('task', 400, true, 'one');
  assert.equal(map.get('task').state, 'waiting'); ledger.progress('task', 500, true, 'two');
  assert.equal(map.get('task').state, 'active');
});
test('unrelated/unidentified approval resolution cannot dismiss known approval', () => {
  const {map, ledger} = setup(); ledger.start('task', 100); ledger.wait('task', 200, 'one');
  ledger.progress('task', 300, true, 'other'); ledger.progress('task', 400, true);
  assert.equal(map.get('task').state, 'waiting');
  ledger.finish('task', 'ready', 500); assert.equal(map.get('task').state, 'ready');
});
test('anonymous waiting resolves explicitly; stale waiting cannot reopen completion', () => {
  const {map, ledger} = setup(); ledger.start('task', 100); ledger.wait('task', 200);
  ledger.progress('task', 300, true); assert.equal(map.get('task').state, 'active');
  ledger.finish('task', 'ready', 400); ledger.wait('task', 500); assert.equal(map.get('task').state, 'ready');
});
test('concurrent tasks remain independent', () => {
  const {map, ledger} = setup(); ledger.start('one', 100, 'a'); ledger.start('two', 100, 'b');
  ledger.finish('one', 'stopped', 200, 'a'); assert.equal(map.get('two').state, 'active');
});
test('only structured lifecycle envelopes count; message/tool errors do not', () => {
  assert.equal(sessionEvent('{invalid'), null);
  assert.equal(sessionEvent(JSON.stringify({ type: 'response_item', payload: {type:'task_complete',turn_id:'a'},timestamp:new Date().toISOString()})), null);
  assert.equal(sessionEvent(event('error', 100)), null);
  assert.equal(sessionEvent(event('task_complete', 100, null)), null);
  assert.equal(sessionEvent(event('task_failed', 100)).state, 'failed');
  assert.equal(sessionEvent(event('turn_aborted', 100)).state, 'stopped');
});

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'yanxiaobei-state-test-'));
try {
  const id = '00000000-0000-4000-8000-000000000001';
  const file = path.join(temp, 'rollout-2026-09-03T13-08-09-' + id + '.jsonl');
  const header = JSON.stringify({type:'session_meta',payload:{id,source:'vscode'}})+'\n';
  test('restart learns completed history without a new completion reminder', () => {
    fs.writeFileSync(file, header + event('task_started', 100) + event('task_complete', 300));
    const {map, ledger} = setup(); const reader = new SessionActivityReader(temp, ledger);
    assert.equal(reader.poll([id]), 1); assert.equal(map.size, 0); assert.equal(ledger.latest.get(id).state, 'ready');
  });
  test('incremental JSON split over writes waits for newline', () => {
    fs.writeFileSync(file, header + event('task_started', 100));
    const {map, ledger} = setup(); const reader = new SessionActivityReader(temp, ledger); reader.poll([id]);
    const completion = event('task_complete', 300); fs.appendFileSync(file, completion.slice(0, 17)); reader.poll([id]);
    assert.equal(map.get(id).state, 'active'); fs.appendFileSync(file, completion.slice(17)); reader.poll([id]);
    assert.equal(map.get(id).state, 'ready');
  });
  test('file truncation recovers new turn without replaying old success', () => {
    fs.writeFileSync(file, header + event('task_started', 100) + event('task_complete', 300));
    const {map, ledger} = setup(); const reader = new SessionActivityReader(temp, ledger); reader.poll([id]);
    fs.writeFileSync(file, header + event('task_started', 1000, 'b')); reader.poll([id]);
    assert.equal(map.get(id).state, 'active'); assert.equal(map.get(id).turnId, 'b');
  });
  test('bounded startup tail finds completion beyond a huge tool payload', () => {
    fs.writeFileSync(file, header + event('task_started', 100) + JSON.stringify({type:'response_item',text:'x'.repeat(5000)}) + '\n' + event('task_complete', 300));
    const {map, ledger} = setup(); const reader = new SessionActivityReader(temp, ledger); reader.limit = 1024;
    reader.poll([id]); assert.equal(map.size, 0); assert.equal(ledger.latest.get(id).state, 'ready');
  });
  test('large incremental lines and UTF-8 split do not prevent the next lifecycle event', () => {
    fs.writeFileSync(file, header + event('task_started', 100));
    const {map, ledger} = setup(); const reader = new SessionActivityReader(temp, ledger); reader.limit = 256; reader.poll([id]);
    fs.appendFileSync(file, JSON.stringify({type:'response_item',text:'燕'.repeat(700)}) + '\n' + event('task_complete', 300));
    for (let n=0; n<15; n++) reader.poll([id]);
    assert.equal(map.get(id).state, 'ready');
  });
  test('unobserved sessions are not included in the activity tray', () => {
    const {map, ledger} = setup(); const reader = new SessionActivityReader(temp, ledger);
    reader.poll([]); assert.equal(map.size, 0);
  });
  test('missing/unreadable session does not imply task completion', () => {
    const {map, ledger} = setup(); ledger.start('missing', 100);
    const reader = new SessionActivityReader(temp, ledger); reader.poll(['missing']);
    assert.equal(map.get('missing').state, 'active');
  });
} finally { fs.rmSync(temp, {recursive:true, force:true}); }

const appRoot = path.join(__dirname, '../windows-companion');
const source = fs.readFileSync(path.join(appRoot, 'quota-bridge.js'), 'utf8').split("process.stdin.setEncoding('utf8');")[0];
function bridgeContext() {
  const context = vm.createContext({ require:n=>n==='fs'?{mkdirSync(){},writeFileSync(){}}:require(n),
    __dirname:appRoot, Buffer, Date, process:{env:{},platform:'win32',stdout:{write(){}}} });
  vm.runInContext(source, context);
  vm.runInContext("['a','b','00000000-0000-4000-8000-000000000001'].forEach(id=>sessionReader.classify(id,{source:'vscode'}))", context);
  return code=>vm.runInContext(code, context);
}
test('success and error reminders both expire after 10 minutes', () => {
  const run = bridgeContext(); run("markReady('a',Date.now()-READY_TTL_MS-1);markFailed('b',Date.now()-READY_TTL_MS-1);emitPetState()");
  assert.equal(run('combinedState.pet.counts.total'), 0);
});
test('real desktop interrupt pattern clears running', () => {
  const run = bridgeContext(); const id='00000000-0000-4000-8000-000000000001';
  run(`processLogLine(${JSON.stringify(new Date().toISOString()+' info Reasoning summary turn-start config resolved conversationId='+id)})`);
  run(`processLogLine(${JSON.stringify(new Date().toISOString()+' info response_routed conversationId='+id+' errorCode=null method=turn/interrupt')});emitPetState()`);
  assert.equal(run('combinedState.pet.counts.running'), 0);
});
test('log rotation replay does not clear other tracked tasks or resurrect reminders', () => {
  const run=bridgeContext(); run("markActive('a',Date.now());markReady('b',Date.now());activity.delete('b');markReady('b',Date.now());emitPetState()");
  assert.equal(run('combinedState.pet.counts.total'),1);
  assert.equal(source.includes('activity.clear()'),false);
});
test('activity heartbeat continues without resetting the animation state', () => {
  const run=bridgeContext(); run("markActive('a',Date.now());emitPetState();combinedState.updatedAt=0;lastHeartbeatAt=0;emitPetState()");
  assert.ok(run('combinedState.updatedAt') > 0); assert.equal(run('combinedState.pet.petState'),'running');
});
test('quota/bridge errors are not silently cleared by unrelated activity heartbeat', () => {
  const run=bridgeContext(); run("persist({type:'error',scope:'bridge',message:'offline'});emitPetState()");
  assert.equal(run('combinedState.error.scope'),'bridge');
});
test('resumed failed/interrupted/completed turns never become thinking from older session starts', () => {
  for (const [status, expected] of [['failed','idle'],['interrupted','idle'],['completed','idle']]) {
    const run=bridgeContext(); const id='00000000-0000-4000-8000-000000000001';
    const turn='00000000-0000-4000-8000-000000000002'; const now=Date.now();
    run(`processLogLine(${JSON.stringify(new Date(now).toISOString()+' info maybe_resume_success conversationId='+id+' latestTurnId='+turn+' latestTurnStatus='+status)})`);
    run(`ledger.start('${id}',${now-10000},'${turn}','session');emitPetState()`);
    assert.equal(run('combinedState.pet.petState'),expected);
  }
});
console.log(`Activity regression: ${cases} cases passed; no real task or account changed.`);
