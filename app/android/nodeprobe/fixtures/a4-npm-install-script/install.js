'use strict';

const fs = require('fs');
const {spawnSync} = require('child_process');

const child = spawnSync('node', ['--version'], {encoding: 'utf8'});
if (child.error || child.status !== 0) {
  throw child.error || new Error(`node child exited with status ${child.status}: ${child.stderr}`);
}
const nodeVersion = child.stdout.trim();
if (nodeVersion !== process.version) {
  throw new Error(`node command resolved ${nodeVersion}, expected ${process.version}`);
}
fs.writeFileSync('install-marker.json', JSON.stringify({
  installed: true,
  nodeVersion,
  childStatus: child.status,
  childSignal: child.signal,
}));
