'use strict';

// Loads the SmartSpectra preload bridge first, then exposes only the small
// config surface Breathe Garden needs. The API key is read from .env in the
// main process and passed to this local, bundled page over context-isolated
// IPC. It is never written into the renderer bundle or committed to git.
require('@smartspectra/node-sdk/preload');

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('breatheGarden', {
  getConfig: () => ipcRenderer.invoke('breathe-garden:get-config'),
});
