# EVM backend (spike)

Contracts are ordinary Bend functions in the `Contract` monad of [Evm.bend](Evm.bend). Specs are laws about them, as in [counter/LAWS.bend](counter/LAWS.bend).

```text
contract.bend ─ Frontend.check ─ read.bend ─ IR ─ certify.bend ─ CERT.bend ─ Bend checks IR ≡ contract
```

[certify.bend](certify.bend) prints each entry as a literal [IR](ir.bend) value and a law stating that `IR.call` of that value equals the source function. `IR.call` reverts when a variable is not bound, then runs the IR. The IR constructors map one to one to DSL calls, so both sides normalize to the same term and `{==}` proves the law.

The reader ([read.bend](read.bend)) is not trusted: a wrong IR makes the certificate fail. The trusted base is the Bend checker, the semantics in [Evm.bend](Evm.bend) and [ir.bend](ir.bend), and the shape of the law that certify.bend prints. certify.bend rejects a contract that imports a different `Evm.bend`, and a parameter list that does not bind levels 0, 1, ... in order.

```sh
bun host/run.js backends/evm/certify.bend backends/evm/counter/program.bend get increment set \
  > backends/evm/counter/CERT.bend
bun vendor/bend/bend2/main.ts backends/evm/counter/CERT.bend
bun run test:evm
```

## Model

- Words are `Nat`. Checked `add` reverts at the state's `limit`, which is 2^256 on the EVM. Proofs keep the limit symbolic: the checker writes any closed Nat near 2^256 out in unary.
- Storage is an association list: the newest slot wins and missing slots read as zero. A revert discards all state.
- Supported now: `sload`, `sstore`, `caller`, checked `add`, `require`, `pure`, Nat parameters and literal constants. The reader rejects everything else.

## Limits

- The certificate's imports are relative. Save it as `CERT.bend` beside the contract, or it names other files.
- certify.bend must run through `host/run.js`, which gives it its own path in `BEND_ENTRY`.
- Literals are limited by `Nat.read` (about 2^48). Source Nat literals already stop at 2^32 - 1.
- There is no Yul lowering yet. The IR → Yul preservation proof is the next step.
- In the reader, match on `Call` names, not on nested `Term` patterns: nested patterns over Term made checking take 6 GB.
