# bend-frontend

A composable frontend for **full upstream Bend 2**. It loads source and imports, elaborates syntax, checks types, quantities, termination and proofs, and returns a typed, serializable checked program.

```text
Bend source → upstream parser and checker → CheckedProgram → your consumer
```

The library has no compiler or runtime dependency, backend registry, target selection, or requirement for a `main` function. Backends and analysis tools are ordinary functions that consume `CheckedProgram`; the frontend does not register or call them.

## Use

Requires Git and Bun (tested with 1.3.12).

```sh
git submodule update --init
bun install --frozen-lockfile
bun run cli check examples/PROOF.bend
bun run cli export examples/program.bend -o build/program.core.json
bun test
bun run typecheck
```

The library is the package's primary entry point. The CLI only checks or writes the same data as JSON.

```ts
import { check, type CheckedProgram } from 'bend-frontend';

const program = await check('examples/program.bend');

// A consumer needs only the public data types.
function definitions(program: CheckedProgram) {
  return program.declarations.filter(d => d.kind === 'Def');
}

console.log(definitions(program).map(d => d.name));
```

`check(file)` resolves a filesystem entry and uses upstream import resolution, including `Base` and content-addressed packages (which upstream may fetch if absent). It rejects failed checks, holes, and open laws. `PROOF.bend` must import an adjacent `LAWS.bend` when one exists. Errors retain upstream's diagnostic text. Checking can normalize terms, but does not run `main` or load foreign implementations; those files need not exist yet.

## The boundary

The public types are `CheckedProgram`, `CoreDeclaration`, `CoreTerm`, `CorePattern`, and `Quantity`, defined in [src/core.ts](src/core.ts). Their fields contain plain objects, arrays, strings, numbers, booleans, and null; optional fields may be absent. There are no upstream `Book` objects, JavaScript functions, or source-span objects to interpret.

The program carries `format: "bend-frontend.core"`, `version: 1`, and the upstream revision. The format is versioned; breaking representation changes require a version change. It is checked core syntax, not an executable machine IR.

| Field | Meaning |
| --- | --- |
| `entry`, `inputs` | Absolute entry path and loaded source/declared foreign file paths. No transitive foreign includes or content attestation. |
| `declarations` | All loaded declarations, including Base and generated template instances, identified by canonical `name`. |
| `order` | Upstream declaration/checking order; a law and its fill can repeat a name. |
| `templates` | Template name → upstream specialization key → generated declaration name. Treat keys as opaque. |

Each declaration includes its type, arity, and whether it came from Base. Arity includes erased and template binders; a constructor's arity counts its own fields, while its type includes the datatype parameters too. Datatypes include constructors and their types, parameter count, and leading quantity-parameter count. Definitions include `sourceBody` (elaborated syntax before checking), `checkedBody` (with checker annotations and specialized calls), template-parameter count, an explicit `unsafe` marker, and declared `foreign` paths. Foreign and primitive declarations can have null bodies.

For templates, the first `templateParameters` leading `All` binders correspond to symbolic `Ref` names formed as `declaration.name + "~" + binder.k`, with each binder's domain as its type (substitute earlier symbolic parameters in dependent domains). These parameters are already substituted out of `checkedBody`, whose remaining binder levels start at zero. Concrete instances are separate definitions with zero template parameters.

Core terms retain upstream's tagged syntax:

- `Var` identifies a local by absolute binder level `i`, not its spelling `k`. If `v` is present, it carries the explicit memoized value/type; annotation placeholders such as `_` at level `-1` must be read through `v`. `Ref.k` names a declaration (or a template's symbolic parameter); `Ref.b` preserves the call's `!` hint.
- `All` describes a dependent function type; `Lam` binds its argument; `App` applies it. Quantities are `None` (erased), `Lone` (affine), and `Many` (duplicable). Read quantities from checked type annotations as well as binders.
- `Let` retains parallel groups: its values are in the outer scope, and its body binds all names/levels together. It is not a sequence of nested lets.
- `ADT` applies a datatype; `r` lists excluded constructors in a refined type. `Ctr` constructs a value. `Mat` has a constructor handler `h` and remaining cases `m`; `Efq` is the empty case eliminator.
- `Ann` retains types, and `Sub` retains substitutions, including pattern substitutions. `Typ`, `Qnt`, `Qua`, `Min`, `Eql`, `Rfl`, and `Rwt` preserve kind, quantity, and proof information. `Lit` preserves compact Nat/string literals. `Hol` remains in the syntax union, but unfinished user proofs are rejected by checking.

Higher-order annotations are reified before export, so JSON serialization does not silently drop their binder functions. The complete prelude is retained; exports can be large. Reachability, erasure, closure conversion, memory layout, effect handling, and code generation belong to future consumers.

`@unsafe` and foreign declarations retain upstream's escape hatches. Their markers are explicit declarations, not a transitive safety analysis: a dependent definition is not unconditionally proved simply because its own `unsafe` flag is false. The exported object is not a proof certificate or an authenticated artifact, and mutating it does not re-check it.

## Development

The example covers recursive data, parallel bindings, a captured closure, template specialization, erased and duplicable parameters, arrays, and a checked equality law. Tests exercise the public boundary and failed checks, without generating or executing target code.

`vendor/bend` is the unmodified Apache-2.0 upstream submodule, pinned by `upstream.json`. The full source checkout includes upstream backend files for provenance, but this library imports only `bend2/bend.ts` and its prelude; foreign sources are recorded, not loaded as code. A test checks the library's module graph for compiler/runtime dependencies. Checking refuses a different or modified tracked upstream checkout. Upgrade the gitlink and manifest together, then rerun the tests.

For Bend syntax, run `bun vendor/bend/bend2/main.ts guide`. The trusted kernel is never patched. `bun run typecheck` excludes two existing upstream TS2339 narrowing errors at `bend.ts:2125` and `bend.ts:3828`, and fails on every other diagnostic. Plain `bunx tsc --noEmit` reports those two errors.

The bendSVM project informed the reuse of upstream checking. No bendSVM source or bounded SVM representation is included. Backend choices remain open.
