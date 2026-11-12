const fs = require('fs');
const path = require('path');

const output = process.argv[2];
const events = process.argv[4];
const requestedArgs = JSON.parse(fs.readFileSync(path.join(__dirname, 'a4-cli-args.json'), 'utf8'));
const cli = path.join(__dirname, 'node_modules', 'json5', 'lib', 'cli.js');
const stdout = [];
const stderr = [];
let requestedExitCode;

let cliArgs = requestedArgs;
if (requestedArgs.length === 1 && requestedArgs[0] === '--probe-invalid-json') {
  const invalidInput = path.join(__dirname, 'a4-cli-invalid.json5');
  fs.writeFileSync(invalidInput, '{unquoted: }\n');
  cliArgs = [invalidInput];
} else if (requestedArgs.length === 1 && requestedArgs[0] === '--probe-large-validate') {
  cliArgs = ['--validate', path.join(__dirname, 'a4-cli-large.json5')];
}

function emit(type, data = {}) {
  fs.appendFileSync(events, JSON.stringify({type, ...data}) + '\n');
}

emit('ready', {version: process.version, bin: 'json5'});
const stdoutWrite = process.stdout.write.bind(process.stdout);
const stderrWrite = process.stderr.write.bind(process.stderr);
process.stdout.write = (chunk, encoding, callback) => {
  stdout.push(Buffer.isBuffer(chunk) ? chunk.toString() : String(chunk));
  if (typeof encoding === 'function') encoding();
  else if (typeof callback === 'function') callback();
  return true;
};
process.stderr.write = (chunk, encoding, callback) => {
  stderr.push(Buffer.isBuffer(chunk) ? chunk.toString() : String(chunk));
  if (typeof encoding === 'function') encoding();
  else if (typeof callback === 'function') callback();
  return true;
};
const originalExit = process.exit;
process.exit = (code = 0) => {
  requestedExitCode = Number(code) || 0;
  process.exitCode = requestedExitCode;
};
process.argv = ['node', cli, ...cliArgs];
process.once('beforeExit', () => {
  const result = {
    package: 'json5',
    version: require(path.join(__dirname, 'node_modules', 'json5', 'package.json')).version,
    bin: 'lib/cli.js',
    requestedArgs,
    args: process.argv.slice(2),
    stdout: stdout.join(''),
    stderr: stderr.join(''),
    exitCode: requestedExitCode ?? process.exitCode ?? 0,
  };
  fs.writeFileSync(output, JSON.stringify(result));
  emit('binResult', {version: result.version, exitCode: result.exitCode});
  process.exit = originalExit;
  process.stdout.write = stdoutWrite;
  process.stderr.write = stderrWrite;
});
try {
  require(cli);
} catch (error) {
  emit('exception', {message: error.stack || String(error)});
  process.exitCode = 1;
}
