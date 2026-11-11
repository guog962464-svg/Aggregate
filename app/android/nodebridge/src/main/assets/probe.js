const fs = require('fs');
const http = require('http');

const output = process.argv[2];
const delayMs = Number(process.argv[3] || 0);
const events = process.argv[4];
const shouldFail = process.argv[5] === '1';
function emit(type, data = {}) {
  fs.appendFileSync(events, JSON.stringify({ type, ...data }) + '\n');
}
process.on('uncaughtException', (error) => {
  emit('exception', { message: error.message });
  process.exitCode = 1;
});
const originalLog = console.log;
console.log = (...items) => {
  emit('console', { message: items.join(' ') });
  originalLog(...items);
};
emit('ready', { version: process.version });
if (shouldFail) {
  throw new Error('a3-probe-failure');
}
const server = http.createServer((request, response) => {
  response.end('network-ok');
});
setTimeout(() => server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  http.get(`http://127.0.0.1:${port}/`, (response) => {
    let body = '';
    response.on('data', (chunk) => body += chunk);
    response.on('end', () => {
      emit('network', { body });
      fs.writeFileSync(output, JSON.stringify({
        version: process.version,
        file: 'ok',
        network: body,
      }));
      emit('fileWrite', { bytes: fs.statSync(output).size });
      fs.readFileSync(output, 'utf8');
      emit('fileRead');
      console.log('A3_NODE_PROBE_READY');
      server.close();
    });
  }).on('error', (error) => {
    console.error(error);
    process.exitCode = 1;
    server.close();
  });
}), delayMs);
