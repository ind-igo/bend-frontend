import { checkUpstream, compiled } from '../host/adapter.js';

checkUpstream();
// Proofs must hold with no unsafe or foreign code, so they get upstream's verdict.
for (const file of ['src/PROOF.bend', 'tests/fixtures/PROOF.bend']) {
  const child = Bun.spawnSync([process.execPath, 'vendor/bend/bend2/main.ts', file, '--check-only'],
    { stdout: 'inherit', stderr: 'inherit' });
  if (child.error) throw child.error;
  if (child.exitCode !== 0) process.exit(child.exitCode ?? 1);
}
// The CLI does IO through foreign effects, which the verdict refuses; check it as a program.
try {
  await compiled('src/cli.bend', false);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
