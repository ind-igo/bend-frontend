# bend-frontend

- Keep the full upstream language. Do not replace the checker with a subset parser.
- Never edit the vendored trusted kernel. Pin upstream changes deliberately.
- Use `cx overview` and `cx definition` to navigate code.
- Run `bun vendor/bend/bend2/main.ts guide` before writing Bend; put important example rules in `tests/fixtures/LAWS.bend`.
- Before committing, run `bun run check` and `bun run test`.
- Keep the Bend frontend target-independent. Backends live in their own repositories as explicit consumers, such as bend-evm. The JavaScript host may use upstream main.ts/comp.ts to bootstrap our Bend tools, but must never compile or execute the user input during checking.
- Keep the public output self-contained, typed, and serializable; preserve checked quantities and semantics.
- Do not describe a checked syntax export as a verified compiler or proof certificate.

- First-party implementation and proofs are Bend. Keep JavaScript limited to the upstream/IO adapter, launchers, and test harnesses; do not add TypeScript or a host-language lowering.
- `src/core.bend` is the authoritative schema. Preserve every checked construct and mark export format changes explicitly.
