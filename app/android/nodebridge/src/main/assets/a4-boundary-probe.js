'use strict';

const fs = require('fs');
const path = require('path');
const tty = require('tty');

const outputPath = process.argv[2];
const eventsPath = process.argv[4];
const filesRoot = __dirname;
const action = fs.readFileSync(path.join(filesRoot, 'a4-boundary-action.txt'), 'utf8').trim();
const addonPath = path.join(filesRoot, 'a4-boundary-native-addon.node');
const childPath = path.join(filesRoot, 'a4-boundary-child.js');

function errorInfo(error) {
  return {
    name: error && error.name ? error.name : null,
    code: error && error.code ? error.code : null,
    message: String(error && error.message ? error.message : error).slice(0, 1200),
  };
}

function baseline() {
  const stdin = process.stdin;
  const stdout = process.stdout;
  const stderr = process.stderr;
  return {
    nodeVersion: process.version,
    nodeMobileVersion: process.versions.mobile || null,
    platform: process.platform,
    cwd: process.cwd(),
    path: process.env.PATH || null,
    stdin: {
      available: !!stdin,
      type: typeof stdin,
      readable: stdin ? !!stdin.readable : false,
      readableEnded: stdin ? !!stdin.readableEnded : null,
      isTTY: stdin ? !!stdin.isTTY : false,
      setRawMode: stdin ? typeof stdin.setRawMode : 'unavailable',
    },
    stdout: {available: !!stdout, isTTY: stdout ? !!stdout.isTTY : false},
    stderr: {available: !!stderr, isTTY: stderr ? !!stderr.isTTY : false},
    tty: {
      stdin: tty.isatty(0),
      stdout: tty.isatty(1),
      stderr: tty.isatty(2),
    },
  };
}

function requireChildProcess() {
  const attempts = [];
  for (const specifier of ['node:child_process', 'child_process']) {
    try {
      return {module: require(specifier), attempts};
    } catch (error) {
      attempts.push({specifier, ...errorInfo(error)});
    }
  }
  return {module: null, attempts};
}

function waitForChild(child, captureOutput = false, timeoutMs = 2500) {
  return new Promise((resolve) => {
    let settled = false;
    let stdout = '';
    let stderr = '';
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({...result, stdout: stdout.slice(0, 1000), stderr: stderr.slice(0, 1000)});
    };
    if (captureOutput && child.stdout) child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    if (captureOutput && child.stderr) child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.once('spawn', () => { child.__a4Spawned = true; });
    child.once('error', (error) => finish({spawned: false, error: errorInfo(error)}));
    child.once('exit', (code, signal) => finish({spawned: !!child.__a4Spawned, code, signal}));
    const timer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch (_) {}
      finish({spawned: !!child.__a4Spawned, timedOut: true});
    }, timeoutMs);
  });
}

async function observeStdin() {
  const stdin = process.stdin;
  if (!stdin || typeof stdin.on !== 'function') {
    return {available: false, receivedBytes: 0, receivedLines: [], reason: 'process.stdin is unavailable'};
  }
  let receivedBytes = 0;
  const receivedLines = [];
  const onData = (chunk) => {
    receivedBytes += Buffer.isBuffer(chunk) ? chunk.length : Buffer.byteLength(String(chunk));
  };
  const onLine = (line) => { if (receivedLines.length < 3) receivedLines.push(String(line).slice(0, 500)); };
  const onError = (error) => { receivedLines.push(`stdin-error:${errorInfo(error).message}`); };
  stdin.on('data', onData);
  stdin.on('error', onError);
  const readline = require('readline');
  const reader = readline.createInterface({input: stdin, terminal: false});
  reader.on('line', onLine);
  try { stdin.resume(); } catch (_) {}
  await new Promise((resolve) => setTimeout(resolve, 350));
  try { stdin.pause(); } catch (_) {}
  reader.close();
  stdin.removeListener('data', onData);
  stdin.removeListener('error', onError);
  return {available: true, receivedBytes, receivedLines, reason: receivedBytes === 0 ? 'no host input arrived during observation window' : null};
}

function mediaTools() {
  const names = ['ffmpeg', 'ffprobe', 'mpv'];
  const directories = [...new Set([...(process.env.PATH || '').split(':'), '/system/bin', '/system/xbin'])]
    .filter(Boolean);
  return Object.fromEntries(names.map((name) => {
    const candidates = directories.map((directory) => path.join(directory, name));
    const executable = candidates.find((candidate) => {
      try { fs.accessSync(candidate, fs.constants.X_OK); return true; } catch (_) { return false; }
    });
    return [name, {found: !!executable, executable: executable || null, candidates: candidates.slice(0, 20)}];
  }));
}

async function inspectMediaTools() {
  const tools = mediaTools();
  const loaded = requireChildProcess();
  const launch = {};
  for (const [name, tool] of Object.entries(tools)) {
    if (!tool.found) {
      launch[name] = {attempted: false, reason: 'executable not found on fixed paths or PATH'};
    } else if (!loaded.module) {
      launch[name] = {attempted: false, reason: 'child_process module unavailable'};
    } else {
      try {
        launch[name] = {
          attempted: true,
          ...await waitForChild(loaded.module.spawn(tool.executable, ['--version'], {
            stdio: ['ignore', 'pipe', 'pipe'],
          }), true, 3000),
        };
      } catch (error) {
        launch[name] = {attempted: true, thrown: errorInfo(error)};
      }
    }
  }
  return {tools, childProcessImports: loaded.attempts, launch};
}

async function main() {
  const result = {action, ...baseline()};
  switch (action) {
    case 'runtime':
      break;
    case 'child-process': {
      const loaded = requireChildProcess();
      result.childProcess = {available: !!loaded.module, importAttempts: loaded.attempts,
        spawnType: loaded.module ? typeof loaded.module.spawn : 'unavailable',
        forkType: loaded.module ? typeof loaded.module.fork : 'unavailable'};
      break;
    }
    case 'spawn': {
      const loaded = requireChildProcess();
      result.childProcessImports = loaded.attempts;
      if (!loaded.module) {
        result.spawn = {attempted: false, reason: 'child_process module unavailable'};
      } else {
        try {
          result.spawn = {
            systemShell: {
              attempted: true,
              ...await waitForChild(loaded.module.spawn('/system/bin/sh', ['-c', 'exit 0'], {stdio: 'ignore'})),
            },
            nodeFromAppData: {
              attempted: true,
              ...await waitForChild(loaded.module.spawn(process.execPath, [childPath], {stdio: 'ignore'})),
            },
          };
        } catch (error) {
          result.spawn = {attempted: true, thrown: errorInfo(error)};
        }
      }
      break;
    }
    case 'fork': {
      const loaded = requireChildProcess();
      result.childProcessImports = loaded.attempts;
      if (!loaded.module) {
        result.fork = {attempted: false, reason: 'child_process module unavailable'};
      } else {
        try {
          const child = loaded.module.fork(childPath, [], {execArgv: [], silent: true});
          let message = null;
          child.once('message', (value) => { message = String(value).slice(0, 500); });
          result.fork = {attempted: true, message, ...await waitForChild(child)};
        } catch (error) {
          result.fork = {attempted: true, thrown: errorInfo(error)};
        }
      }
      break;
    }
    case 'media-tools': {
      result.mediaTools = await inspectMediaTools();
      break;
    }
    case 'stdio': {
      const stdin = await observeStdin();
      result.stdioMcp = {
        stdin,
        stdoutWrite: typeof process.stdout.write,
        mcpInitializeLineObserved: stdin.receivedLines.some((line) => {
          try { return JSON.parse(line).method === 'initialize'; } catch (_) { return false; }
        }),
        reason: stdin.receivedBytes === 0 ? 'no MCP request reached fd 0 from the Android Node bridge' : null,
      };
      break;
    }
    case 'tui':
      result.tui = {
        stdinTTY: !!(process.stdin && process.stdin.isTTY),
        stdoutTTY: !!(process.stdout && process.stdout.isTTY),
        canSetRawMode: !!(process.stdin && typeof process.stdin.setRawMode === 'function'),
        canUseInteractiveTerminal: !!(process.stdin && process.stdin.isTTY
          && typeof process.stdin.setRawMode === 'function'),
      };
      break;
    case 'native-addon':
      try {
        const addon = require(addonPath);
        result.nativeAddon = {
          loaded: true,
          exportType: typeof addon.getNapiVersion,
          napiVersion: addon.getNapiVersion(),
          sourcePath: addonPath,
        };
      } catch (error) {
        result.nativeAddon = {loaded: false, sourcePath: addonPath, error: errorInfo(error)};
      }
      break;
    default:
      throw new Error(`Unsupported fixed boundary action: ${action}`);
  }
  fs.writeFileSync(outputPath, JSON.stringify(result));
  fs.appendFileSync(eventsPath, JSON.stringify({type: 'boundaryResult', action, resultFile: 'a3-result.json'}) + '\n');
}

main().catch((error) => {
  const result = {action, nodeVersion: process.version, error: errorInfo(error)};
  try { fs.writeFileSync(outputPath, JSON.stringify(result)); } catch (_) {}
  try { fs.appendFileSync(eventsPath, JSON.stringify({type: 'boundaryResult', action, failed: true, resultFile: 'a3-result.json'}) + '\n'); } catch (_) {}
});
