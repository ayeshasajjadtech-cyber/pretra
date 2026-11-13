'use strict';

// Breathe Garden main process.
//
// Security posture:
// - Renderer has no Node.js access, runs with context isolation + sandbox.
// - Only the local app page is loaded; navigation, popups, and webviews are blocked.
// - Camera permission is granted only to this window's local page, and only for video.
// - The API key lives in .env, is read in main, and is handed to the trusted local
//   renderer over IPC so the renderer-side SDK can configure itself. It is never
//   written into source, the bundle, or logs.

const path = require('node:path');
const fs = require('node:fs');
const { fileURLToPath } = require('node:url');
const { app, BrowserWindow, ipcMain, session } = require('electron');

try {
  require('dotenv').config({ path: path.join(__dirname, '.env'), quiet: true });
} catch (error) {
  console.warn('[breathe-garden] Could not load .env:', error.message || error);
}

const APP_NAME = 'Breathe Garden';
const APP_INDEX_PATH = path.resolve(path.join(__dirname, 'index.html'));
const CONFIG_CHANNEL = 'breathe-garden:get-config';
const SMOKE = process.env.BREATHE_GARDEN_SMOKE === '1';
const IS_DEV = !app.isPackaged;
const API_KEY = String(process.env.SMARTSPECTRA_API_KEY || '').trim();
const HAS_API_KEY = API_KEY.length > 0;

let mainWindow = null;
let sdkLoadError = null;
let sdkBinding = null;

app.setName(APP_NAME);

function isAppIndexUrl(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'file:') return false;
    return path.resolve(fileURLToPath(parsed)) === APP_INDEX_PATH;
  } catch {
    return false;
  }
}

function isTrustedLocalPage(webContents) {
  if (!webContents || webContents !== mainWindow?.webContents) return false;
  return isAppIndexUrl(webContents.getURL());
}

function configurePermissions() {
  const defaultSession = session.defaultSession;

  defaultSession.setPermissionRequestHandler((webContents, permission, callback, details) => {
    if (permission !== 'media' || !isTrustedLocalPage(webContents)) {
      callback(false);
      return;
    }

    const mediaTypes = Array.isArray(details?.mediaTypes) ? details.mediaTypes : [];
    callback(!mediaTypes.includes('audio'));
  });

  defaultSession.setPermissionCheckHandler((webContents, permission, requestingOrigin, details) => {
    if (permission !== 'media' || !isTrustedLocalPage(webContents)) return false;
    const mediaTypes = Array.isArray(details?.mediaTypes) ? details.mediaTypes : [];
    return !mediaTypes.includes('audio');
  });
}

function bindSdk(window) {
  try {
    const { bindSmartSpectraIpc } = require('@smartspectra/node-sdk/main');
    sdkBinding = bindSmartSpectraIpc(window, {
      logger(level, message) {
        const line = `[smartspectra/main] ${message}`;
        if (level === 'error') console.error(line);
        else if (level === 'warn') console.warn(line);
        else console.log(line);
      },
    });
    sdkLoadError = null;
  } catch (error) {
    sdkLoadError = error?.message || String(error);
    console.error('[breathe-garden] SmartSpectra SDK failed to load:', sdkLoadError);
  }
}

function registerIpc() {
  ipcMain.handle(CONFIG_CHANNEL, (event) => {
    if (event.sender !== mainWindow?.webContents) {
      throw new Error('Config request came from an unexpected renderer');
    }

    return {
      apiKey: API_KEY,
      appVersion: app.getVersion(),
      hasApiKey: HAS_API_KEY,
      isDev: IS_DEV,
      platform: process.platform,
      sdkLoadError,
      smoke: SMOKE,
    };
  });
}

function hardenWindow(window) {
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

  window.webContents.on('will-attach-webview', (event) => {
    event.preventDefault();
  });

  window.webContents.on('will-navigate', (event, url) => {
    if (!isAppIndexUrl(url)) event.preventDefault();
  });

  window.webContents.on('render-process-gone', (_event, details) => {
    console.error('[breathe-garden] Renderer process ended:', details.reason);
  });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForDevHelper(window, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (window.isDestroyed()) return false;
    const ready = await window.webContents.executeJavaScript(
      'Boolean(window.__breatheGardenDev)',
      true,
    );
    if (ready) return true;
    await delay(250);
  }
  return false;
}

async function runSmokeCheck(window) {
  const outDir = process.env.BREATHE_GARDEN_SMOKE_OUT
    ? path.dirname(path.resolve(process.env.BREATHE_GARDEN_SMOKE_OUT))
    : path.join(__dirname, 'docs', 'screenshots');
  const screenshotPath = process.env.BREATHE_GARDEN_SMOKE_OUT
    ? path.resolve(process.env.BREATHE_GARDEN_SMOKE_OUT)
    : path.join(outDir, 'smoke.png');
  const resultPath = path.join(outDir, 'smoke-result.json');

  try {
    const helperReady = await waitForDevHelper(window);
    if (!helperReady) throw new Error('Renderer dev helpers did not initialize');

    const started = await window.webContents.executeJavaScript(
      'window.__breatheGardenDev.startSimulated()',
      true,
    );
    if (!started) throw new Error('Simulated session did not start');
    await delay(2500);

    const state = await window.webContents.executeJavaScript(
      'window.__breatheGardenDev.getState()',
      true,
    );

    await fs.promises.mkdir(outDir, { recursive: true });
    await fs.promises.writeFile(
      resultPath,
      JSON.stringify({ capturedAt: new Date().toISOString(), state }, null, 2),
    );

    const image = await window.webContents.capturePage();
    await fs.promises.writeFile(screenshotPath, image.toPNG());

    console.log(`[breathe-garden] Smoke screenshot: ${screenshotPath}`);
    console.log(`[breathe-garden] Smoke state: ${JSON.stringify(state)}`);
  } catch (error) {
    console.error('[breathe-garden] Smoke check failed:', error);
    process.exitCode = 1;
  } finally {
    app.quit();
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    show: !SMOKE,
    backgroundColor: '#07151b',
    title: APP_NAME,
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'dist', 'preload.bundle.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      spellcheck: false,
      devTools: IS_DEV,
      backgroundThrottling: false,
    },
  });

  mainWindow.setMenuBarVisibility(false);
  hardenWindow(mainWindow);
  bindSdk(mainWindow);

  mainWindow.webContents.once('did-finish-load', () => {
    if (SMOKE) runSmokeCheck(mainWindow);
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    sdkBinding = null;
  });

  const query = SMOKE ? '?simulate=1' : '';
  mainWindow.loadFile(path.join(__dirname, 'index.html'), { search: query }).catch((error) => {
    console.error('[breathe-garden] Failed to load app shell:', error);
  });
}

app.whenReady().then(() => {
  if (process.platform === 'win32') {
    app.setAppUserModelId('com.breathegarden.app');
  }

  configurePermissions();
  registerIpc();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
}).catch((error) => {
  console.error('[breathe-garden] Failed to start:', error);
  app.quit();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send?.('breathe-garden:app-quitting');
  }
});
