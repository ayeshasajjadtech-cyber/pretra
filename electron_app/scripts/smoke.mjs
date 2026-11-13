import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const electron = require('electron');
const root = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const output = path.join(root, 'docs', 'screenshots', 'smoke.png');

const child = spawn(electron, ['.'], {
  cwd: root,
  env: {
    ...process.env,
    BREATHE_GARDEN_SMOKE: '1',
    BREATHE_GARDEN_SMOKE_OUT: output,
  },
  stdio: 'inherit',
  windowsHide: true,
});

const timeout = setTimeout(() => {
  console.error('[smoke] Timed out after 45 seconds');
  child.kill();
  process.exitCode = 1;
}, 45000);

child.on('error', (error) => {
  clearTimeout(timeout);
  console.error('[smoke] Failed to launch Electron:', error);
  process.exitCode = 1;
});

child.on('exit', (code, signal) => {
  clearTimeout(timeout);
  if (signal) {
    console.error(`[smoke] Electron exited with signal ${signal}`);
    process.exitCode = 1;
    return;
  }
  process.exitCode = code ?? 1;
});
