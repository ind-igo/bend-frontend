import { expect, test } from 'bun:test';
import { check, bend } from 'bend-frontend';
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function emitYul(program, name) {
  const lowering = await bend(new URL('./lower.bend', import.meta.url).href);
  const result = lowering.compile(program, name);
  if (result.$ === 'Fail') throw new Error(result.error);
  return result.value;
}

test('emits checked U32 arithmetic, compiles Yul, and executes it on a local EVM', async () => {
  const program = await check(`${import.meta.dir}/PROOF.bend`);
  const creations = [];
  for (const name of ['program.calculate', 'program.scopes']) {
    const yul = await emitYul(program, name);
    const compiler = Bun.spawnSync(['solc', '--standard-json'], {
      stdin: Buffer.from(JSON.stringify({ language: 'Yul', sources: { 'example.yul': { content: yul } },
        settings: { evmVersion: 'shanghai', optimizer: { enabled: true },
          outputSelection: { '*': { '*': ['evm.bytecode.object'] } } } })),
    });
    expect(compiler.exitCode).toBe(0);
    const compiled = JSON.parse(compiler.stdout.toString());
    const errors = (compiled.errors ?? []).filter((e) => e.severity === 'error');
    expect(errors).toEqual([]);
    creations.push(`0x${compiled.contracts['example.yul'].BendDemo.evm.bytecode.object}`);
  }

  // A fresh local chain, zero accounts, no external RPC or signed transactions.
  const node = Bun.spawn(['anvil', '--host', '127.0.0.1', '--port', '0', '--accounts', '0', '--no-mining'], {
    stdout: 'pipe', stderr: 'pipe',
  });
  const deadline = setTimeout(() => node.kill(), 10_000);
  try {
    const reader = node.stdout.getReader();
    const decoder = new TextDecoder();
    let output = '', port;
    while (!port) {
      const chunk = await reader.read();
      if (chunk.done) throw new Error('Anvil stopped before starting its local RPC');
      output += decoder.decode(chunk.value);
      port = output.match(/Listening on 127\.0\.0\.1:(\d+)/)?.[1];
    }
    reader.releaseLock();
    const rpc = async (params) => {
      const response = await fetch(`http://127.0.0.1:${port}`, { method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params }),
        signal: AbortSignal.timeout(3000),
      });
      const payload = await response.json();
      if (payload.error || payload.result === undefined) throw new Error(payload.error?.message ?? 'Missing result');
      return payload.result;
    };
    // Execute the initializer, then execute its returned runtime via a state override.
    const runtime = await rpc([{ data: creations[0] }, 'latest']);
    const scopedRuntime = await rpc([{ data: creations[1] }, 'latest']);
    const address = '0x0000000000000000000000000000000000000123';
    const call = (data) => rpc([{ to: address, data }, 'latest', { [address]: { code: runtime } }]);
    const encode = (values) => '0x' + values.map(v => v.toString(16).padStart(64, '0')).join('');
    for (const values of [[6n, 7n, 0n], [0xffffffffn, 2n, 3n], [0xffffffffn, 0xffffffffn, 0xffffffffn],
      [0n, 0n, 0n], [12345n, 6789n, 42n]]) {
      const expected = (values[0] * values[1] + values[2]) & 0xffffffffn;
      expect(BigInt(await call(encode(values)))).toBe(expected);
      const scoped = (expected * ((values[1] * values[2] + values[0]) & 0xffffffffn)) & 0xffffffffn;
      expect(BigInt(await rpc([{ to: address, data: encode(values) }, 'latest',
        { [address]: { code: scopedRuntime } }]))).toBe(scoped);
    }
    await expect(call('0x')).rejects.toThrow(/revert/);
    await expect(call(encode([0x100000000n, 1n, 0n]))).rejects.toThrow(/revert/);
    const sender = '0x0000000000000000000000000000000000000456';
    await expect(rpc([{ from: sender, to: address, data: encode([1n, 1n, 0n]), value: '0x1' }, 'latest',
      { [address]: { code: runtime }, [sender]: { balance: '0x1' } }])).rejects.toThrow(/revert/);
    console.log('Yul → solc → local EVM: (6 * 7) + 0 = 42; U32 overflow and calldata checks passed.');
  } finally {
    clearTimeout(deadline);
    node.kill();
    await node.exited;
  }
}, 60_000);

test('rejects unsupported runtime constructs instead of guessing', async () => {
  const program = await check(`${import.meta.dir}/../../examples/program.bend`);
  await expect(emitYul(program, 'adder')).rejects.toThrow('U32 result');
  await expect(emitYul(program, 'identity')).rejects.toThrow('U32 arguments');
  await expect(emitYul(program, 'sum')).rejects.toThrow('U32 arguments');
  await expect(emitYul(program, 'twice')).rejects.toThrow('safe, concrete function');
});

test('the universal preservation proof rejects an incorrect lowering', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'bend-lowering-proof-'));
  try {
    await mkdir(join(dir, 'experiments/yul'), { recursive: true });
    await mkdir(join(dir, 'src'));
    await copyFile(`${import.meta.dir}/../../src/core.bend`, join(dir, 'src/core.bend'));
    await copyFile(`${import.meta.dir}/../u32.bend`, join(dir, 'experiments/u32.bend'));
    for (const name of ['lower.bend', 'LAWS.bend', 'PROOF.bend', 'program.bend']) {
      await copyFile(join(import.meta.dir, name), join(dir, 'experiments/yul', name));
    }
    const path = join(dir, 'experiments/yul/lower.bend');
    const source = await readFile(path, 'utf8');
    const wrong = source.replace('a b = lower(left) lower(right)\n      Mul32{a, b}',
      'a b = lower(left) lower(right)\n      Add32{a, b}');
    expect(wrong).not.toBe(source);
    await writeFile(path, wrong);
    await expect(check(join(dir, 'experiments/yul/PROOF.bend'))).rejects.toThrow('Location: LAWS.preserves');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
