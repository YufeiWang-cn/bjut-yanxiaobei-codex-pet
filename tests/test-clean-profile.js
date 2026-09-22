'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawn}=require('node:child_process');
const root=path.resolve(__dirname,'..'),temporary=fs.mkdtempSync(path.join(os.tmpdir(),'yanxiaobei-clean-profile-'));
const profile=path.join(temporary,'new-user','.codex'),sessions=path.join(profile,'sessions','2026','09','22');
const id='10000000-0000-4000-8000-000000000001',turn='10000000-0000-4000-8000-000000000002';
fs.mkdirSync(sessions,{recursive:true});
fs.writeFileSync(path.join(sessions,`rollout-2026-09-22T12-00-00-${id}.jsonl`),[
  JSON.stringify({timestamp:new Date().toISOString(),type:'session_meta',payload:{id,thread_source:'user',originator:'Codex Desktop'}}),
  JSON.stringify({timestamp:new Date().toISOString(),type:'event_msg',payload:{type:'task_started',turn_id:turn}}),
  ''
].join('\n'));
fs.writeFileSync(path.join(profile,'session_index.jsonl'),JSON.stringify({id,thread_name:'全新电脑任务',updated_at:new Date().toISOString()})+'\n');
const child=spawn(process.execPath,[path.join(root,'windows-companion','quota-bridge.js')],{
  cwd:path.join(root,'windows-companion'),windowsHide:true,
  env:{...process.env,CODEX_HOME:profile,USERPROFILE:path.join(temporary,'new-user'),HOME:path.join(temporary,'new-user'),
    LOCALAPPDATA:path.join(temporary,'local'),APPDATA:path.join(temporary,'roaming'),
    YANXIAOBEI_DATA_DIR:path.join(temporary,'data'),PATH:''},stdio:['pipe','pipe','pipe']
});
let buffer='',settled=false;
const timer=setTimeout(()=>finish(new Error('Clean-profile bridge did not expose the running task')),7000);
function finish(error,payload){
  if(settled)return;settled=true;clearTimeout(timer);try{child.kill();}catch{}
  try{if(error)throw error;assert.equal(payload.petState,'running');assert.equal(payload.tasks.length,1);assert.equal(payload.tasks[0].title,'全新电脑任务');
    console.log('PASS: clean user profile detects a running Codex task without desktop logs or prior cache');}
  finally{fs.rmSync(temporary,{recursive:true,force:true});}
}
child.stdout.setEncoding('utf8');child.stdout.on('data',chunk=>{
  buffer+=chunk;let newline;
  while((newline=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,newline);buffer=buffer.slice(newline+1);let value;try{value=JSON.parse(line);}catch{continue}
    if(value.type==='pet-state'&&value.petState==='running')return finish(null,value);}
});
child.stderr.setEncoding('utf8');child.stderr.on('data',chunk=>{if(!settled&&chunk.trim())finish(new Error(chunk.trim()));});
child.on('error',finish);child.on('exit',code=>{if(!settled)finish(new Error('Bridge exited early: '+code));});
