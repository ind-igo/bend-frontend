import { afterAll, beforeAll, expect, test } from 'bun:test';
import { linkSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { check, array, bend, encode } from 'bend-frontend';

const root = path.resolve(import.meta.dir, '..');
const temp = mkdtempSync(path.join(tmpdir(), 'bend-frontend-'));
let program;
beforeAll(async () => { program = await check(path.join(root, 'tests/fixtures/program.bend')); }, 30_000);
afterAll(() => rmSync(temp, { recursive: true, force: true }));

function nodes(value) {
  if (value === null || typeof value !== 'object') return [];
  return [value, ...Object.values(value).flatMap(nodes)];
}

function definition(name) {
  const def = array(program.declarations).find(d => d.header.name === name);
  if (def?.$ !== 'Definition') throw new Error(`Missing definition: ${name}`);
  return def;
}

function source(name, body) {
  const file = path.join(temp, name);
  writeFileSync(file, body);
  return file;
}

function cli(...args) {
  // Each process compiles the Bend frontend before it checks the input.
  return Bun.spawnSync([process.execPath, 'host/run.js', 'src/cli.bend', ...args], { cwd: root, timeout: 60_000 });
}

test('the shared Bend core retains full-language constructs as serializable data', () => {
  expect(program.format).toBe('bend-frontend.core');
  expect(program.version).toBe(2);
  const tree = array(program.declarations).find(d => d.header.name === 'Tree');
  expect(tree?.$).toBe('Algebraic');
  expect(array(tree.constructors).map(c => c.name)).toEqual(['Leaf', 'Branch']);
  expect(nodes(array(tree.constructors)[1].typ).some(n => n.$ === 'TADT' && n.name === 'Tree')).toBe(true);

  expect(nodes(definition('sum').checked).some(n => n.$ === 'TLet' && array(n.bindings).length === 2)).toBe(true);
  expect(nodes(definition('adder').checked).filter(n => n.$ === 'TLam')).toHaveLength(2);
  expect(definition('identity').header.typ).toMatchObject({ $: 'TAll', quantity: { $: 'Erased' } });
  expect(definition('square').header.typ).toMatchObject({ $: 'TAll', quantity: { $: 'Reusable' } });
  expect(definition('twice').template_parameters).toBe(1);
  expect(array(array(program.templates).find(t => t.name === 'twice').instances).length).toBeGreaterThan(0);
  expect(nodes(definition('array_value').checked).some(n => n.$ === 'TRef' && n.name === 'Array.set')).toBe(true);

  const annotations = nodes(definition('identity').checked).filter(n => n.$ === 'TAnn');
  expect(annotations.some(n => nodes(n.typ).some(t => t.$ === 'TAll' && t.level.value === 1
    && t.domain.$ === 'TVar' && t.domain.level.value === 0))).toBe(true);
  let count = 0;
  const json = JSON.stringify(program, (key, value) => {
    if (typeof value === 'function' || key === 's') throw new Error('Leaked upstream object');
    count++;
    return value;
  });
  expect(count).toBeGreaterThan(100);
  expect(JSON.parse(json)).toEqual(program);
});

test('checks proofs and libraries without a main, and isolates check calls', async () => {
  const proof = await check(path.join(root, 'tests/fixtures/PROOF.bend'));
  const answer = array(proof.declarations).find(d => d.header.name.endsWith('LAWS.answer'));
  expect(answer?.$).toBe('Definition');
  expect(answer.header.typ.$).toBe('TEql');
  expect(nodes(answer.checked).some(n => n.$ === 'TRfl')).toBe(true);
  const file = source('library.bend', 'type Token is Data:\n  Token{}\ndef token() -> Token:\n  Token{}\n');
  const library = await check(file);
  expect(array(library.declarations).map(d => d.header.name)).toEqual(['Token', 'token']);
  expect(array(library.declarations).some(d => d.header.name === 'main')).toBe(false);
  expect(array(program.declarations).some(d => d.header.name === 'Token')).toBe(false);
  library.commit = 'consumer mutation';
  expect((await check(file)).commit).toBe(program.commit);
}, 30_000);

test('rejects incomplete proofs, false equations, affine duplication, and nontermination', async () => {
  for (const [name, body, error] of [
    ['hole', 'def hole() -> U32:\n  ?TODO\n', /Incomplete program/],
    ['open', 'law claim:\n  U32\n', /Incomplete program/],
    ['false', 'def falsehood() -> {1 == 2 : U32}:\n  {==}\n', /expected|observed/],
    ['duplicate', 'def duplicate(x: U32) -> U32:\n  (x + x : U32)\n', /consumed more than once/],
    ['loop', 'def loop(n: Nat) -> Nat:\n  loop(n)\n', /descent|smaller|recursive|decreasing/],
  ]) {
    await expect(check(source(`${name}.bend`, `import Base\n${body}`))).rejects.toThrow(error);
  }
  source('LAWS.bend', 'type Claim is Data:\n  Claim{}\n');
  await expect(check(source('PROOF.bend', 'type Unrelated is Data:\n  Unrelated{}\n')))
    .rejects.toThrow('must import the adjacent LAWS.bend');
}, 30_000);

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
  const declarations = array(result.declarations);
  expect(declarations.find(d => d.header.name === 'diverge')).toMatchObject({ unsafe: true });
  const declaration = declarations.find(d => d.header.name === 'effect');
  expect(array(declaration.foreign)).toEqual([effect]);
  expect(declaration.source).toEqual({ $: 'None' });
  expect(declaration.checked).toEqual({ $: 'None' });
  expect(array(result.inputs)).toContain(effect);
  rmSync(effect);
  expect(cli('export', file, '-o', path.join(temp, 'effects.json')).exitCode).toBe(0);
}, 90_000);

test('the Bend CLI checks/exports, exits, and protects input files', () => {
  const file = source('cli.bend', 'type Token is Data:\n  Token{}\n');
  const output = path.join(temp, 'core.json');
  const exported = cli('export', file, '-o', output);
  expect(exported.exitCode).toBe(0);
  expect(array(JSON.parse(readFileSync(output, 'utf8')).declarations)[0].header.name).toBe('Token');
  expect(cli('check', file).exitCode).toBe(0);
  expect(cli('emit', file).exitCode).not.toBe(0);
  expect(cli('--help').exitCode).toBe(0);
  expect(cli('export', file, '--wrong', output).exitCode).not.toBe(0);
  const original = readFileSync(file, 'utf8');
  const alias = path.join(temp, 'input-alias');
  linkSync(file, alias);
  for (const destination of [file, alias]) {
    const overwrite = cli('export', file, '-o', destination);
    expect(overwrite.exitCode).not.toBe(0);
    expect(overwrite.stderr.toString() + overwrite.stdout.toString()).toContain('overwrite a program input');
  }
  expect(readFileSync(file, 'utf8')).toBe(original);
}, 180_000);

test('Bend decodes the host boundary and rejects malformed upstream data', async () => {
  const frontend = await bend(new URL('../src/frontend.bend', import.meta.url).href);
  const ref = { $: 'Ref', k: 'U32' };
  const qty = { $: 'Lone' };
  const raw = body => ({ repository: 'test', commit: 'test', entry: '/test.bend', inputs: [], order: ['f'],
    templates: {}, declarations: { f: { $: 'Def', n: 0, x: 0, T: ref, v: body, e: body } },
    holes: 0, open: 0, paired_laws_missing: false });
  const finish = value => frontend.finish({ $: 'Done', value: encode(value) });
  const decode = body => finish(raw(body));
  const body = result => array(result.value.declarations)[0].checked.value;

  const sub = decode({ $: 'Sub', i: -1, v: ref, f: ref });
  expect(body(sub)).toMatchObject({ $: 'TSub', level: { $: 'Placeholder' }, value: { $: 'Inl' } });
  expect(sub.value.nodes).toBe(7); // header type + three nodes in each source/checked body
  const pattern = decode({ $: 'Sub', i: 0,
    v: { $: 'PCtr', k: 'C', x: [{ $: 'PVar', k: 'x', i: 0, q: qty }] }, f: ref });
  expect(body(pattern).value).toMatchObject({ $: 'Inr', value: { $: 'PCtr' } });
  expect(pattern.value.nodes).toBe(5); // patterns are not term nodes

  const group = { $: 'Let', k: ['x'], i: [0], q: [qty], v: [ref], f: ref };
  expect(array(body(decode(group)).bindings)).toHaveLength(1);
  expect(decode({ ...group, q: [] })).toMatchObject({ $: 'Fail', error: 'Mismatched upstream let bindings' });
  expect(decode({ $: 'NewUpstreamTerm' })).toMatchObject({ $: 'Fail', error: 'Unknown upstream term: NewUpstreamTerm' });
  expect(decode({ $: 'Qua', q: { $: 'FutureQuantity' } }).$).toBe('Fail');
  expect(decode({ $: 'Var', k: 'x', i: -2 }).$).toBe('Fail');
  expect(decode({ $: 'Var', k: 'x', i: 2 ** 32 }).$).toBe('Fail');
  expect(body(decode({ $: 'Var', k: 'x', i: 0xffffffff })).level.value).toBe(0xffffffff);
  expect(decode({ $: 'Ref', k: 'x', b: 'true' }).$).toBe('Fail');
  expect(decode({ $: 'App', f: ref }).$).toBe('Fail');
  expect(finish({ ...raw(ref), holes: 1 })).toMatchObject({ $: 'Fail', error: 'Incomplete program: 1 proof holes and 0 open laws' });
  expect(finish({ ...raw(ref), paired_laws_missing: true }).$).toBe('Fail');
  expect(frontend.finish({ $: 'Done', value: { $: 'Decoded', value: { $: 'Unit' } } }).$).toBe('Fail');
  expect(() => encode({ closure() {} })).toThrow('Cannot transport upstream value: function');
});
