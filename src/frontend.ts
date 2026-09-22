import { execFileSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as Bend from '../vendor/bend/bend2/bend.ts';
import upstream from '../upstream.json';
import { exportTerm, type CheckedProgram } from './core.ts';

export type { CheckedProgram, CoreDeclaration, CoreTerm, CorePattern, Quantity } from './core.ts';

const upstreamDirectory = fileURLToPath(new URL('../vendor/bend', import.meta.url));

function checkUpstream(): void {
  const git = (...args: string[]) => execFileSync('git', ['-C', upstreamDirectory, ...args], { encoding: 'utf8' }).trim();
  if (git('rev-parse', 'HEAD') !== upstream.commit || git('status', '--porcelain', '--untracked-files=no')) {
    throw new Error('vendor/bend must be unchanged at the commit in upstream.json; run git submodule update --init');
  }
}

function diagnostic(error: unknown): string {
  if (error && typeof error === 'object' && '$' in error && error.$ === 'Err') {
    return Bend.err_show(error as Bend.Err);
  }
  return error instanceof Error ? error.message : String(error);
}

// Target-independent checking only. No compiler-reserved names, entry-point
// requirement, execution, erasure, or target-specific representation choices.
export async function check(file: string): Promise<CheckedProgram> {
  checkUpstream();
  const entry = path.resolve(file);
  const book = Bend.book_nil();
  const seen = new Map<string, string | null>();
  try {
    await Bend.book_load(book, entry, '', seen);
    const laws = path.join(path.dirname(entry), 'LAWS.bend');
    if (path.basename(entry) === 'PROOF.bend' && existsSync(laws) && !seen.has(realpathSync(laws))) {
      throw new Error('PROOF.bend must import the adjacent LAWS.bend');
    }
    Bend.book_valid(book);
    if (book.hols || book.open) {
      throw new Error(`Incomplete program: ${book.hols} proof holes and ${book.open} open laws`);
    }
    const foreign = Object.values(book.tlds).flatMap(def => def.$ === 'Def' ? def.i ?? [] : [])
      .map(file => path.resolve(file));
    return exportProgram(book, realpathSync(entry), [...new Set([...seen.keys(), ...foreign])]);
  } catch (error) {
    throw new Error(diagnostic(error), { cause: error });
  }
}

function exportProgram(book: Bend.Book, entry: string, inputs: string[]): CheckedProgram {
  const lower = (term: Bend.HTerm) => exportTerm(Bend.term_lower(term));
  return {
    format: 'bend-frontend.core',
    version: 1,
    upstream: { ...upstream },
    entry,
    inputs,
    order: book.order,
    templates: book.tmps,
    declarations: Object.entries(book.tlds).map(([name, def]) => {
      const common = { name, kind: def.$, base: def.b === true, arity: def.n, type: lower(def.T) };
      if (def.$ === 'ADT') {
        return { ...common, kind: 'ADT' as const, parameters: def.n, quantityParameters: def.g,
          constructors: def.c.map(c => ({ name: c.k, arity: c.n, type: lower(c.T) })) };
      }
      return { ...common, kind: 'Def' as const, templateParameters: def.x,
        unsafe: def.u === true, foreign: (def.i ?? []).map(file => path.resolve(file)),
        sourceBody: def.v === null ? null : lower(def.v),
        checkedBody: def.e === undefined ? null : exportTerm(def.e) };
    }),
  };
}
