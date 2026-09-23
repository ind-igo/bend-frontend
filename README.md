# bend-frontend

A composable frontend for **full upstream Bend 2**, written in Bend. It checks a program once and hands backends a typed, serializable `Core.Program`.

```text
Bend source → upstream checker → generic data → Bend decoder → Core.Program → backend
```

The frontend has no backend registry or target selection and does not require the input to define `main`. It checks types, quantities, termination and proofs without executing the input or its effects.

## Use

Requires Git and Bun (tested with Bun 1.3.12). There are no package dependencies.

```sh
git submodule update --init
bun run cli check tests/fixtures/PROOF.bend
bun run cli export tests/fixtures/program.bend -o build/program.core.json
bun run check          # check all first-party Bend entry points and proofs
bun run test           # frontend tests
```

Use these scripts: plain `bun test` also discovers upstream's tool tests.

The CLI is [src/cli.bend](src/cli.bend). [host/run.js](host/run.js) launches it, or any other Bend driver, with the checker/IO adapter attached:

```sh
bun host/run.js src/cli.bend check tests/fixtures/program.bend
```

`run.js` sets `BEND_ENTRY` to the driver's real path, so a driver can find the files beside it.

To write a backend, read [Connecting Bend to backends](docs/backends.md). [bend-evm](https://github.com/ind-igo/bend-evm) is a backend in its own repository: it lowers to Yul for the EVM and uses this repository as a submodule.

## The Bend interface

[src/frontend.bend](src/frontend.bend) exposes:

```bend
# Frontend.check returns IO(Result<&2, &2, String, Core.Program>).
result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
# Frontend.or_die(A, result) stops with the error instead.
program : Core.Program <- Frontend.or_die(Core.Program, result)
```

`Frontend.finish` is the pure step from host data to an accepted program. It runs [decode.bend](src/decode.bend), which translates upstream terms, patterns, declarations and templates, validates metadata and counts term nodes. It rejects proof holes, open laws, and a `PROOF.bend` that does not import its adjacent `LAWS.bend`.

JavaScript callers can use the same frontend:

```js
import { check, array } from 'bend-frontend';

const program = await check('tests/fixtures/program.bend');
console.log(array(program.declarations).map(d => d.header.name));
```

## Export format 2

[src/core.bend](src/core.bend) is the authoritative schema. `check` returns the same constructor-shaped `Core.Program` that Bend consumers receive; `export` writes it as JSON. It round-trips through `JSON.stringify`/`JSON.parse`: no functions, source spans, upstream `Book` or `BigInt` values.

Lists are `Con{head, tail}` / `Nil{}`, options are `Some{value}` / `None{}`, and constructors carry a `$` tag. The host `array` helper converts lists for JS callers.

| Program field | Meaning |
| --- | --- |
| `format`, `version` | `bend-frontend.core`, `2` |
| `repository`, `commit` | Pinned upstream identity |
| `entry`, `inputs` | Absolute entry and loaded source/declared foreign paths |
| `order` | Check/declaration order; laws and their fills can repeat a name |
| `templates` | Template names and opaque specialization-key → generated-name mappings |
| `declarations` | Every declaration outside Base, and every declaration these reach by name. Instances of Base templates count as Base |
| `nodes` | Number of reified term nodes; a traversal bound, not a cost or gas bound |

`Algebraic` and `Definition` share a `Header` with `name`, `base`, `arity` and `typ`. Definitions also keep template counts, unsafe markers, foreign paths and optional source/checked bodies. Foreign implementations are recorded, not loaded, and need not exist. Unreached Base declarations are left out, and `order` and `templates` only name exported declarations. Exports can still be large: exporting the frontend itself gives millions of term nodes.

`Term` constructors mirror upstream's syntax with a `T` prefix. Consumers must preserve:

- `Bound{value}` is an absolute binder level, not a de Bruijn distance. `Placeholder{}` is upstream's `-1` level. Variable names do not establish identity.
- `TVar.memo` holds memoized values/types. `Core.bare` unwraps these and `TAnn` only; its idempotence is proved in [src/PROOF.bend](src/PROOF.bend).
- Quantities are `Erased`, `Affine` or `Reusable`. Lambda quantities and checked annotations are kept. Do not infer erasure from names.
- `TLet.bindings` is a parallel group: every RHS is in the outer scope, and the body binds the whole group.
- `TADT.excluded` keeps constructor exclusions in refined types. `TMat.hit` / `miss` and `TEfq` keep matching and empty elimination.
- `TSub.value` is `Inl{term}` or `Inr{pattern}`.
- Natural literals are decimal strings; text literals are separate. Counts and nonnegative levels are U32, and out-of-range metadata is rejected, not truncated.
- A definition's arity includes erased/template binders. A constructor's arity counts its own fields; its type also includes datatype parameters.
- Leading template binders correspond to symbolic references named `declaration.name + "~" + binder.name`. Substitute earlier parameters into dependent domains. Checked bodies drop these binders, so their levels start at zero. Concrete instances are separate definitions without template parameters.

## Host boundary and trust

The JavaScript host only connects Bend to upstream:

- [adapter.js](host/adapter.js): verifies the upstream pin, calls the checker, reifies closures into generic data, bootstraps our Bend tools with upstream's JS compiler, and does JSON/file IO. It never builds Core terms and never compiles the user's input. Upstream may fetch content-addressed imports.
- [effects.js](host/effects.js): Bend foreign effects. A subprocess bridges upstream's async loader to its synchronous IO runtime.
- [run.js](host/run.js): attaches the adapter and launches a Bend entry point.

Checking and compiling our Bend tools costs seconds and gigabytes, so the adapter keeps each checked build in `build/cache`. The key is the upstream pin plus the hash of the adapter and of every file upstream read for that tool. A changed input rebuilds it with a full check. The user's program is never cached. `bun run check` still checks every entry point.

[wire.bend](src/wire.bend) is the generic transport. [decode.bend](src/decode.bend) owns the mapping into Core; backends never see transport types.

Trusted, not proved: the upstream checker and compiler, the adapter, and the decoder. The decoder is typechecked and tested, with small laws for its representation choices, but has no preservation theorem. `Core.Program` is mutable data, not a proof certificate, and `unsafe`/`foreign` markers are not a transitive safety analysis. Each backend must state the scope of its own proofs.

`vendor/bend` is the unchanged Apache-2.0 upstream submodule, pinned by `upstream.json`. The host refuses a different or modified checkout; upgrade the gitlink and manifest together.

## License

The frontend's own code is licensed under [MIT](LICENSE). Vendored Bend keeps its [Apache-2.0 license](vendor/bend/LICENSE).
