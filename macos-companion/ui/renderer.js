'use strict';
const $=id=>document.getElementById(id);
const durations={};let displayed='idle',frame=0,timer,lastPacket=null,taskKey='',dragging=false,pendingDrag=null,dragFrame=0;
const reduceMotion=matchMedia('(prefers-reduced-motion: reduce)');
const colors={running:'#5ed1e6',waiting:'#f5cf78',failed:'#fa898f',review:'#b5a4ff',idle:'#8ce4be'};
function paintFrame(){
  clearTimeout(timer);const times=durations[displayed]||[420];
  $('sprite').src=`assets/frames/${displayed}/${String(frame%times.length).padStart(2,'0')}.png`;
  if(!reduceMotion.matches)timer=setTimeout(()=>{frame=(frame+1)%times.length;paintFrame();},times[frame%times.length]);
}
function animate(name){if(!durations[name])name='idle';if(displayed===name&&timer)return;displayed=name;frame=0;paintFrame();}
reduceMotion.addEventListener('change',()=>{frame=0;paintFrame();});
function remaining(value){return Number.isFinite(value)?Math.round(Math.max(0,Math.min(100,100-value))):null;}
function countdown(seconds){if(!Number.isFinite(seconds))return '时间未知';const left=Math.max(0,seconds-Date.now()/1000);if(!left)return '待刷新';const minutes=Math.ceil(left/60);return minutes>=1440?`${Math.floor(minutes/1440)}天${Math.floor(minutes%1440/60)}小时`:`${Math.floor(minutes/60)}小时${minutes%60}分`;}
function quota(){const q=lastPacket?.quota;for(const [name,key] of [['five','primary'],['week','secondary']]){
  const percent=remaining(q?.[key]?.usedPercent);$(name+'-value').textContent=percent==null?'-- 剩余':percent+'% 剩余';$(name+'-bar').value=percent??0;$(name+'-time').textContent=countdown(q?.[key]?.resetsAt);
}const credits=q?.resetCredits?.availableCount;$('reset').textContent=Number.isInteger(credits)&&credits>=0?'重置 ×'+credits:'重置 --';
 const age=q?Math.max(0,Math.floor((Date.now()/1000-q.fetchedAt)/60)):null;
 $('quota-status').textContent=lastPacket?.error?.message || (q?`${lastPacket.demo?'演示':String(q.planType||'额度').toUpperCase()} · ${age<1?'刚刚更新':age+'分钟前'}`:'等待额度数据');
 $('quota-status').title=lastPacket?.error?.message||'仅显示订阅额度，不会兑换重置';}
function renderTasks(tasks,known){const key=JSON.stringify([known,tasks.map(t=>[t.id,t.title,t.state,t.label,t.kindLabel])]);if(key===taskKey)return;taskKey=key;
 const list=$('task-list');const scroll=list.scrollTop;list.replaceChildren();
 for(const task of tasks){const row=document.createElement('button');row.className='task';row.dataset.state=task.state;row.title=task.title+' · '+task.label;
  const dot=document.createElement('span');dot.className='indicator';const copy=document.createElement('span');copy.className='copy';
  const kind=task.kindLabel||'Codex';const title=document.createElement('strong');title.textContent=task.title;const label=document.createElement('small');label.textContent=kind+' · '+task.label;
  const arrow=document.createElement('span');arrow.className='chevron';arrow.textContent='›';copy.append(title,label);row.append(dot,copy,arrow);
  row.addEventListener('click',()=>window.pet.openTask(task.id));list.append(row);
 }list.scrollTop=scroll;$('empty').hidden=tasks.length>0;$('empty').textContent=known?'暂时没有活动任务':'状态暂不可用，连接后更新';}
function update(packet){lastPacket=packet;const pet=packet.pet,p=packet.preferences;
 $('quota').hidden=!p.quotaVisible;$('tasks').hidden=!p.tasksVisible;$('panels').hidden=!p.quotaVisible&&!p.tasksVisible;
 $('shell').classList.toggle('pet-only',!p.quotaVisible&&!p.tasksVisible);$('arrow').textContent=p.tasksVisible?'▴':'▾';
 $('caption').textContent=pet.label;$('state-label').textContent=pet.label;$('dot').style.backgroundColor=colors[pet.petState]||colors.idle;
 for(const [id,key] of [['total','total'],['running','running'],['waiting','waiting'],['ready','ready']]){const v=pet.counts?.[key];$(id).textContent=Number.isFinite(v)?(v>99?'99+':String(v)):'--';}
 $('summary').title=pet.counts?`任务 ${pet.counts.total} · 进行 ${pet.counts.running} · 等待 ${pet.counts.waiting} · 完成 ${pet.counts.ready} · 出错 ${pet.counts.failed}`:'状态暂不可用';
 $('task-count').textContent=pet.counts?`${pet.tasks.length} 项`:'-- 项';renderTasks(pet.tasks||[],!!pet.counts);quota();
 if(!dragging||Object.hasOwn(packet,'dragState'))animate(packet.dragState||pet.petState);
 $('toast').hidden=!packet.toast;$('toast').textContent=packet.toast?.text||'';
}
for(const [id,action] of [['refresh','refresh'],['close-quota','toggle-quota'],['summary','toggle-tasks'],['collapse','toggle-tasks'],['clear','clear-ready']])$(id).addEventListener('click',()=>window.pet.action(action));
$('pet-body').addEventListener('dblclick',()=>{if(!dragging)window.pet.action('open');});
document.addEventListener('contextmenu',event=>{event.preventDefault();window.pet.action('menu');});
for(const element of document.querySelectorAll('[data-drag]')){
 element.addEventListener('pointerdown',event=>{if(event.button!==0||event.target.closest('button'))return;pendingDrag={x:event.screenX,y:event.screenY,id:event.pointerId,element};element.setPointerCapture(event.pointerId);window.pet.drag('start');});
 element.addEventListener('pointermove',event=>{if(!pendingDrag)return;if(Math.hypot(event.screenX-pendingDrag.x,event.screenY-pendingDrag.y)>4)dragging=true;if(dragging&&!dragFrame)dragFrame=requestAnimationFrame(()=>{dragFrame=0;window.pet.drag('move');});});
 const end=()=>{if(!pendingDrag)return;pendingDrag=null;cancelAnimationFrame(dragFrame);dragFrame=0;dragging=false;window.pet.drag('end');if(lastPacket)animate(lastPacket.pet.petState);};
 element.addEventListener('pointerup',end);element.addEventListener('pointercancel',end);element.addEventListener('lostpointercapture',end);
}
fetch('assets/animation-timing.json').then(r=>r.json()).then(profile=>{
 Object.assign(durations,profile.companion);paintFrame();window.pet.onState(update);return window.pet.getState();
}).then(update).catch(()=>{$('caption').textContent='资源加载失败';$('state-label').textContent='请完整解压';});
setInterval(quota,1000);
