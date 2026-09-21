'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname,'..');
const source = path.resolve(root,'../windows-companion');
const jobs = ['quota-bridge.js','activity-state.js','platform-paths.js','update-check.js'].map(name=>[name,'runtime/'+name]);
jobs.push(['animation-timing.json','assets/animation-timing.json']);
jobs.push(['../LICENSE.md','assets/LICENSE.md']);
const states = {idle:6,'running-right':8,'running-left':8,waving:4,jumping:5,failed:8,waiting:6,running:6,review:6};
for (const [state,count] of Object.entries(states)) for(let n=0;n<count;n++) {
  const relative=`frames/${state}/${String(n).padStart(2,'0')}.png`; jobs.push([relative,'assets/'+relative]);
}
for (const [from,to] of jobs) {
  const target = path.join(root,to), original = path.join(source,from);
  if (fs.existsSync(original)) { fs.mkdirSync(path.dirname(target),{recursive:true}); fs.copyFileSync(original,target); }
  if (!fs.existsSync(target)) throw new Error('Missing bundled resource: '+to+'; extract the complete archive.');
  if (fs.existsSync(original) && !fs.readFileSync(target).equals(fs.readFileSync(original))) throw new Error('Resource drift: '+to);
}
const manifest = Object.fromEntries(jobs.map(([,to])=>[to,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,to))).digest('hex')]));
fs.writeFileSync(path.join(root,'assets','manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(`Prepared/validated ${jobs.length} resources, including all 57 animation frames.`);
