const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('crossover', {
  init: () => ipcRenderer.invoke('init'),
  setLayout: (list) => ipcRenderer.send('layout', list),
  setVisible: (visible) => ipcRenderer.send('visible', visible),
  action: (id, action) => ipcRenderer.send('action', id, action),
  onState: (callback) => ipcRenderer.on('state', (_event, id, state) => callback(id, state)),
  onFullScreen: (callback) => ipcRenderer.on('fullscreen', (_event, id) => callback(id)),
});
