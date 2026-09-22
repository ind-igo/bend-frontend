# bend-frontend

- Keep the full upstream language. Do not replace the checker with a subset parser.
- Never edit the vendored trusted kernel. Pin upstream changes deliberately.
- Use `cx overview` and `cx definition` to navigate code.
- Run `bun vendor/bend/bend2/main.ts guide` before writing Bend; put important example rules in `examples/LAWS.bend`.
- Before committing, run `bun run cli check examples/PROOF.bend`, `bun test`, and `bun run typecheck`.
- This project is frontend only. Do not add backends, runtime code, or dependencies on upstream comp.ts/main.ts to the library.
- Keep the public output self-contained, typed, and serializable; preserve checked quantities and semantics.
- Do not describe a checked syntax export as a verified compiler or proof certificate.
