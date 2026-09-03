'use strict';
const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('pet',Object.freeze({
  getState:()=>ipcRenderer.invoke('pet:get'),
  action:name=>ipcRenderer.invoke('pet:action',name),
  openTask:id=>ipcRenderer.invoke('pet:task',id),
  drag:phase=>ipcRenderer.send('pet:drag',phase),
  onState:callback=>{ const handler=(_event,state)=>callback(state); ipcRenderer.on('pet:state',handler); return ()=>ipcRenderer.removeListener('pet:state',handler); },
}));
