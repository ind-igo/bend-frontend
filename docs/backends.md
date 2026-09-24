# Connecting Bend to different backends

A backend is a Bend consumer of `Core.Program`. The frontend checks the full upstream language once; each backend decides which runtime features it supports and how to represent them. There is no backend registry to implement or modify.

A backend lives in its own repository and uses this one as a git submodule. The working reference is [bend-evm](https://github.com/ind-igo/bend-evm). It reads contracts written in a small `Contract` monad, lowers them to a Yul fragment in Bend, proves that the lowering preserves every command, and runs the printed Counter on a local EVM.

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

The EVM backend's driver, [compile.bend](https://github.com/ind-igo/bend-evm/blob/main/src/compile.bend), does this:

```bend
result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
program : Core.Program <- Frontend.or_die(Core.Program, result)
text : String <- Frontend.or_die(String, contract(program, backend, Certify.strings(entries)))
```

Entry names are checked declaration names. Use the declaration headers instead of guessing names from source text.

Run it from the bend-evm root:

```sh
bun vendor/bend-frontend/host/run.js src/compile.bend \
  examples/counter/program.bend get increment set > build/Counter.yul
```

`host/run.js` launches any Bend driver the same way. Backends consume Core only; they never touch the host or the transport.

## Adding a backend

1. **Define acceptance.** Select an entry, inspect its checked type, and determine its reachable runtime requirements. Reject unsupported calls, types, quantities, or effects explicitly. Checking a full Bend source file does not imply that every target can execute it. Never treat `unsafe: false` alone as evidence that dependencies are safe.
2. **Choose the runtime IR.** Reuse [ir.bend](https://github.com/ind-igo/bend-evm/blob/main/src/ir.bend) if its storage, caller, checked add, and require are sufficient. For richer programs, add the constructs the next example needs. Full core includes proofs and dependent types; it is not already a machine IR.
3. **Define the target AST and its meaning.** State what its operations, values, scopes, errors, and effects mean. Make integer width and overflow explicit. A precise small fragment is useful; an AST named after a machine is not by itself a complete machine model.
4. **Implement the lowering in Bend.** Return target data rather than building strings while deciding semantics. Keep target-independent transformations separate when there is actual reuse.
5. **State and prove preservation.** Relate the input and output evaluators, including representation changes and acceptance conditions. Keep statements in `LAWS.bend` and implementations in `PROOF.bend`.
6. **Print/encode and execute.** Produce text or bytes from the same target AST, then test the emitted artifact with the actual target toolchain. Test failure paths and boundary values as well as ordinary results.

The EVM reader, [read.bend](https://github.com/ind-igo/bend-evm/blob/main/src/read.bend), consumes `Core.Term` directly. It drops annotations, finds the `Evm.bend` module that the contract imports, and reads each DSL call into one IR command. No separate JS-to-IR converter is needed. The reader is not trusted: a certificate proves that its IR equals the source function.

## What changes between targets

| Target | Artifact and decisions |
| --- | --- |
| EVM/Yul | Yul text and then bytecode. Define the calldata/return ABI, storage/effects, integer widths, reverts, and gas assumptions. The example checks `add` for overflow at 2^256 and reverts. |
| WASM | WASM instructions or WAT, followed by validation/encoding. Define imports, linear-memory layout, allocation, call signatures, and how closures or recursive data are represented. Larger integers need an explicit multiword implementation. |

There is no need to copy Solana's specific size, stack, or recursion limits. A bounded profile is a practical starting point when it matches a target; bounds should be justified by that target. Conversely, termination alone does not prove that execution fits a gas, memory, or prover budget.

## The proof pattern

The runnable example proves that the actual `lower` function preserves the outcome of every IR command, for every output kind, environment and state:

```bend
law preserves:
  for +cmd: IR.Cmd
  for +out: IR.Output
  for +env: List<&2, IR.Binding>
  for +s: Evm.State
  {Yul.exec(Yul.lower(cmd, out), out, env, s) == IR.run(cmd, out, env, s) : Evm.Outcome<IR.value(out)>}
```

Read [PROOF.bend](https://github.com/ind-igo/bend-evm/blob/main/src/PROOF.bend): each case matches the command and the state, so storage reads and writes compute, and the body uses the induction hypothesis. Checked add uses one lemma: the Yul guard `gt(b, sub(not(0), a))` is zero exactly when `a + b < limit`. A certificate connects each contract function to its IR for all inputs. A test changes the lowering and checks that the theorem fails.

For a different representation, the statement may instead be:

```text
decode(target_eval(lower(source), encode(inputs))) = source_eval(source, inputs)
```

That is a specification sketch, not executable Bend syntax. A real statement must define the valid input domain, the encoding relation, all observable results, and any failure/resource assumptions. For a partial lowering, preservation applies when lowering returns `Done`; rejecting a program is not evidence that it was compiled correctly.

Proofs compose when their intermediate semantics and assumptions agree. A shared erasure or normalization pass can be proved once, and multiple backends can reuse it. State relations are needed when representations change; effectful programs require preservation of relevant events and state, not only the final numeric answer.

## The current boundary

In that example, the theorem covers IR → the modeled Yul fragment. The model's `add`, `sub`, `not` and `gt` are the EVM's operations on words below `limit`. The connection to the printed Yul and the actual EVM is tested, not formally proved.

Outside that theorem: everything the [README](../README.md#host-boundary-and-trust) lists as trusted, plus the printer, the ABI dispatcher and `solc`. The Core reader is not trusted: the certificate checks its output. Every added guarantee needs its own law and checked proof.
