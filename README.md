# bend-frontend

A composable frontend for **full upstream Bend 2**, written in Bend. The core schema, upstream-to-Core conversion, frontend policy, CLI, and example lowering are Bend programs. A JavaScript host adapter calls the pinned upstream checker and transports its result as generic data.

```text
Bend source → upstream checker → generic data → Bend decoder → Core.Program → consumer
```

The frontend has no backend registry or target selection and does not require the input to define `main`. It checks types, quantities, termination and proofs without executing the input program or its effects. The host uses upstream's JS compiler only to bootstrap our own Bend tools.

## Use

Requires Git and Bun (tested with Bun 1.3.12). There are no package dependencies.

```sh
git submodule update --init
bun run cli check examples/PROOF.bend
bun run cli export examples/program.bend -o build/program.core.json
bun run check
bun run test
```

The CLI implementation is [src/cli.bend](src/cli.bend). The package command invokes it through [host/run.js](host/run.js), which also runs other Bend consumers with the checker/IO adapter attached:

```sh
mkdir -p build
bun host/run.js experiments/yul/emit.bend > build/calculate.yul
bun run test:lowering  # additionally requires solc and anvil
```

Start with [Connecting Bend to backends](docs/backends.md) for the architecture, extension steps, proof boundaries, and EVM/WASM/Zig/ZK considerations. The [Yul walkthrough](experiments/yul/README.md) is a runnable example.

## The Bend interface

[src/core.bend](src/core.bend) is the authoritative schema. [src/frontend.bend](src/frontend.bend) exposes:

```bend
# Frontend.check returns IO(Result<&2, &2, String, Core.Program>).
# Your consumer pattern-matches Done{program} or Fail{error}.
result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
```

`Frontend.finish` is the pure boundary between host observations and an accepted program. It runs [decode.bend](src/decode.bend), which translates upstream terms, patterns, declarations, and templates, validates metadata, and counts term nodes. It rejects proof holes, open laws, and a `PROOF.bend` that does not import its adjacent `LAWS.bend`. The host resolves files/imports, verifies the upstream pin, invokes the checker, and reifies its internal syntax. It never compiles the user's input. Content-addressed imports may be fetched by upstream.

JavaScript callers can use the same Bend frontend through the host convenience API:

```js
import { check, array } from 'bend-frontend';

const program = await check('examples/program.bend');
console.log(array(program.declarations).map(d => d.header.name));
```

## Export format 2

This is a schema change from the initial TypeScript prototype's format 1. `check` returns the same constructor-shaped `Core.Program` that Bend consumers receive. `export` writes it as JSON; it round-trips through ordinary `JSON.stringify`/`JSON.parse`, with no functions, source spans, upstream `Book`, or JavaScript `BigInt` values.

Lists use Bend's `Con{head, tail}` / `Nil{}` representation, options use `Some{value}` / `None{}`, and constructors carry a `$` tag. The host `array` helper is only a convenience for JS callers. No backend-specific reshaping occurs at this boundary.

| Program field | Meaning |
| --- | --- |
| `format`, `version` | `bend-frontend.core`, `2` |
| `repository`, `commit` | Pinned upstream identity |
| `entry`, `inputs` | Absolute entry and loaded source/declared foreign paths |
| `order` | Check/declaration order; laws and their fills can repeat a name |
| `templates` | Template names and opaque specialization-key → generated-name mappings |
| `declarations` | Complete declarations, including Base and generated instances |
| `nodes` | Number of reified term nodes; traversal budget metadata, not a cost or gas bound |

`Algebraic` and `Definition` share a `Header` containing `name`, `base`, `arity`, and `typ`. Definitions retain template counts, unsafe markers, foreign paths, and optional source/checked bodies. Foreign implementations need not exist; they are recorded without loading them. The export includes every declaration rather than pruning unreachable ones, and can be large. Generic transport increases allocation and decoding costs; exporting the frontend itself expands to millions of term nodes. Use `bun run check` for its proof validation without exporting that syntax.

The `Term` constructors correspond to upstream's syntax, prefixed with `T` to avoid Base constructor-name collisions. Details consumers must preserve:

- `Bound{value}` is an absolute binder level, not a de Bruijn distance. `Placeholder{}` preserves upstream's `-1` annotation level. Variable spelling does not establish identity.
- `TVar.memo` explicitly reifies memoized values/types. `Core.bare` unwraps these and `TAnn` without rewriting other constructs; its idempotence is proved in [src/PROOF.bend](src/PROOF.bend).
- Quantities are `Erased`, `Affine`, or `Reusable`; optional lambda quantities and checked type annotations are retained. Do not infer erasure from variable names.
- `TLet.bindings` is a parallel group. Every RHS is in the outer scope; its body binds the whole group. Scope and sharing decisions belong to the consumer.
- `TADT.excluded` retains constructor exclusions in refined types. `TMat.hit` / `miss` and `TEfq` preserve matching and empty elimination.
- `TSub.value` distinguishes a term from a pattern through Base.Either’s `Inl` / `Inr`. The former JS adapter incorrectly emitted `Left` / `Right` for this case; the Bend decoder fixes that mismatch without changing the format-2 schema.
- Natural literal values use decimal strings; the checker has already parsed their source spelling. Text literals are separate constructors. Counts and nonnegative levels are U32; the Bend decoder rejects out-of-range metadata instead of truncating it.
- A definition's arity includes erased/template binders. A constructor's arity counts its own fields, while its type also includes datatype parameters.
- Leading template binders correspond to symbolic references named `declaration.name + "~" + binder.name`. Earlier parameters must be substituted into dependent domains. Checked bodies remove these binders; their remaining levels start at zero. Concrete instances are separate definitions with no template parameters.

The program is mutable host data, not an authenticated proof certificate. Unsafe/foreign markers are not a transitive safety analysis. Backend support and preservation proofs must state their own scope.

## Host boundary and development

All first-party TypeScript files and TypeScript/Incur dependencies have been removed. The remaining host files perform operations that connect Bend to its existing implementation:

- [adapter.js](host/adapter.js): upstream checking and closure reification, generic data transport, JS bootstrap, JSON/file IO and input-overwrite protection. It does not construct Core terms or declarations.
- [effects.js](host/effects.js): Bend foreign-effect entry points. A subprocess bridges upstream's async loader to its synchronous JS IO runtime.
- [run.js](host/run.js): attaches that adapter and launches a Bend entry point.

[wire.bend](src/wire.bend) defines the generic transport and a structural bottom-up fold. [decode.bend](src/decode.bend) owns the mapping into Core; backends consume Core directly and never need the transport types. The fold has no arbitrary traversal fuel limit.

The IO bridge requires Bun and incurs a worker startup plus serialization and generic-tree decoding. It is not a native C embedding of the checker. The adapter and upstream checker/compiler remain trusted; porting conversion and policy to Bend does not verify them. The decoder is typechecked and regression-tested, with small checked laws for substitution representation and metadata overflow; it does not yet have a full preservation theorem.

`bun run check` checks all first-party Bend entry points and proofs without running their effects. `bun run test` runs the frontend tests; `bun run test:lowering` checks actual Yul/EVM execution and deliberately breaks a lowering to ensure its proof rejects it. Use these scripts: unfiltered `bun test` also discovers upstream's separate tool tests.

`vendor/bend` is the unchanged Apache-2.0 upstream submodule pinned by `upstream.json`. Its TypeScript implementation remains upstream code. The host refuses a different or modified tracked checkout; upgrade the gitlink and manifest together. No bendSVM source was copied.

## License

The frontend's own code is licensed under [MIT](LICENSE). Vendored Bend retains its [Apache-2.0 license](vendor/bend/LICENSE).
