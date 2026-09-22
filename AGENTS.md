# bend-frontend

- Keep the full upstream language. Do not replace the checker with a subset parser.
- Never edit the vendored trusted kernel. Pin upstream changes deliberately.
- Use `cx overview` and `cx definition` to navigate code.
- Run `bun vendor/bend/bend2/main.ts guide` before writing Bend; put important example rules in `examples/LAWS.bend`.
- Before committing, run `bun run check`, `bun run test`, and `bun run test:lowering` (requires solc/anvil).
- Keep the Bend frontend target-independent. Backends stay in explicit examples/consumers. The JavaScript host may use upstream main.ts/comp.ts to bootstrap our Bend tools, but must never compile or execute the user input during checking.
- Keep the public output self-contained, typed, and serializable; preserve checked quantities and semantics.
- Do not describe a checked syntax export as a verified compiler or proof certificate.

- First-party implementation and proofs are Bend. Keep JavaScript limited to the upstream/IO adapter, launchers, and test harnesses; do not reintroduce TypeScript or a separate host-language lowering.
- `src/core.bend` is the authoritative schema. Preserve every checked construct and mark export format changes explicitly.
