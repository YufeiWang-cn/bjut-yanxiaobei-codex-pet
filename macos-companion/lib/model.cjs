'use strict';
const STATES = new Set(['idle','running','waiting','failed','review','running-left','running-right','waving','jumping']);
const DEFAULTS = {quotaVisible:true,tasksVisible:false,followCodex:false,notify:false,codexApp:'',codexExecutable:'',codexHome:'',logRoot:'',x:null,y:null};
function preferences(input={}) {
  const result={...DEFAULTS};
  for(const key of ['quotaVisible','tasksVisible','followCodex','notify']) if(typeof input[key]==='boolean') result[key]=input[key];
  for(const key of ['codexApp','codexExecutable','codexHome','logRoot']) if(typeof input[key]==='string' && input[key].length<2048 && !input[key].includes('\0')) result[key]=input[key];
  for(const key of ['x','y']) if(Number.isFinite(input[key])) result[key]=Math.round(input[key]);
  return result;
}
function sizeFor(prefs) { return prefs.quotaVisible || prefs.tasksVisible ? {width:410,height:prefs.tasksVisible?(prefs.quotaVisible?374:256):190} : {width:132,height:182}; }
function clampBounds(bounds, area) {
  const width=Math.min(bounds.width,area.width),height=Math.min(bounds.height,area.height);
  return {width,height,x:Math.round(Math.min(Math.max(Number.isFinite(bounds.x)?bounds.x:area.x,area.x),area.x+area.width-width)),
    y:Math.round(Math.min(Math.max(Number.isFinite(bounds.y)?bounds.y:area.y,area.y),area.y+area.height-height))};
}
function threadURI(id) { if(!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)) throw new Error('Invalid task ID'); return 'codex://threads/'+id; }
function fresh(pet, now=Date.now(), alive=true) { const age=now/1000-Number(pet?.fetchedAt); return !!pet && alive && Number.isFinite(age) && age>=-5 && age<=15; }
function remaining(window) { return Number.isFinite(window?.usedPercent) ? Math.round(Math.max(0,Math.min(100,100-window.usedPercent))) : null; }
function dragState(dx,dy) { return Math.abs(dx)>4 && Math.abs(dx)>Math.abs(dy)*1.15 ? (dx>0?'running-right':'running-left') : null; }
function safeSnapshot(pet, now, alive) { if(!fresh(pet,now,alive)) return {petState:'idle',label:'状态离线',counts:null,tasks:[]}; return {...pet,petState:STATES.has(pet.petState)?pet.petState:'idle'}; }
module.exports={preferences,sizeFor,clampBounds,threadURI,fresh,remaining,dragState,safeSnapshot};
