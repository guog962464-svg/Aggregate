'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const filesRoot = __dirname;
const outputPath = process.argv[2];
const eventsPath = process.argv[4];
const action = fs.readFileSync(path.join(filesRoot, 'a4-ncm-action.txt'), 'utf8').trim();
const manifest = JSON.parse(fs.readFileSync(path.join(filesRoot, 'a4-ncm-manifest.json'), 'utf8'));
const npmManifest = JSON.parse(fs.readFileSync(path.join(filesRoot, 'a4-npm-manifest.json'), 'utf8'));
const npmCliPath = path.join(filesRoot, 'a4-npm-cli', 'bin', 'npm-cli.js');
const packageRoot = path.join(filesRoot, 'a4-ncm-workspace', 'install');
const packageJsonPath = path.join(packageRoot, 'node_modules', '@music163', 'ncm-cli', 'package.json');
const cliPath = path.join(packageRoot, 'node_modules', '@music163', 'ncm-cli', 'dist', 'index.js');
const cacheRoot = path.join(filesRoot, 'a4-ncm-cache');
const homeRoot = path.join(filesRoot, 'a4-ncm-home');
const allowedActions = new Set([
  'install', 'version', 'help', 'configure', 'login-help', 'search', 'tui', 'play',
]);
const exitSignal = {};

const stdout = [];
const stderr = [];
let outputBytes = 0;
let explicitExitCode;
let commandError;
let timedOut = false;
let finalized = false;

function emit(type, payload = {}) {
  fs.appendFileSync(eventsPath, JSON.stringify({type, ...payload}) + '\n');
}

function info(error) {
  return {
    name: error && error.name ? error.name : null,
    code: error && error.code ? error.code : null,
    message: String(error && error.message ? error.message : error).slice(0, 1200),
  };
}

function capture(target, chunk, encoding, callback) {
  const value = Buffer.isBuffer(chunk) ? chunk.toString() : String(chunk);
  if (outputBytes < 24576) {
    const remaining = 24576 - outputBytes;
    target.push(value.slice(0, remaining));
    outputBytes += Math.min(value.length, remaining);
  }
  if (typeof encoding === 'function') encoding();
  else if (typeof callback === 'function') callback();
  return true;
}

function readInstallSummary() {
  const lockPath = path.join(packageRoot, 'package-lock.json');
  let lock = null;
  try { lock = JSON.parse(fs.readFileSync(lockPath, 'utf8')); } catch (_) {}
  const packages = lock && lock.packages ? lock.packages : {};
  const directNames = [
    'node_modules/@music163/ncm-cli',
    'node_modules/ffprobe-static',
    'node_modules/fluent-ffmpeg',
    'node_modules/commander',
    'node_modules/@clack/prompts',
  ];
  let installedManifest = null;
  try { installedManifest = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8')); } catch (_) {}
  let lockSha256 = null;
  try { lockSha256 = crypto.createHash('sha256').update(fs.readFileSync(lockPath)).digest('hex'); } catch (_) {}
  return {
    packageRoot,
    cliExists: fs.isFile ? fs.isFile(cliPath) : fs.existsSync(cliPath),
    installedPackageVersion: installedManifest ? installedManifest.version : null,
    lockfileVersion: lock ? lock.lockfileVersion : null,
    lockSha256,
    expectedLockSha256: manifest.lockSha256,
    lockPackageCount: Object.keys(packages).length,
    dependencyVersions: Object.fromEntries(directNames.map((name) => [
      name.replace(/^node_modules\//, ''), packages[name] ? packages[name].version : null,
    ])),
  };
}

function cliArguments() {
  switch (action) {
    case 'version': return ['--version'];
    case 'help': return ['--help'];
    case 'configure': return ['configure'];
    case 'login-help': return ['login', '--help'];
    case 'search': return ['search', 'song', '--keyword', '林俊杰'];
    case 'tui': return ['tui'];
    case 'play': {
      const inputPath = path.join(filesRoot, 'a4-ncm-play-args.json');
      const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
      if (!/^[A-Za-z0-9_-]{1,160}$/.test(input.encryptedId)
          || !/^\d{1,24}$/.test(input.originalId)) {
        throw new Error('play arguments failed fixed ID validation');
      }
      return ['play', '--song', '--encrypted-id', input.encryptedId,
        '--original-id', input.originalId];
    }
    default: throw new Error(`Unsupported fixed ncm action: ${action}`);
  }
}

function finalize() {
  if (finalized) return;
  finalized = true;
  const install = readInstallSummary();
  const result = {
    action,
    nodeVersion: process.version,
    nodeMobileVersion: process.versions.mobile || null,
    platform: process.platform,
    cwd: process.cwd(),
    stdinTTY: !!(process.stdin && process.stdin.isTTY),
    stdoutTTY: !!(process.stdout && process.stdout.isTTY),
    npmVersion: npmManifest.version,
    packageVersion: manifest.version,
    lockSha256: manifest.lockSha256,
    exitCode: explicitExitCode ?? process.exitCode ?? (commandError ? 1 : 0),
    timedOut,
    stdout: stdout.join('').slice(-6000),
    stderr: stderr.join('').slice(-6000),
    error: commandError ? String(commandError.stack || commandError).slice(0, 1800) : null,
    install,
  };
  fs.writeFileSync(outputPath, JSON.stringify(result));
  emit('ncmResult', {action, exitCode: result.exitCode, timedOut, resultFile: 'a3-result.json'});
  process.exitCode = 0;
}

function reportFailure(error) {
  if (error === exitSignal) return;
  commandError = error;
  process.exitCode = 1;
}

async function main() {
  if (!allowedActions.has(action)) throw new Error(`Action is not allowlisted: ${action}`);
  fs.mkdirSync(homeRoot, {recursive: true});
  fs.mkdirSync(cacheRoot, {recursive: true});
  process.env.HOME = homeRoot;
  process.env.npm_config_userconfig = path.join(homeRoot, '.npmrc');
  process.env.npm_config_globalconfig = path.join(homeRoot, 'global.npmrc');
  process.env.npm_config_cache = cacheRoot;
  process.env.npm_config_update_notifier = 'false';
  process.chdir(filesRoot);
  process.stdout.write = (chunk, encoding, callback) => capture(stdout, chunk, encoding, callback);
  process.stderr.write = (chunk, encoding, callback) => capture(stderr, chunk, encoding, callback);
  process.exit = (code = 0) => {
    explicitExitCode = Number(code) || 0;
    process.exitCode = explicitExitCode;
    throw exitSignal;
  };
  process.on('uncaughtException', (error) => {
    if (error !== exitSignal) reportFailure(error);
  });
  process.on('unhandledRejection', reportFailure);
  process.once('beforeExit', finalize);

  let entryPath;
  if (action === 'install') {
    if (!fs.existsSync(npmCliPath)) throw new Error('Pinned npm CLI asset is missing');
    process.argv = [process.execPath, npmCliPath, 'ci', '--prefix', packageRoot,
      '--cache', cacheRoot, '--registry=https://registry.npmjs.org/',
      '--no-audit', '--no-fund', '--no-progress', '--loglevel=notice', '--ignore-scripts'];
    entryPath = npmCliPath;
    emit('ncmStarted', {action, packageVersion: manifest.version, lockSha256: manifest.lockSha256});
  } else {
    if (!fs.existsSync(cliPath)) throw new Error('ncm-cli is not installed; run fixed install action first');
    process.chdir(packageRoot);
    process.argv = [process.execPath, cliPath, ...cliArguments()];
    entryPath = cliPath;
    emit('ncmStarted', {action, packageVersion: manifest.version});
  }

  try {
    const result = require(entryPath);
    if (result && typeof result.then === 'function') result.catch(reportFailure);
  } catch (error) {
    if (error !== exitSignal) reportFailure(error);
  }
}

main().catch(reportFailure);
