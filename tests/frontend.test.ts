import { afterAll, beforeAll, expect, test } from 'bun:test';
import { linkSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { check, type CheckedProgram, type CoreDeclaration } from 'bend-frontend';

const root = path.resolve(import.meta.dir, '..');
const temp = mkdtempSync(path.join(tmpdir(), 'bend-frontend-'));
let program: CheckedProgram;
beforeAll(async () => { program = await check(path.join(root, 'examples/program.bend')); });
afterAll(() => rmSync(temp, { recursive: true, force: true }));

function nodes(value: unknown): Record<string, unknown>[] {
  if (value === null || typeof value !== 'object') return [];
  return [value as Record<string, unknown>, ...Object.values(value).flatMap(nodes)];
}

function definition(name: string): Extract<CoreDeclaration, { kind: 'Def' }> {
  const def = program.declarations.find(d => d.name === name);
  if (def?.kind !== 'Def') throw new Error(`Missing definition: ${name}`);
  return def;
}

function source(name: string, body: string): string {
  const file = path.join(temp, name);
  writeFileSync(file, body);
  return file;
}

function cli(...args: string[]) {
  return Bun.spawnSync([process.execPath, 'src/cli.ts', ...args], { cwd: root, timeout: 15_000 });
}

test('the public output retains full-language constructs as plain serializable data', () => {
  expect(program.format).toBe('bend-frontend.core');
  expect(program.version).toBe(1);
  const tree = program.declarations.find(d => d.name === 'Tree');
  expect(tree?.kind).toBe('ADT');
  if (tree?.kind !== 'ADT') throw new Error('Missing Tree');
  expect(tree.constructors.map(c => c.name)).toEqual(['Leaf', 'Branch']);
  expect(nodes(tree.constructors[1]!.type).some(n => n.$ === 'ADT' && n.k === 'Tree')).toBe(true);

  expect(nodes(definition('sum').checkedBody).some(n => n.$ === 'Let' && (n.v as unknown[]).length === 2)).toBe(true);
  expect(nodes(definition('adder').checkedBody).filter(n => n.$ === 'Lam')).toHaveLength(2);
  expect(definition('identity').type).toMatchObject({ $: 'All', q: { $: 'None' } });
  expect(definition('square').type).toMatchObject({ $: 'All', q: { $: 'Many' } });
  expect(definition('twice').templateParameters).toBe(1);
  expect(Object.values(program.templates.twice!).length).toBeGreaterThan(0);
  expect(nodes(definition('array_value').checkedBody).some(n => n.$ === 'Ref' && n.k === 'Array.set')).toBe(true);

  // Reified dependent types must retain the outer A binder and inner x binder.
  const annotations = nodes(definition('identity').checkedBody).filter(n => n.$ === 'Ann');
  expect(annotations.some(n => nodes(n.T).some(t => t.$ === 'All' && t.i === 1
    && (t.A as Record<string, unknown>).$ === 'Var' && (t.A as Record<string, unknown>).i === 0))).toBe(true);

  let count = 0;
  const json = JSON.stringify(program, (key, value) => {
    if (typeof value === 'function' || key === 's') throw new Error('Leaked upstream object');
    count++;
    return value;
  });
  expect(count).toBeGreaterThan(100);
  expect(JSON.parse(json)).toEqual(program);
});

test('checks proofs and libraries without a main, and keeps check calls independent', async () => {
  const proof = await check(path.join(root, 'examples/PROOF.bend'));
  const answer = proof.declarations.find(d => d.name.endsWith('LAWS.answer'));
  expect(answer?.kind).toBe('Def');
  if (answer?.kind !== 'Def') throw new Error('Missing law');
  expect(answer.type.$).toBe('Eql');
  expect(nodes(answer.checkedBody).some(n => n.$ === 'Rfl')).toBe(true);
  const file = source('library.bend', 'type Token is Data:\n  Token{}\ndef token() -> Token:\n  Token{}\n');
  const library = await check(file);
  expect(library.declarations.map(d => d.name)).toEqual(['Token', 'token']);
  expect(library.declarations.some(d => d.name === 'main')).toBe(false);
  expect(program.declarations.some(d => d.name === 'Token')).toBe(false);
  library.upstream.commit = 'consumer mutation';
  expect((await check(file)).upstream.commit).toBe(program.upstream.commit);
});

test('rejects incomplete proofs, false equations, affine duplication, and nontermination', async () => {
  for (const [name, body, error] of [
    ['hole', 'def hole() -> U32:\n  ?TODO\n', /Incomplete program/],
    ['open', 'law claim:\n  U32\n', /Incomplete program/],
    ['false', 'def falsehood() -> {1 == 2 : U32}:\n  {==}\n', /expected|observed/],
    ['duplicate', 'def duplicate(x: U32) -> U32:\n  (x + x : U32)\n', /consumed more than once/],
    ['loop', 'def loop(n: Nat) -> Nat:\n  loop(n)\n', /descent|smaller|recursive|decreasing/],
  ] as const) {
    await expect(check(source(`${name}.bend`, `import Base\n${body}`))).rejects.toThrow(error);
  }
  source('LAWS.bend', 'type Claim is Data:\n  Claim{}\n');
  await expect(check(source('PROOF.bend', 'type Unrelated is Data:\n  Unrelated{}\n')))
    .rejects.toThrow('must import the adjacent LAWS.bend');
});

test('preserves unsafe and foreign declarations without executing effects', async () => {
  const effect = source('effect.js', 'throw new Error("must never execute");\n');
  const file = source('effects.bend', `import Base
@unsafe
def diverge() -> Empty:
  diverge()
def effect() -> IO(Unit):
  import "./effect.js"
`);
  const result = await check(file);
  expect(result.declarations.find(d => d.name === 'diverge')).toMatchObject({ unsafe: true });
  expect(result.declarations.find(d => d.name === 'effect')).toMatchObject({
    foreign: [effect], sourceBody: null, checkedBody: null,
  });
  expect(result.inputs).toContain(effect);
  // Foreign implementations are declarations, not frontend dependencies.
  rmSync(effect);
  expect(cli('export', file, '-o', path.join(temp, 'effects.json')).exitCode).toBe(0);
});

test('the CLI only checks/exports, exits, and protects source files', () => {
  const file = source('cli.bend', 'type Token is Data:\n  Token{}\n');
  const output = path.join(temp, 'core.json');
  const exported = cli('export', file, '-o', output);
  expect(exported.exitCode).toBe(0);
  expect(JSON.parse(readFileSync(output, 'utf8')).declarations[0].name).toBe('Token');
  expect(cli('check', file).exitCode).toBe(0);
  expect(cli('emit', file).exitCode).not.toBe(0);
  const original = readFileSync(file, 'utf8');
  const alias = path.join(temp, 'input-alias');
  linkSync(file, alias);
  for (const destination of [file, alias]) {
    const overwrite = cli('export', file, '-o', destination);
    expect(overwrite.exitCode).not.toBe(0);
    expect(overwrite.stderr.toString() + overwrite.stdout.toString()).toContain('overwrite a program input');
  }
  expect(readFileSync(file, 'utf8')).toBe(original);
});

test('the library module graph excludes the compiler, runtime, and CLI', async () => {
  const build = await Bun.build({ entrypoints: [path.join(root, 'src/frontend.ts')], target: 'bun', metafile: true });
  expect(build.success).toBe(true);
  const files = Object.keys(build.metafile!.inputs);
  expect(files.some(f => f.endsWith('bend2/bend.ts'))).toBe(true);
  expect(files.some(f => /(?:comp|main|cli)\.ts$|node_modules|\/effs\//.test(f))).toBe(false);
});
