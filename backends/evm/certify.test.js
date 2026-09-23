import { expect, test } from 'bun:test';
import { readFileSync, writeFileSync, mkdtempSync, rmSync, copyFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dir, '../..');
const bend = (...args) => Bun.spawnSync([process.execPath, ...args], { cwd: root, timeout: 120_000 });

test('the committed Counter certificate is current', () => {
  const generated = bend('host/run.js', 'backends/evm/certify.bend', 'backends/evm/counter/program.bend',
    'get', 'increment', 'set');
  expect(generated.exitCode).toBe(0);
  expect(generated.stdout.toString()).toBe(readFileSync(path.join(import.meta.dir, 'counter/CERT.bend'), 'utf8'));
}, 120_000);

test('a certificate for the wrong IR does not check', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'bend-evm-cert-'));
  try {
    mkdirSync(path.join(dir, 'counter'));
    for (const file of ['Evm.bend', 'ir.bend', 'counter/program.bend', 'counter/CERT.bend']) {
      copyFileSync(path.join(import.meta.dir, file), path.join(dir, file));
    }
    const cert = path.join(dir, 'counter/CERT.bend');
    const good = readFileSync(cert, 'utf8');
    for (const [from, to, law] of [
      ['IR.Lit{7n}', 'IR.Lit{8n}', 'set'],
      ['IR.SStore{IR.Lit{0n}, IR.Var{1n}}', 'IR.SStore{IR.Lit{0n}, IR.Var{0n}}', 'increment'],
      ['IR.Tail{IR.SLoad{IR.Lit{0n}}}', 'IR.Tail{IR.SLoad{IR.Lit{1n}}}', 'get'],
      // An unbound Var reads as 0, like the source's literal key, so only the scope check catches it.
      ['IR.Tail{IR.SLoad{IR.Lit{0n}}}', 'IR.Tail{IR.SLoad{IR.Var{5n}}}', 'get'],
    ]) {
      expect(good).toContain(from);
      writeFileSync(cert, good.replace(from, to));
      const checked = bend('vendor/bend/bend2/main.ts', cert, '--check-only');
      expect(checked.exitCode).not.toBe(0);
      expect(checked.stdout.toString() + checked.stderr.toString()).toContain(`Location: ${law}`);
    }
    // The copied Evm.bend and ir.bend could define different semantics.
    const copy = bend('host/run.js', 'backends/evm/certify.bend', path.join(dir, 'counter/program.bend'), 'get');
    expect(copy.exitCode).not.toBe(0);
    expect(copy.stderr.toString()).toContain("must import this backend's Evm.bend");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}, 120_000);
