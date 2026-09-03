'use strict';
const {app,BrowserWindow,Menu,Tray,nativeImage,ipcMain,protocol,screen,utilityProcess,dialog,shell,Notification}=require('electron');
const fs=require('fs'),path=require('path'),os=require('os');
const {execFile}=require('child_process');
const {preferences,sizeFor,clampBounds,threadURI,dragState,safeSnapshot,remaining}=require('./lib/model.cjs');
const demo=process.argv.includes('--demo'),smoke=process.argv.includes('--smoke-test');
const root=__dirname;
const dataRoot=process.env.YANXIAOBEI_DATA_DIR || path.join(os.homedir(),'Library','Application Support','BJUT-YanXiaoBei');
app.setPath('userData',dataRoot);
protocol.registerSchemesAsPrivileged([{scheme:'pet',privileges:{standard:true,secure:true,supportFetchAPI:true}}]);
let win,tray,bridge,heartbeat,watcher,demoTimer,drag=null,quitting=false,watching=false,codexWasRunning=null;
let state={pet:null,quota:null,error:null},prefs=preferences(),toast=null;
const entry='pet://app/index.html';
const settingsFile=path.join(dataRoot,'mac-settings.json');
function save() { fs.mkdirSync(dataRoot,{recursive:true}); fs.writeFileSync(settingsFile,JSON.stringify(prefs,null,2)+'\n',{mode:0o600}); }
function packet() { return {pet:safeSnapshot(state.pet,Date.now(),demo||!!bridge),quota:state.quota,error:state.error,
  preferences:{quotaVisible:prefs.quotaVisible,tasksVisible:prefs.tasksVisible},toast:toast&&toast.until>Date.now()?toast:null,demo}; }
function broadcast() {
  if(win&&!win.isDestroyed()) win.webContents.send('pet:state',packet());
  if(tray) { const q=remaining(state.quota?.primary); tray.setToolTip('燕小北 · '+packet().pet.label+(q==null?'':` · 5H 剩余 ${q}%`)); }
}
function notice(text) { toast={text:String(text).slice(0,160),until:Date.now()+7000}; broadcast(); }
function boundsFor(size) {
  const old=win?win.getBounds():{x:prefs.x,y:prefs.y,...size};
  const display=Number.isFinite(old.x)&&Number.isFinite(old.y)?screen.getDisplayMatching({...old,...size}):screen.getPrimaryDisplay();
  const area=display.workArea;
  return clampBounds({x:old.x??area.x+area.width-size.width-24,y:old.y??area.y+area.height-size.height-32,...size},area);
}
function layout() { win.setBounds(boundsFor(sizeFor(prefs)),false); savePosition(); broadcast(); rebuildMenus(); }
function savePosition() { if(!win||win.isDestroyed())return; const {x,y}=win.getBounds(); prefs.x=x;prefs.y=y;save(); }
function trusted(event) { if(event.sender!==win?.webContents || event.senderFrame?.url!==entry) throw new Error('Untrusted IPC sender'); }
function execute(file,args) { return new Promise((resolve,reject)=>execFile(file,args,{timeout:5000,maxBuffer:1024*1024,windowsHide:true},(error,stdout)=>error?reject(error):resolve(stdout))); }
function codexApp() {
  const candidates=[prefs.codexApp,process.env.CODEX_APP_PATH,'/Applications/Codex.app',path.join(os.homedir(),'Applications','Codex.app'),'/Applications/ChatGPT.app',path.join(os.homedir(),'Applications','ChatGPT.app')];
  return candidates.find(p=>p&&p.endsWith('.app')&&fs.existsSync(p)) || null;
}
async function openCodex() {
  if(demo) return notice('演示模式：不会打开真实 Codex');
  const target=codexApp(); if(!target) throw new Error('未找到 Codex.app，请从右键菜单选择你的 Codex 应用。');
  // Activate the existing app, never navigate to a new task/home URL.
  await execute('/usr/bin/open',['-a',target]);
}
async function openTask(id) {
  const uri=threadURI(id);
  if(!state.pet?.tasks?.some(task=>task.id===id)) throw new Error('任务已不在当前活动列表中，请刷新后再试。');
  if(demo) return notice('演示模式：不会打开真实任务');
  await shell.openExternal(uri);
}
async function choose(kind) {
  if(demo) return notice('演示模式不会改变本机配置');
  const chosen=await dialog.showOpenDialog(win,{title:kind==='app'?'选择 Codex.app':'选择 Codex CLI 可执行文件',
    properties:kind==='app'?['openFile','openDirectory']:['openFile']});
  if(chosen.canceled) return;
  const selected=chosen.filePaths[0];
  if(kind==='app') { if(!selected.endsWith('.app')) throw new Error('请选择 .app 应用包');prefs.codexApp=selected; }
  else { fs.accessSync(selected,fs.constants.X_OK); if(!fs.statSync(selected).isFile()) throw new Error('请选择可执行文件');prefs.codexExecutable=selected; }
  save(); await restartBridge(); notice('路径已更新，正在重新连接');
}
async function loginToggle() {
  if(!app.isPackaged||demo) return notice('请先在 Mac 打包安装 .app；源码/演示模式不设置登录项');
  const enabled=app.getLoginItemSettings().openAtLogin;
  app.setLoginItemSettings({openAtLogin:!enabled});
  const result=app.getLoginItemSettings();
  notice(result.status==='requires-approval'?'请在 macOS 登录项设置中确认授权':result.openAtLogin?'已设置登录时启动；请重登录验证':'登录启动已关闭');
  rebuildMenus();
}
function menuClick(action) { return ()=>Promise.resolve(action()).catch(error=>notice(error.message)); }
function rebuildMenus() {
  const template=[
    {label:'BJUT 燕小北 · 个人制作',enabled:false},
    {label:'显示桌宠 / 找回位置',click:()=>{win.show();layout();}},
    {label:'打开 Codex（保留原页面）',click:menuClick(openCodex)},
    {type:'separator'},
    {label:'显示额度气泡',type:'checkbox',checked:prefs.quotaVisible,click:()=>{prefs.quotaVisible=!prefs.quotaVisible;layout();}},
    {label:'显示任务队列',type:'checkbox',checked:prefs.tasksVisible,click:()=>{prefs.tasksVisible=!prefs.tasksVisible;layout();}},
    {label:'跟随 Codex 显示 / 隐藏',type:'checkbox',checked:prefs.followCodex,enabled:!demo,click:()=>{prefs.followCodex=!prefs.followCodex;codexWasRunning=null;save();checkCodex();rebuildMenus();}},
    {label:'登录时启动（安装的 .app）',type:'checkbox',checked:!demo&&app.isPackaged&&app.getLoginItemSettings().openAtLogin,enabled:!demo&&app.isPackaged,click:menuClick(loginToggle)},
    {label:'系统完成通知',type:'checkbox',checked:prefs.notify,enabled:!demo,click:()=>{prefs.notify=!prefs.notify;save();}},
    {type:'separator'},
    {label:'刷新额度与任务',click:()=>command('refresh')},
    {label:'清除完成 / 错误提醒',click:()=>command('clear-ready')},
    {label:'重新连接数据桥',enabled:!demo,click:menuClick(restartBridge)},
    {label:'选择 Codex 应用…',enabled:!demo,click:menuClick(()=>choose('app'))},
    {label:'选择 Codex CLI…',enabled:!demo,click:menuClick(()=>choose('cli'))},
    {label:'打开本地配置目录',enabled:!demo,click:menuClick(async()=>{const error=await shell.openPath(dataRoot);if(error)throw new Error(error);})},
    {type:'separator'},
    {label:'关闭桌宠',click:()=>app.quit()},
  ];
  const menu=Menu.buildFromTemplate(template); tray?.setContextMenu(menu);
  Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'燕小北',submenu:template}]));
  return menu;
}
function command(value) {
  if(demo) { if(value==='clear-ready') {state.pet={...state.pet,petState:'idle',label:'空闲中',counts:{total:0,running:0,active:0,waiting:0,ready:0,failed:0},tasks:[]};broadcast();}return; }
  bridge?.postMessage(value);
}
function receive(payload) {
  if(!payload||typeof payload!=='object')return;
  if(payload.type==='pet-state') {
    const previous=new Map((state.pet?.tasks||[]).map(task=>[task.id,task.state]));
    const completed=(payload.tasks||[]).find(task=>task.state==='ready'&&previous.get(task.id)&&previous.get(task.id)!=='ready');
    state.pet=payload;
    if(state.error?.scope==='activity') state.error=null;
    if(completed) {
      notice('已完成 · '+completed.title);
      if(prefs.notify&&Notification.isSupported())new Notification({title:'燕小北 · 任务完成',body:String(completed.title).slice(0,100),silent:true}).show();
    }
  } else if(payload.type==='snapshot') {state.quota=payload;if(state.error?.scope==='quota')state.error=null;}
  else if(payload.type==='error') state.error={scope:payload.scope,message:String(payload.message).slice(0,240)};
  broadcast();
}
function startBridge() {
  const env={...process.env,YANXIAOBEI_DATA_DIR:dataRoot};
  for(const [setting,key] of [['codexExecutable','CODEX_EXE'],['codexApp','CODEX_APP_PATH'],['codexHome','CODEX_HOME'],['logRoot','CODEX_LOG_DIR']]) if(prefs[setting])env[key]=prefs[setting];
  env.PATH=[path.join(os.homedir(),'.local','bin'),'/opt/homebrew/bin','/usr/local/bin',env.PATH||'/usr/bin:/bin'].join(path.delimiter);
  const runtime=app.isPackaged?path.join(process.resourcesPath,'runtime'):path.join(root,'runtime');
  const child=utilityProcess.fork(path.join(runtime,'quota-bridge.js'),[],{env,cwd:runtime,stdio:'ignore',serviceName:'燕小北数据桥'});
  bridge=child; state.error=null;state.pet=null;
  child.on('message',payload=>{if(bridge===child)receive(payload);});
  child.on('exit',()=>{if(bridge===child){bridge=null;state.error={scope:'bridge',message:'数据桥已退出，请从菜单重新连接'};broadcast();}});
}
async function stopBridge() {
  const child=bridge;bridge=null;if(!child)return;
  await new Promise(resolve=>{const timer=setTimeout(()=>{child.kill();resolve();},1800); child.once('exit',()=>{clearTimeout(timer);resolve();});try{child.postMessage('shutdown');}catch{clearTimeout(timer);resolve();}});
}
async function restartBridge() {await stopBridge();if(!quitting)startBridge();}
async function checkCodex() {
  if(demo||!prefs.followCodex||watching)return;
  watching=true;
  try {
    const target=codexApp();
    const listing=await execute('/bin/ps',['-axo','comm=']);
    const running=!!target&&listing.split('\n').some(line=>line.trim().startsWith(target+'/Contents/MacOS/'));
    if(running!==codexWasRunning) { if(running)win.showInactive();else win.hide();codexWasRunning=running; }
  } catch {notice('无法检查 Codex 运行状态；菜单栏仍可找回桌宠');}finally{watching=false;}
}
function demoState() {
  const name=process.argv.find(a=>a.startsWith('--demo-state='))?.split('=')[1]||'running';
  const names={running:['思考中','active'],waiting:['需要确认','waiting'],failed:['任务出错','failed'],review:['任务完成','ready'],idle:['空闲中',null]};
  const [label,taskState]=names[name]||names.running;
  const tasks=taskState?[{id:'00000000-0000-4000-8000-000000000001',title:'检查桌宠状态与界面',state:taskState,label,updatedAt:Date.now()/1000}]:[];
  state.pet={petState:names[name]?name:'running',label,fetchedAt:Date.now()/1000,tasks,counts:{total:tasks.length,running:taskState==='active'?1:0,waiting:taskState==='waiting'?1:0,ready:taskState==='ready'?1:0,failed:taskState==='failed'?1:0}};
  state.quota={fetchedAt:Date.now()/1000,planType:'示例',primary:{usedPercent:23,resetsAt:Date.now()/1000+15000},secondary:{usedPercent:50,resetsAt:Date.now()/1000+530000},resetCredits:{availableCount:2}};
  broadcast();
}
function installIPC() {
  ipcMain.handle('pet:get',event=>{trusted(event);return packet();});
  ipcMain.handle('pet:task',async(event,id)=>{trusted(event);try{await openTask(id);return {ok:true};}catch(error){notice(error.message);return {ok:false};}});
  ipcMain.handle('pet:action',async(event,name)=>{
    trusted(event);
    try {
      if(name==='menu') rebuildMenus().popup({window:win});
      else if(name==='open') await openCodex();
      else if(name==='toggle-quota'){prefs.quotaVisible=!prefs.quotaVisible;layout();}
      else if(name==='toggle-tasks'){prefs.tasksVisible=!prefs.tasksVisible;layout();}
      else if(name==='refresh'||name==='clear-ready')command(name);
      else if(name==='quit')app.quit();
      else throw new Error('Unsupported action');
      return {ok:true};
    }catch(error){notice(error.message);return {ok:false};}
  });
  ipcMain.on('pet:drag',(event,phase)=>{
    trusted(event);
    if(phase==='start')drag={point:screen.getCursorScreenPoint(),bounds:win.getBounds(),last:screen.getCursorScreenPoint()};
    else if(phase==='move'&&drag){const p=screen.getCursorScreenPoint(),area=screen.getDisplayNearestPoint(p).workArea;
      win.setBounds(clampBounds({...drag.bounds,x:drag.bounds.x+p.x-drag.point.x,y:drag.bounds.y+p.y-drag.point.y},area),false);
      win.webContents.send('pet:state',{...packet(),dragState:dragState(p.x-drag.last.x,p.y-drag.last.y)});drag.last=p;
    } else if(phase==='end'){drag=null;savePosition();broadcast();}
  });
}
async function smokeTest() {
  clearInterval(demoTimer);
  await new Promise(resolve=>setTimeout(resolve,900));
  const report=await win.webContents.executeJavaScript(`(async()=>{
    const title=document.querySelector('#state-label').textContent;
    const img=document.querySelector('#sprite');
    if(!img.complete||img.naturalWidth!==192)throw new Error('Sprite failed to load');
    await window.pet.action('toggle-tasks');
    await new Promise(r=>setTimeout(r,150));
    if(document.querySelectorAll('.task').length!==1)throw new Error('Task tray failed');
    const denied=await window.pet.openTask('bad;open');if(denied.ok)throw new Error('Invalid task ID accepted');
    return {title,rows:document.querySelectorAll('.task').length,spriteWidth:img.naturalWidth,isolated:typeof require==='undefined'};
  })()`);
  if(!report.isolated)throw new Error('Renderer Node integration enabled');
  const original=state.pet;
  report.states=[];
  for(const [name,label] of [['failed','任务出错'],['waiting','需要确认'],['review','任务完成'],['idle','空闲中'],['running','思考中']]) {
    state.pet={...original,petState:name,label,fetchedAt:Date.now()/1000};broadcast();
    await new Promise(resolve=>setTimeout(resolve,80));
    const rendered=await win.webContents.executeJavaScript(`({label:document.querySelector('#caption').textContent,src:document.querySelector('#sprite').src})`);
    if(rendered.label!==label||!rendered.src.includes('/'+name+'/'))throw new Error('State rendering failed: '+name);
    report.states.push(name);
  }
  state.pet={...original,fetchedAt:Date.now()/1000-20};broadcast();
  await new Promise(resolve=>setTimeout(resolve,80));
  report.offline=await win.webContents.executeJavaScript(`document.querySelector('#caption').textContent==='状态离线'&&document.querySelector('#running').textContent==='--'`);
  if(!report.offline)throw new Error('Stale thinking survived');
  state.pet={...original,fetchedAt:Date.now()/1000};broadcast();
  report.layouts=[];
  for(const [q,t] of [[true,false],[false,true],[false,false],[true,true]]){
    prefs.quotaVisible=q;prefs.tasksVisible=t;layout();
    await new Promise(resolve=>setTimeout(resolve,80));
    const fit=await win.webContents.executeJavaScript(`['quota','tasks','pet-body'].filter(id=>!document.getElementById(id).hidden&&document.getElementById(id).getClientRects().length).every(id=>{const b=document.getElementById(id).getBoundingClientRect();return b.bottom<=innerHeight&&b.right<=innerWidth;})`);
    if(!fit)throw new Error('Panel clipping: '+q+','+t);report.layouts.push([q,t]);
  }
  toast=null;broadcast();
  await new Promise(resolve=>setTimeout(resolve,100));
  const shot=await win.webContents.capturePage();
  fs.writeFileSync(path.join(dataRoot,'macos-ui-preview.png'),shot.toPNG());
  fs.writeFileSync(path.join(dataRoot,'smoke-result.json'),JSON.stringify(report,null,2));
  console.log('Electron smoke PASS: '+JSON.stringify(report));
  app.quit();
}
if(!app.requestSingleInstanceLock()){app.quit();}
else {
  app.on('second-instance',()=>{win?.show();win?.focus();});
  app.whenReady().then(async()=>{
    if(process.platform!=='darwin'&&!demo) {dialog.showErrorBox('macOS 版本','Windows 请使用 windows-companion；开发预览可使用 --demo。');app.quit();return;}
    fs.mkdirSync(dataRoot,{recursive:true});
    try{prefs=preferences(JSON.parse(fs.readFileSync(settingsFile,'utf8')));}catch{}
    if(demo)prefs=preferences();
    protocol.handle('pet',request=>{
      const url=new URL(request.url);if(url.host!=='app')return new Response('Not found',{status:404});
      const relative=decodeURIComponent(url.pathname).replace(/^\/+/,''),mapped=relative.startsWith('assets/')?relative:'ui/'+(relative||'index.html');
      const file=path.resolve(root,mapped);const allowed=[path.join(root,'assets')+path.sep,path.join(root,'ui')+path.sep];
      if(!allowed.some(prefix=>file.startsWith(prefix)))return new Response('Forbidden',{status:403});
      try {const mime={'.html':'text/html','.css':'text/css','.js':'text/javascript','.json':'application/json','.png':'image/png'}[path.extname(file)];
        if(!mime)return new Response('Not found',{status:404});return new Response(fs.readFileSync(file),{headers:{'content-type':mime+'; charset=utf-8'}});
      }catch{return new Response('Not found',{status:404});}
    });
    win=new BrowserWindow({...boundsFor(sizeFor(prefs)),show:false,frame:false,transparent:true,hasShadow:false,resizable:false,
      skipTaskbar:true,alwaysOnTop:true,title:'BJUT 燕小北 · macOS',webPreferences:{preload:path.join(root,'preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false,webSecurity:true,backgroundThrottling:false}});
    win.setAlwaysOnTop(true,'floating');win.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});
    win.webContents.setWindowOpenHandler(()=>({action:'deny'}));
    win.webContents.on('will-navigate',event=>event.preventDefault());
    win.webContents.session.setPermissionRequestHandler((_wc,_permission,callback)=>callback(false));
    win.webContents.session.setPermissionCheckHandler(()=>false);
    const icon=nativeImage.createFromPath(path.join(root,'assets','frames','idle','00.png')).resize({width:18,height:20});
    tray=new Tray(icon);rebuildMenus();tray.on('click',()=>{win.show();layout();});
    app.dock?.hide();installIPC();
    screen.on('display-metrics-changed',()=>layout());screen.on('display-removed',()=>layout());
    await win.loadURL(entry);
    if(!smoke)win.showInactive();
    if(demo){demoState();demoTimer=setInterval(demoState,4000);}else startBridge();
    heartbeat=setInterval(broadcast,1000);watcher=setInterval(checkCodex,2000);checkCodex();
    if(smoke) await smokeTest();
  }).catch(error=>{console.error(error);if(smoke)app.exit(1);else {dialog.showErrorBox('燕小北启动失败',error.message);app.quit();}});
  app.on('activate',()=>win?.show());
  app.on('window-all-closed',()=>app.quit());
  app.on('before-quit',event=>{
    if(quitting)return;
    quitting=true;event.preventDefault();clearInterval(heartbeat);clearInterval(watcher);clearInterval(demoTimer);
    try{savePosition();}catch{}
    stopBridge().finally(()=>app.quit());
  });
}
