import { checkUpstream } from '../host/adapter.js';

checkUpstream();
for (const file of ['src/PROOF.bend', 'src/cli.bend', 'tests/fixtures/PROOF.bend',
  'backends/yul/PROOF.bend', 'backends/yul/emit.bend',
  'backends/evm/counter/PROOF.bend', 'backends/evm/counter/CERT.bend', 'backends/evm/certify.bend']) {
  const child = Bun.spawnSync([process.execPath, 'vendor/bend/bend2/main.ts', file, '--check-only'],
    { stdout: 'inherit', stderr: 'inherit' });
  if (child.error) throw child.error;
  if (child.exitCode !== 0) process.exit(child.exitCode ?? 1);
}
