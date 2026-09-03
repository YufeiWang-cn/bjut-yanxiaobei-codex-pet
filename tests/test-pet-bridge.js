const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const appRoot = path.join(__dirname, '..', 'windows-companion');
const source = fs.readFileSync(path.join(appRoot, 'quota-bridge.js'), 'utf8');
const context = vm.createContext({
  require: name => name === 'fs' ? {mkdirSync() {}, writeFileSync() {}} : require(name),
  __dirname: appRoot, Buffer, Date,
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
console.log('PASS: task counts, names, four-state priority, completion expiry, quota and reset count');
