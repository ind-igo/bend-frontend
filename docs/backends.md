# Connecting Bend to different backends

A backend is a Bend consumer of `Core.Program`. The frontend checks the full upstream language once; each backend decides which runtime features it supports and how to represent them. There is no backend registry to implement or modify.

A backend lives in its own repository and uses this one as a git submodule. The working reference is [the U32 Yul example](https://github.com/ind-igo/bend-evm/blob/main/yul-u32/README.md) in [bend-evm](https://github.com/ind-igo/bend-evm). It accepts a deliberately small arithmetic profile, lowers it in Bend, proves a preservation theorem, and executes the printed result on a local EVM.

## The connection

```text
Source and imports
       ↓ upstream parsing, elaboration and checking
Host adapter → generic data → Bend decoder → Core.Program
                    ↓ backend acceptance / entry selection
             Target-independent runtime IR
                    ↓ proved lowering
                Target AST
                    ↓ printer or encoder
                 Artifact
```

The authoritative types live in [core.bend](../src/core.bend). [frontend.bend](../src/frontend.bend) provides `check(file)`, returning `IO(Result<&2, &2, String, Core.Program>)`. Pattern-match the result, then pass the program to your backend's ordinary Bend function.

The Yul implementation uses this signature:

```bend
def compile(program: Core.Program, name: String) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    fn : Source.Function <- Source.entry(program, name)
    return emit(fn)
```

`name` is a canonical checked declaration name. Checking `program.bend` directly exposes `calculate`; importing it from `PROOF.bend` exposes `program.calculate`. Use declaration headers instead of guessing names from source text.

[emit.bend](https://github.com/ind-igo/bend-evm/blob/main/yul-u32/emit.bend) is the complete driver: read arguments, call `Frontend.check`, call `Yul.compile`, report errors, and write the result. Run it from the bend-evm root:

```sh
mkdir -p build
bun vendor/bend-frontend/host/run.js yul-u32/emit.bend \
  yul-u32/PROOF.bend program.calculate > build/calculate.yul
```

`host/run.js` launches any Bend driver the same way. Backends consume Core only; they never touch the host or the transport.

## Adding a backend

1. **Define acceptance.** Select an entry, inspect its checked type, and determine its reachable runtime requirements. Reject unsupported calls, types, quantities, or effects explicitly. Checking a full Bend source file does not imply that every target can execute it. Never treat `unsafe: false` alone as evidence that dependencies are safe.
2. **Choose the runtime IR.** Reuse [u32.bend](https://github.com/ind-igo/bend-evm/blob/main/yul-u32/u32.bend) if the example's variables, lets, add, and multiply are sufficient. For richer programs, add the constructs the next example needs. Full core includes proofs and dependent types; it is not already a machine IR.
3. **Define the target AST and its meaning.** State what its operations, values, scopes, errors, and effects mean. Make integer width and overflow explicit. A precise small fragment is useful; an AST named after a machine is not by itself a complete machine model.
4. **Implement the lowering in Bend.** Return target data rather than building strings while deciding semantics. Keep target-independent transformations separate when there is actual reuse.
5. **State and prove preservation.** Relate the input and output evaluators, including representation changes and acceptance conditions. Keep statements in `LAWS.bend` and implementations in `PROOF.bend`.
6. **Print/encode and execute.** Produce text or bytes from the same target AST, then test the emitted artifact with the actual target toolchain. Test failure paths and boundary values as well as ordinary results.

The existing reader consumes `Core.Term` directly. It unwraps annotations, checks Base primitive identity, validates binders, and sequentializes pure parallel groups inside Bend. No separate JS-to-arithmetic-IR converter is needed. Its traversal fuel comes from the exported node count and only makes the mixed term/binding-list traversal total; it is not an execution fuel policy or a gas estimate.

## What changes between targets

| Target | Artifact and decisions |
| --- | --- |
| EVM/Yul | Yul text and then bytecode. Define the calldata/return ABI, storage/effects, integer widths, reverts, and gas assumptions. The example masks arithmetic to preserve U32 wrapping on 256-bit words. |
| WASM | WASM instructions or WAT, followed by validation/encoding. Define imports, linear-memory layout, allocation, call signatures, and how closures or recursive data are represented. Larger integers need an explicit multiword implementation. |

There is no need to copy Solana's specific size, stack, or recursion limits. A bounded profile is a practical starting point when it matches a target; bounds should be justified by that target. Conversely, termination alone does not prove that execution fits a gas, memory, or prover budget.

## The proof pattern

The runnable example proves the actual `lower` function preserves its modeled U32 meaning for every source expression and environment:

```bend
law preserves:
  for +expr: Source.Expr
  for +env: List<&2, Source.Binding<U32>>
  {Yul.eval(Yul.lower(expr), env) == Source.eval(expr, env) : U32}
```

Read [PROOF.bend](https://github.com/ind-igo/bend-evm/blob/main/yul-u32/PROOF.bend): the variable case reduces directly; add and multiply use the induction hypotheses for their children; the binding case first equates the bound values and then uses the body theorem under the extended environment. The example also connects its readable arithmetic IR to the original Bend function for all inputs. A test replaces multiplication with addition and checks that the universal theorem fails.

For a different representation, the statement may instead be:

```text
decode(target_eval(lower(source), encode(inputs))) = source_eval(source, inputs)
```

That is a specification sketch, not executable Bend syntax. A real statement must define the valid input domain, the encoding relation, all observable results, and any failure/resource assumptions. For a partial lowering, preservation applies when lowering returns `Done`; rejecting a program is not evidence that it was compiled correctly.

Proofs compose when their intermediate semantics and assumptions agree. A shared erasure or normalization pass can be proved once, and multiple backends can reuse it. State relations are needed when representations change; effectful programs require preservation of relevant events and state, not only the final numeric answer.

## The current boundary

In that example, the theorem covers arithmetic IR → the modeled Yul U32 fragment. Its evaluator defines `Add32` and `Mul32` using Bend U32 operations. The connection to the printed masks and actual EVM semantics is tested, not formally proved.

Outside that theorem: everything the [README](../README.md#host-boundary-and-trust) lists as trusted, plus the Core reader, the printer, the ABI wrapper and `solc`. Every added guarantee needs its own law and checked proof.
