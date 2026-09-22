import path from 'node:path';
import ts from 'typescript';

const config = ts.readConfigFile('tsconfig.json', ts.sys.readFile);
if (config.error) throw new Error(ts.flattenDiagnosticMessageText(config.error.messageText, '\n'));
const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, process.cwd());
const program = ts.createProgram(parsed.fileNames, parsed.options);
const diagnostics = [...parsed.errors, ...ts.getPreEmitDiagnostics(program)];
// The unmodified pinned upstream has these two narrowing errors. Keep every
// other diagnostic fatal, including new errors in upstream code.
const known = new Map([
  [2125, "Property 'k' does not exist on type 'LTerm'."],
  [3828, "Property 'v' does not exist on type 'TLD'."],
]);
const errors = diagnostics.filter(d => {
  if (!d.file || d.start === undefined || d.code !== 2339
    || path.resolve(d.file.fileName) !== path.resolve('vendor/bend/bend2/bend.ts')) return true;
  const line = d.file.getLineAndCharacterOfPosition(d.start).line + 1;
  return ts.flattenDiagnosticMessageText(d.messageText, '\n').split('\n')[0] !== known.get(line);
});
if (errors.length) {
  console.error(ts.formatDiagnosticsWithColorAndContext(errors, {
    getCanonicalFileName: f => f, getCurrentDirectory: ts.sys.getCurrentDirectory, getNewLine: () => '\n',
  }));
  process.exitCode = 1;
} else {
  console.log(`Typecheck passed (${diagnostics.length - errors.length} known upstream diagnostics excluded).`);
}
