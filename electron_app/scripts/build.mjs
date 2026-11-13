import { mkdir } from 'node:fs/promises';
import { build } from 'esbuild';

await mkdir('dist', { recursive: true });

await build({
  entryPoints: ['src/renderer/app.mjs'],
  outfile: 'dist/renderer.bundle.js',
  bundle: true,
  platform: 'browser',
  format: 'iife',
  target: ['chrome120'],
  sourcemap: true,
  logLevel: 'info',
});

await build({
  entryPoints: ['preload.js'],
  outfile: 'dist/preload.bundle.js',
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: ['node20'],
  external: ['electron'],
  sourcemap: true,
  logLevel: 'info',
});

console.log('Built dist/renderer.bundle.js and dist/preload.bundle.js');
