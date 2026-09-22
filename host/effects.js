// Spliced into upstream's synchronous JS IO runtime. The worker bridges its
// synchronous effects to the upstream checker's asynchronous module loader.
function load(file) {
  const child = require('node:child_process').spawnSync(process.execPath,
    [process.env.BEND_FRONTEND_HOST, '--load', file], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (child.error || child.status !== 0) {
    return { $: 'Fail', error: child.error?.message || child.stderr.trim() || `Checker worker exited ${child.status}` };
  }
  return JSON.parse(child.stdout);
}

function write(file, program) {
  return require(process.env.BEND_FRONTEND_HOST).write(file, program);
}
