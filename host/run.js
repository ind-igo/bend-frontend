#!/usr/bin/env bun
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { compiled } from './adapter.js';

const [entry, ...args] = process.argv.slice(2);
if (!entry) throw new Error('Usage: bun host/run.js <entry.bend> [arguments...]');
let program;
try {
  program = await compiled(entry, false);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
const child = Bun.spawnSync([process.execPath, program, '--', ...args], {
  env: { ...process.env, BEND_ENTRY: realpathSync(entry),
    BEND_FRONTEND_HOST: fileURLToPath(new URL('./adapter.js', import.meta.url)) },
  stdin: 'inherit', stdout: 'inherit', stderr: 'inherit',
});
if (child.error) throw child.error;
process.exit(child.exitCode ?? 1);
