const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const appRoot = path.join(__dirname, '..', 'windows-companion');
const source = fs.readFileSync(path.join(appRoot, 'quota-bridge.js'), 'utf8');
const scheduled=[];
const context = vm.createContext({
  require: name => name === 'fs' ? {mkdirSync() {}, writeFileSync() {}} : require(name),
  __dirname: appRoot, Buffer, Date,
  setTimeout: callback => {scheduled.push(callback);return scheduled.length;},
  clearTimeout() {},
  process: {env: {}, platform: 'win32', stdout: {write() {}}},
});
vm.runInContext(source.split("process.stdin.setEncoding('utf8');")[0], context);
const evaluate = code => vm.runInContext(code, context);
evaluate(`
  const now = Date.now();
  currentLogPath = 'fixture.log';
  ['active','waiting','ready','failed'].forEach(id=>sessionReader.classify(id,{source:'vscode'}));
  markActive('active', now);
  markWaiting('waiting', now);
  activity.get('waiting').waitingSince=now-1300;
  markReady('ready', now);
  markFailed('failed', now);
  rememberThreads({data:[{id:'active',name:'桌宠制作',updatedAt:now/1000}]});
  emitPetState();
`);
let pet = JSON.parse(evaluate('JSON.stringify(combinedState.pet)'));
assert.equal(pet.petState, 'waiting');
assert.deepEqual(pet.tasks.map(t => t.state), ['waiting','failed','ready','active']);
assert.deepEqual(pet.counts, {total:4,active:2,running:1,waiting:1,ready:1,failed:1});
assert.equal(pet.tasks[3].title, '桌宠制作');
evaluate("activity.delete('waiting'); emitPetState()");
assert.equal(evaluate('combinedState.pet.petState'), 'failed');
evaluate("activity.delete('failed'); emitPetState()");
assert.equal(evaluate('combinedState.pet.petState'), 'review');
evaluate("activity.delete('ready'); emitPetState()");
assert.equal(evaluate('combinedState.pet.petState'), 'running');
evaluate("activity.delete('active'); markReady('old',Date.now()-READY_TTL_MS-100); emitPetState()");
assert.equal(evaluate('combinedState.pet.petState'), 'idle');
assert.equal(evaluate('combinedState.pet.tasks.length'), 0);
const quota=JSON.parse(evaluate(`JSON.stringify(normalizeQuota({rateLimits:{primary:{usedPercent:23}},rateLimitResetCredits:{availableCount:2,credits:[]}}))`));
assert.equal(quota.primary.usedPercent,23);
assert.equal(quota.resetCredits.availableCount,2);
assert.equal(evaluate('normalizeQuota({rateLimits:{}}).resetCredits'), null, 'Missing reset information must not mean zero');
evaluate(`
  combinedState.quota=normalizeQuota({rateLimits:{primary:{usedPercent:25,resetsAt:100},secondary:{usedPercent:40,resetsAt:200}},rateLimitResetCredits:{availableCount:2,credits:[]}});
  handleMessage({method:'account/rateLimits/updated',params:{rateLimits:{limitId:'codex',primary:{usedPercent:31}}}});
`);
const push=JSON.parse(evaluate('JSON.stringify(combinedState.quota)'));
assert.equal(push.primary.usedPercent,31,'Quota notification should update immediately');
assert.equal(push.primary.resetsAt,100,'Partial notifications must preserve prior window fields');
assert.equal(push.secondary.usedPercent,40,'Partial notifications must preserve the other window');
assert.equal(push.resetCredits.availableCount,2,'Partial notifications must preserve reset credits');
evaluate(`
  initialized=true;
  appServer={stdin:{writable:true,write(){}}};
  readRateLimits();
  const pendingQuotaId=nextId-1;
  handleMessage({method:'account/rateLimits/updated',params:{rateLimits:{limitId:'codex',primary:{usedPercent:32}}}});
  readRateLimits(true);
  handleMessage({id:pendingQuotaId,result:{rateLimits:{primary:{usedPercent:30}}}});
`);
assert.equal(evaluate('combinedState.quota.primary.usedPercent'),32,'Older in-flight reads must not overwrite a newer notification');
assert.equal(evaluate('quotaRefreshQueued'),false,'One manual refresh is queued for the next turn');
assert.ok(scheduled.length>0,'Queued refresh must be scheduled after in-flight request');
evaluate(`
  const eventTime=Date.now();
  sessionReader.classify('quota-task',{source:'vscode'});
  markActive('quota-task',eventTime);emitPetState();
  markReady('quota-task',eventTime+1000);emitPetState();
`);
assert.ok(scheduled.length>1,'A completed task should schedule a prompt quota refresh');
console.log('PASS: task counts, names, four-state priority, completion expiry, quota and reset count');
