const fs = require('fs');
const path = require('path');

const output = process.argv[2];
const events = process.argv[4];
const cliArgs = JSON.parse(fs.readFileSync(path.join(__dirname, 'a4-cli-args.json'), 'utf8'));
const cli = path.join(__dirname, 'node_modules', 'json5', 'lib', 'cli.js');
const stdout = [];
const stderr = [];
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
process.argv = ['node', cli, ...cliArgs];
try {
  require(cli);
  const result = {
    package: 'json5',
    version: require(path.join(__dirname, 'node_modules', 'json5', 'package.json')).version,
    bin: 'lib/cli.js',
    args: process.argv.slice(2),
    stdout: stdout.join(''),
    stderr: stderr.join(''),
    exitCode: process.exitCode || 0,
  };
  fs.writeFileSync(output, JSON.stringify(result));
  emit('binResult', {version: result.version, exitCode: result.exitCode});
} catch (error) {
  emit('exception', {message: error.stack || String(error)});
  process.exitCode = 1;
} finally {
  process.stdout.write = stdoutWrite;
  process.stderr.write = stderrWrite;
}
