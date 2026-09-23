import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, realpathSync, renameSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as Bend from '../vendor/bend/bend2/bend.ts';
import * as Comp from '../vendor/bend/bend2/comp.ts';
import upstream from '../upstream.json';

const upstreamDirectory = fileURLToPath(new URL('../vendor/bend', import.meta.url));
const cacheDirectory = fileURLToPath(new URL('../build/cache', import.meta.url));

export function checkUpstream() {
  const git = (...args) => execFileSync('git', ['-C', upstreamDirectory, ...args], { encoding: 'utf8' }).trim();
  if (git('rev-parse', 'HEAD') !== upstream.commit || git('status', '--porcelain', '--untracked-files=no')) {
    throw new Error('vendor/bend must be unchanged at the commit in upstream.json; run git submodule update --init');
  }
}

export function array(values) {
  const result = [];
  for (; values.$ === 'Con'; values = values.tail) result.push(values.head);
  if (values.$ !== 'Nil') throw new Error('Invalid Bend list');
  return result;
}

// One generic data transport, independent of both upstream and Core constructors.
export function encode(value) {
  if (value == null) return { $: 'Null' };
  if (typeof value === 'boolean') return { $: 'Boolean', value };
  if (typeof value === 'string') return { $: 'Text', value };
  if (typeof value === 'number' && Number.isFinite(value)) return { $: 'Number', decimal: String(value) };
  if (Array.isArray(value)) {
    let items = { $: 'End' };
    for (let i = value.length - 1; i >= 0; i--) items = { $: 'Item', value: encode(value[i]), rest: items };
    return { $: 'Array', items };
  }
  if (typeof value === 'object' && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null)) {
    let fields = { $: 'End' };
    const entries = Object.entries(value);
    for (let i = entries.length - 1; i >= 0; i--) {
      const [name, child] = entries[i];
      if (child !== undefined) fields = { $: 'Field', name, value: encode(child), rest: fields };
    }
    return { $: 'Object', fields };
  }
  throw new Error(`Cannot transport upstream value: ${typeof value}`);
}

// Checked terms are first-order except Var.v refinement memos. Reify those at
// their lexical depth; do not re-lower checked terms (that would erase memos).
function reify(value, depth = 0) {
  if (Array.isArray(value)) return value.map(child => reify(child, depth));
  if (value === null || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).filter(([key]) => key !== 's').map(([key, child]) => {
    if (value.$ === 'Var' && key === 'v' && child != null) child = Bend.term_lower(child, depth);
    return [key, reify(child, depth + binders(value, key))];
  }));
}

// All.B and Lam.f are under one new binder; Let.f is under the whole group.
function binders(term, key) {
  if ((term.$ === 'All' && key === 'B') || (term.$ === 'Lam' && key === 'f')) return 1;
  return term.$ === 'Let' && key === 'f' ? term.k.length : 0;
}

const diagnostic = error => error?.$ === 'Err' ? Bend.err_show(error) : error instanceof Error ? error.message : String(error);

const lowered = def => reify(def.$ === 'ADT'
  ? { ...def, T: Bend.term_lower(def.T), c: def.c.map(c => ({ ...c, T: Bend.term_lower(c.T) })) }
  : { ...def, T: Bend.term_lower(def.T), v: def.v == null ? null : Bend.term_lower(def.v),
    i: def.i?.map(f => path.resolve(f)) });

// Base is most of every book and most of it is unused. Export the non-Base
// declarations and the declarations they reach through names in their terms.
function reachable(book) {
  const owner = Object.create(null), template = Object.create(null), done = new Map();
  for (const [name, def] of Object.entries(book.tlds)) if (def.$ === 'ADT') for (const c of def.c) owner[c.k] = name;
  for (const [name, instances] of Object.entries(book.tmps)) for (const k of Object.values(instances)) template[k] = name;
  const pending = Object.keys(book.tlds).filter(name => !book.tlds[name].b);
  const visit = value => {
    if (value === null || typeof value !== 'object') return;
    if (['Ref', 'ADT', 'Ctr', 'Mat'].includes(value.$)) pending.push(value.k, owner[value.k]);
    for (const child of Object.values(value)) visit(child);
  };
  while (pending.length) {
    const name = pending.pop();
    if (!(name in book.tlds) || done.has(name)) continue;
    done.set(name, lowered(book.tlds[name]));
    visit(done.get(name));
    pending.push(template[name]);
  }
  return new Map(Object.keys(book.tlds).filter(name => done.has(name)).map(name => [name, done.get(name)]));
}

// The host supplies upstream data and filesystem observations. Bend owns all
// Core construction, metadata validation, node counting, and frontend policy.
export async function load(file) {
  try {
    checkUpstream();
    const entry = path.resolve(file), book = Bend.book_nil(), seen = new Map();
    await Bend.book_load(book, entry, '', seen);
    Bend.book_valid(book);
    const kept = reachable(book);
    const templates = Object.fromEntries(Object.entries(book.tmps).filter(([name]) => kept.has(name))
      .map(([name, instances]) => [name, Object.fromEntries(Object.entries(instances).filter(([, k]) => kept.has(k)))]));
    const foreign = Object.values(book.tlds).flatMap(d => d.i?.map(f => path.resolve(f)) ?? []);
    const laws = path.join(path.dirname(entry), 'LAWS.bend');
    return { $: 'Done', value: encode({ ...upstream, entry: realpathSync(entry),
      inputs: [...new Set([...seen.keys(), ...foreign])], order: book.order.filter(name => kept.has(name)), templates,
      declarations: Object.fromEntries(kept), holes: book.hols, open: book.open,
      paired_laws_missing: path.basename(entry) === 'PROOF.bend' && existsSync(laws) && !seen.has(realpathSync(laws)),
    }) };
  } catch (error) {
    return { $: 'Fail', error: diagnostic(error) };
  }
}

const sha = file => createHash('sha256').update(readFileSync(file)).digest('hex');

function atomic(file, text) {
  writeFileSync(`${file}.${process.pid}.tmp`, text);
  renameSync(`${file}.${process.pid}.tmp`, file);
}

// The existing upstream JS compiler bootstraps our Bend tools; it is not a
// target backend offered by this frontend. Never load the user's program here.
// Checking and compiling a tool costs seconds and gigabytes, but the output
// only changes with the files upstream read, so keep it keyed by their hashes.
// A library exports its pure defs, as upstream's import plugin does; a program runs main.
export async function compiled(file, library) {
  checkUpstream();
  const entry = realpathSync(file);
  const out = path.join(cacheDirectory, createHash('sha256').update(`${library}:${entry}`).digest('hex').slice(0, 16));
  const target = out + (library ? '.mjs' : '.cjs');
  try {
    const { commit, inputs } = JSON.parse(readFileSync(`${out}.json`, 'utf8'));
    if (commit === upstream.commit && existsSync(target)
      && Object.entries(inputs).every(([input, hash]) => existsSync(input) && sha(input) === hash)) return target;
  } catch {}
  const book = Bend.book_nil(), seen = new Map();
  try {
    await Bend.book_load(book, entry, '', seen);
    Bend.book_valid(book);
    Comp.book_owned(book, Comp.SYNTH);
  } catch (error) {
    throw new Error(diagnostic(error));
  }
  if (book.hols + book.open) throw new Error(`${entry}: the code is incomplete, and not a valid proof yet`);
  const pure = [...new Set(book.order)].filter(name => {
    const def = book.tlds[name];
    return def.$ === 'Def' && def.v !== null && def.b !== true && def.x === 0 && def.i === undefined
      && Comp.io_base(book, def.T) === null;
  });
  const foreign = Object.values(book.tlds).flatMap(d => d.$ === 'Def' ? d.i ?? [] : []).map(f => path.resolve(f));
  mkdirSync(cacheDirectory, { recursive: true });
  atomic(target, library ? Comp.js_lib(book, pure, pure) : Comp.js_book(book));
  atomic(`${out}.json`, JSON.stringify({ commit: upstream.commit,
    inputs: Object.fromEntries([...seen.keys(), ...foreign].map(input => [input, sha(input)])) }));
  return target;
}

export async function bend(file) {
  return (await import(await compiled(file.startsWith('file:') ? fileURLToPath(file) : file, true))).default;
}

export async function check(file) {
  const frontend = await bend(new URL('../src/frontend.bend', import.meta.url).href);
  const result = frontend.finish(await load(file));
  if (result.$ === 'Fail') throw new Error(result.error);
  return result.value;
}

export function write(output, program) {
  try {
    const file = path.resolve(output);
    // statSync follows links, so the inode check also catches symlinks and hard links.
    // The path check protects declared foreign files that do not exist yet.
    const target = statSync(file, { throwIfNoEntry: false });
    if (array(program.inputs).some(input => {
      if (input === file) return true;
      const source = statSync(input, { throwIfNoEntry: false });
      return source && target && source.dev === target.dev && source.ino === target.ino;
    })) throw new Error('Output would overwrite a program input');
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(program, null, 2) + '\n');
    return { $: 'Done', value: { $: 'Unit' } };
  } catch (error) {
    return { $: 'Fail', error: diagnostic(error) };
  }
}

if (import.meta.main) {
  if (process.argv[2] !== '--load' || process.argv.length !== 4) throw new Error('Expected --load <source>');
  load(process.argv[3]).then(result => process.stdout.write(JSON.stringify(result)));
}
