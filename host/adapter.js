import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as Bend from '../vendor/bend/bend2/bend.ts';
import upstream from '../upstream.json';

const upstreamDirectory = fileURLToPath(new URL('../vendor/bend', import.meta.url));

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

// The host supplies upstream data and filesystem observations. Bend owns all
// Core construction, metadata validation, node counting, and frontend policy.
export async function load(file) {
  try {
    checkUpstream();
    const entry = path.resolve(file), book = Bend.book_nil(), seen = new Map();
    await Bend.book_load(book, entry, '', seen);
    Bend.book_valid(book);
    const declarations = Object.fromEntries(Object.entries(book.tlds).map(([name, def]) => [name,
      reify(def.$ === 'ADT'
        ? { ...def, T: Bend.term_lower(def.T), c: def.c.map(c => ({ ...c, T: Bend.term_lower(c.T) })) }
        : { ...def, T: Bend.term_lower(def.T), v: def.v == null ? null : Bend.term_lower(def.v),
          i: def.i?.map(f => path.resolve(f)) }),
    ]));
    const foreign = Object.values(declarations).flatMap(d => d.i ?? []);
    const laws = path.join(path.dirname(entry), 'LAWS.bend');
    return { $: 'Done', value: encode({ ...upstream, entry: realpathSync(entry),
      inputs: [...new Set([...seen.keys(), ...foreign])], order: book.order, templates: book.tmps,
      declarations, holes: book.hols, open: book.open,
      paired_laws_missing: path.basename(entry) === 'PROOF.bend' && existsSync(laws) && !seen.has(realpathSync(laws)),
    }) };
  } catch (error) {
    return { $: 'Fail', error: diagnostic(error) };
  }
}

// The existing upstream JS compiler bootstraps our Bend modules; it is not a
// target backend offered by this frontend. Never load the user's program here.
export async function bend(file) {
  checkUpstream();
  await import('../vendor/bend/bend2/main.ts');
  return (await import(file)).default;
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
