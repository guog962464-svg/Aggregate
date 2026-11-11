const fs = require('fs');
const http = require('http');

const output = process.argv[2];
const server = http.createServer((request, response) => {
  response.end('network-ok');
});
server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  http.get(`http://127.0.0.1:${port}/`, (response) => {
    let body = '';
    response.on('data', (chunk) => body += chunk);
    response.on('end', () => {
      fs.writeFileSync(output, JSON.stringify({
        version: process.version,
        file: 'ok',
        network: body,
      }));
      console.log('A3_NODE_PROBE_READY');
      server.close();
    });
  }).on('error', (error) => {
    console.error(error);
    process.exitCode = 1;
    server.close();
  });
});
