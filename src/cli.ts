#!/usr/bin/env bun
import { mkdirSync, existsSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { Cli, z } from 'incur';
import { check, type CheckedProgram } from './frontend.ts';

const args = z.object({ file: z.string().describe('Bend source or PROOF.bend') });
const output = z.string().describe('Output file');

function write(program: CheckedProgram, output: string, content: string) {
  const file = path.resolve(output);
  const destination = existsSync(file) ? realpathSync(file) : file;
  const target = existsSync(file) ? statSync(file) : undefined;
  if (program.inputs.some(input => {
    const source = statSync(input, { throwIfNoEntry: false });
    return input === destination || (source && (realpathSync(input) === destination
      || (source.dev === target?.dev && source.ino === target.ino)));
  })) {
    throw new Error('Output would overwrite a program input');
  }
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, content);
  return { output: file, bytes: Buffer.byteLength(content) };
}

const cli = Cli.create('bend-frontend', {
  version: '0.1.0',
  description: 'Bend frontend: check source and export checked core',
})
  .command('check', {
    description: 'Check with the pinned upstream frontend; reject holes and open laws',
    args,
    async run({ args }) {
      const { entry, upstream, declarations } = await check(args.file);
      return { file: entry, upstream: upstream.commit, declarations: declarations.length,
        unsafeDeclarations: declarations.filter(d => d.kind === 'Def' && d.unsafe).map(d => d.name),
        foreignDeclarations: declarations.filter(d => d.kind === 'Def' && d.foreign.length).map(d => d.name) };
    },
  })
  .command('export', {
    description: 'Export checked core, types, quantities, templates and foreign declarations as JSON',
    args,
    options: z.object({ output }),
    alias: { output: 'o' },
    async run({ args, options }) {
      const program = await check(args.file);
      return write(program, options.output, JSON.stringify(program, null, 2) + '\n');
    },
  });

export default cli;
if (import.meta.main) {
  await cli.serve();
  // Bun otherwise interprets the CLI's exported fetch method as a web server.
  process.exit(process.exitCode ?? 0);
}
