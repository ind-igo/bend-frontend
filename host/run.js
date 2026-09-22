#!/usr/bin/env bun
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { checkUpstream } from './adapter.js';

checkUpstream();
const file = relative => fileURLToPath(new URL(relative, import.meta.url));
const [entry, ...args] = process.argv.slice(2);
if (!entry) throw new Error('Usage: bun host/run.js <entry.bend> [arguments...]');
const child = Bun.spawnSync([process.execPath, file('../vendor/bend/bend2/main.ts'),
  path.resolve(entry), '--', ...args], {
  env: { ...process.env, BEND_FRONTEND_HOST: file('./adapter.js') },
  stdin: 'inherit', stdout: 'inherit', stderr: 'inherit',
});
if (child.error) throw child.error;
process.exit(child.exitCode ?? 1);
