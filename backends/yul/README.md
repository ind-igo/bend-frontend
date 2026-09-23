# A lowering written and proved in Bend

This is a small consumer of the shared [Core.Program](../../src/core.bend). The frontend still accepts full upstream Bend; this backend accepts U32 arguments/results, variables, local bindings, and direct Base U32 addition/multiplication. Other runtime constructs are rejected.

```text
Frontend.check → Core.Program → arithmetic IR → Yul fragment → Yul text
                                      └─ preservation theorem ─┘
```

The core reader, lowering, printer, and command driver are all Bend. The only host code is the shared checker/IO adapter and the JavaScript execution-test harness.

## Run

From the repository root:

```sh
bun run check
mkdir -p build
bun host/run.js backends/yul/emit.bend > build/calculate.yul
solc --strict-assembly --evm-version shanghai --bin build/calculate.yul
bun run test:lowering

# Select another checked function:
bun host/run.js backends/yul/emit.bend backends/yul/PROOF.bend program.scopes
```

Emission requires Bun and Git. The execution test needs `solc` and `anvil` (tested with 0.8.33 and 1.5.1). It creates and stops a local node, simulates creation/calls without submitting transactions, and checks ordinary results, U32 overflow, nested/parallel scopes, malformed calldata, and call value. Another test deliberately changes multiplication to addition and requires the preservation theorem to fail.

The emitted contract takes exactly three 32-byte big-endian words and returns one. It has no selector or storage. Wrong input lengths, inputs above `0xffffffff`, and nonzero call value revert. The arithmetic body is:

```yul
function entry(v0, v1, v2) -> result {
  let v_body := and(mul(v0, v1), 0xffffffff)
  result := and(add(v_body, v2), 0xffffffff)
}
```

## Read the example

- [program.bend](program.bend): `(a * b) + c`, plus a second example with parallel bindings whose nested RHS scopes reuse binder levels.
- [../u32.bend](../u32.bend): source IR/evaluator and a profile reader over the shared `Core.Term`. Unknown variables and unsupported runtime constructs are rejected. The evaluator's default for a missing environment entry is zero; accepted functions get all their parameters from calldata.
- [lower.bend](lower.bend): target AST/evaluator, lowering, printer, and ABI wrapper. Tree-path names distinguish locals from different scopes; independent subtrees use parallel calls.
- [LAWS.bend](LAWS.bend) and [PROOF.bend](PROOF.bend): a universal IR preservation theorem and correspondence with the original `calculate` function for all inputs.
- [emit.bend](emit.bend): the complete Bend driver using `Frontend.check`.

The theorem covers the actual IR transformation under the specified U32 evaluators. Core reading, text generation, the ABI, and EVM/toolchain semantics are tested boundaries rather than proved ones. This is a worked proof of a pass, not an end-to-end verified EVM compiler.

See [Connecting Bend to backends](../../docs/backends.md) for the extension process and target-specific decisions.
