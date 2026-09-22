import * as Bend from '../vendor/bend/bend2/bend.ts';

export type Quantity = { $: 'None' } | { $: 'Lone' } | { $: 'Many' };

export type CorePattern =
  | { $: 'PVar'; k: string; i: number; q: Quantity }
  | { $: 'PCtr'; k: string; x: CorePattern[] };

export type CoreDeclaration = {
  name: string;
  base: boolean;
  arity: number;
  type: CoreTerm;
} & (
  | { kind: 'ADT'; parameters: number; quantityParameters: number;
      constructors: { name: string; arity: number; type: CoreTerm }[] }
  | { kind: 'Def'; templateParameters: number; unsafe: boolean; foreign: string[];
      sourceBody: CoreTerm | null; checkedBody: CoreTerm | null }
);

/** The public frontend output. No runtime, checker objects, or JS closures. */
export type CheckedProgram = {
  format: 'bend-frontend.core';
  version: 1;
  upstream: { repository: string; commit: string };
  entry: string;
  inputs: string[];
  order: string[];
  templates: Record<string, Record<string, string>>;
  declarations: CoreDeclaration[];
};

// The pinned checker's first-order syntax, with memoized higher-order values
// made explicit. This is checked core syntax, not a machine or circuit IR.
export type CoreTerm =
  | { $: 'Var'; k: string; i: number; v?: CoreTerm }
  | { $: 'Ref'; k: string; b?: boolean }
  | { $: 'Sub'; i: number; v: CoreTerm | CorePattern; f: CoreTerm }
  | { $: 'Let'; k: string[]; i: number[]; q: Quantity[]; v: CoreTerm[]; f: CoreTerm }
  | { $: 'Typ'; g: CoreTerm }
  | { $: 'Qnt' }
  | { $: 'Qua'; q: Quantity }
  | { $: 'Min'; a: CoreTerm; b: CoreTerm }
  | { $: 'All'; q: Quantity; k: string; i: number; A: CoreTerm; B: CoreTerm }
  | { $: 'Lam'; k: string; i: number; f: CoreTerm; q?: Quantity }
  | { $: 'App'; f: CoreTerm; x: CoreTerm }
  | { $: 'ADT'; k: string; x: CoreTerm[]; r: string[] }
  | { $: 'Ctr'; k: string; x: CoreTerm[] }
  | { $: 'Lit'; v: string | number }
  | { $: 'Mat'; k: string; h: CoreTerm; m: CoreTerm }
  | { $: 'Efq' }
  | { $: 'Eql'; a: CoreTerm; b: CoreTerm; T: CoreTerm }
  | { $: 'Rfl' }
  | { $: 'Rwt'; e: CoreTerm; p: CoreTerm; f: CoreTerm }
  | { $: 'Hol'; k: string }
  | { $: 'Ann'; x: CoreTerm; T: CoreTerm };

export function exportTerm(term: Bend.LTerm, depth = 0): CoreTerm {
  const { s: _span, ...t } = term;
  const recur = (child: Bend.LTerm) => exportTerm(child, depth);
  switch (t.$) {
    case 'Var': return { $: 'Var', k: t.k, i: t.i, ...(t.v === undefined ? {} : {
      v: exportTerm(Bend.term_lower(t.v, depth), depth),
    }) };
    case 'Ref': case 'Qnt': case 'Qua': case 'Lit':
    case 'Efq': case 'Rfl': case 'Hol': return t;
    case 'Sub': return { ...t, v: t.v.$ === 'PVar' || t.v.$ === 'PCtr' ? exportPattern(t.v) : recur(t.v), f: recur(t.f) };
    case 'Let': return { ...t, v: t.v.map(recur), f: exportTerm(t.f, depth + t.k.length) };
    case 'Typ': return { ...t, g: recur(t.g) };
    case 'Min': return { ...t, a: recur(t.a), b: recur(t.b) };
    case 'All': return { ...t, A: recur(t.A), B: exportTerm(t.B, depth + 1) };
    case 'Lam': return { ...t, f: exportTerm(t.f, depth + 1) };
    case 'App': return { ...t, f: recur(t.f), x: recur(t.x) };
    case 'ADT': case 'Ctr': return { ...t, x: t.x.map(recur) };
    case 'Mat': return { ...t, h: recur(t.h), m: recur(t.m) };
    case 'Eql': return { ...t, a: recur(t.a), b: recur(t.b), T: recur(t.T) };
    case 'Rwt': return { ...t, e: recur(t.e), p: recur(t.p), f: recur(t.f) };
    case 'Ann': return { ...t, x: recur(t.x), T: recur(t.T) };
    default: {
      const unknown: never = t;
      throw new Error(`Unknown Bend core term: ${JSON.stringify(unknown)}`);
    }
  }
}

function exportPattern(pattern: Bend.Patt): CorePattern {
  const { s: _span, ...p } = pattern;
  return p.$ === 'PVar' ? p : { ...p, x: p.x.map(exportPattern) };
}
