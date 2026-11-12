'use strict';

const fs = require('fs');
const path = require('path');

const outputPath = process.argv[2];
const eventsPath = process.argv[4];
const filesRoot = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(filesRoot, 'a4-npm-manifest.json'), 'utf8'));
const action = fs.readFileSync(path.join(filesRoot, 'a4-npm-action.txt'), 'utf8').trim();
const cliPath = path.join(filesRoot, 'a4-npm-cli', 'bin', 'npm-cli.js');
const cacheRoot = path.join(filesRoot, 'a4-npm-cache');
const homeRoot = path.join(filesRoot, 'a4-npm-home');
const baseArgs = [
  '--cache', cacheRoot,
  '--registry=https://registry.npmjs.org/',
  '--no-audit', '--no-fund', '--no-progress', '--loglevel=notice',
];
const roots = {
  install: path.join(filesRoot, 'a4-npm-workspace', 'install'),
  offline: path.join(filesRoot, 'a4-npm-workspace', 'offline'),
  upgrade: path.join(filesRoot, 'a4-npm-workspace', 'upgrade'),
  scriptIgnored: path.join(filesRoot, 'a4-npm-workspace', 'script-ignored'),
  scriptDefault: path.join(filesRoot, 'a4-npm-workspace', 'script-default'),
  integrityBad: path.join(filesRoot, 'a4-npm-workspace', 'integrity-bad'),
  scriptAllowed: path.join(filesRoot, 'a4-npm-global', 'script-allowed'),
};
const fixture = path.join(filesRoot, 'a4-npm-install-script.tgz');
const npmArgs = (() => {
  switch (action) {
    case 'version':
      return ['--version'];
    case 'install':
      return ['install', '--prefix', roots.install, ...baseArgs, '--ignore-scripts', 'supports-color@7.2.0'];
    case 'offline':
      return ['install', '--prefix', roots.offline, ...baseArgs, '--ignore-scripts', '--offline', 'supports-color@7.2.0'];
    case 'cache-verify':
      return ['cache', 'verify', '--cache', cacheRoot];
    case 'script-ignored':
      return ['install', '--prefix', roots.scriptIgnored, ...baseArgs, '--ignore-scripts', fixture];
    case 'script-default':
      return ['install', '--prefix', roots.scriptDefault, ...baseArgs, '--foreground-scripts', fixture];
    case 'script-allowed':
      return ['install', '--global', '--prefix', roots.scriptAllowed, ...baseArgs,
        `--allow-scripts=file:${fixture}`, '--foreground-scripts', fixture];
    case 'integrity-bad':
      return ['ci', '--prefix', roots.integrityBad, ...baseArgs, '--ignore-scripts'];
    case 'upgrade-old':
      return ['install', '--prefix', roots.upgrade, ...baseArgs, '--ignore-scripts', 'json5@2.2.2'];
    case 'upgrade-new':
      return ['install', '--prefix', roots.upgrade, ...baseArgs, '--ignore-scripts', 'json5@2.2.3'];
    case 'uninstall':
      return ['uninstall', '--prefix', roots.upgrade, ...baseArgs, 'json5'];
    default:
      throw new Error(`Unsupported fixed npm action: ${action}`);
  }
})();

const stdout = [];
const stderr = [];
let outputBytes = 0;
let explicitExitCode;
let commandError;
let finalized = false;

function emit(type, payload = {}) {
  fs.appendFileSync(eventsPath, JSON.stringify({type, ...payload}) + '\n');
}

function capture(target, chunk, encoding, callback) {
  const value = Buffer.isBuffer(chunk) ? chunk.toString() : String(chunk);
  if (outputBytes < 16384) {
    const remaining = 16384 - outputBytes;
    target.push(value.slice(0, remaining));
    outputBytes += Math.min(value.length, remaining);
  }
  if (typeof encoding === 'function') encoding();
  else if (typeof callback === 'function') callback();
  return true;
}

function packageState(root) {
  const lockPath = path.join(root, 'package-lock.json');
  let lockPackages = [];
  if (fs.existsSync(lockPath)) {
    try {
      const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
      lockPackages = Object.entries(lock.packages || {}).map(([name, value]) => ({
        name,
        version: value.version || null,
        resolved: value.resolved || null,
        integrity: value.integrity || null,
      }));
    } catch (error) {
      lockPackages = [{error: String(error)}];
    }
  }
  return lockPackages;
}

function packageLoad(root) {
  try {
    const loaded = require(path.join(root, 'node_modules', 'supports-color'));
    return {loaded: true, exportType: typeof loaded};
  } catch (error) {
    return {loaded: false, error: String(error).slice(0, 500)};
  }
}

function writeBadIntegrityFixture() {
  const root = roots.integrityBad;
  fs.mkdirSync(root, {recursive: true});
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({
    name: 'aggregate-a4-integrity-fixture',
    version: '1.0.0',
    private: true,
    dependencies: {json5: '2.2.3'},
  }, null, 2));
  fs.writeFileSync(path.join(root, 'package-lock.json'), JSON.stringify({
    name: 'aggregate-a4-integrity-fixture',
    version: '1.0.0',
    lockfileVersion: 3,
    requires: true,
    packages: {
      '': {name: 'aggregate-a4-integrity-fixture', version: '1.0.0',
        dependencies: {json5: '2.2.3'}},
      'node_modules/json5': {
        version: '2.2.3',
        resolved: 'https://registry.npmjs.org/json5/-/json5-2.2.3.tgz',
        integrity: `sha512-${Buffer.alloc(64).toString('base64')}`,
      },
    },
  }, null, 2));
}

function directoryBytes(root) {
  if (!fs.existsSync(root)) return 0;
  const entries = fs.readdirSync(root, {withFileTypes: true});
  return entries.reduce((total, entry) => {
    const child = path.join(root, entry.name);
    if (entry.isSymbolicLink()) return total;
    return total + (entry.isDirectory() ? directoryBytes(child) : fs.statSync(child).size);
  }, 0);
}

function finalize() {
  if (finalized) return;
  finalized = true;
  const npmExitCode = explicitExitCode ?? process.exitCode ?? (commandError ? 1 : 0);
  const result = {
    action,
    nodeVersion: process.version,
    npmVersion: manifest.version,
    tarballIntegrity: manifest.tarballIntegrity,
    npmExitCode,
    stdout: stdout.join('').slice(-1000),
    stderr: stderr.join('').slice(-1000),
    error: commandError ? String(commandError.stack || commandError).slice(0, 1000) : null,
    installLockPackages: packageState(roots.install),
    installPackageLoad: packageLoad(roots.install),
    offlineLockPackages: packageState(roots.offline),
    offlinePackageLoad: packageLoad(roots.offline),
    upgradeLockPackages: packageState(roots.upgrade),
    integrityLockPackages: packageState(roots.integrityBad),
    integrityPackageExists: fs.existsSync(path.join(roots.integrityBad, 'node_modules', 'json5')),
    scriptIgnoredMarker: fs.existsSync(path.join(roots.scriptIgnored,
      'node_modules', 'aggregate-a4-install-script-fixture', 'install-marker.json')),
    scriptDefaultMarker: fs.existsSync(path.join(roots.scriptDefault,
      'node_modules', 'aggregate-a4-install-script-fixture', 'install-marker.json')),
    scriptAllowedMarker: fs.existsSync(path.join(roots.scriptAllowed,
      'node_modules', 'aggregate-a4-install-script-fixture', 'install-marker.json')),
    cacheBytes: directoryBytes(cacheRoot),
  };
  fs.writeFileSync(outputPath, JSON.stringify(result));
  emit('npmResult', {action, npmExitCode, cacheBytes: result.cacheBytes, resultFile: 'a3-result.json'});
  // The npm command's status is carried in the JSON result; keep the Node probe alive to report it.
  process.exitCode = 0;
}

fs.mkdirSync(homeRoot, {recursive: true});
fs.mkdirSync(cacheRoot, {recursive: true});
process.chdir(filesRoot);
process.env.HOME = homeRoot;
process.env.npm_config_userconfig = path.join(homeRoot, '.npmrc');
process.env.npm_config_globalconfig = path.join(homeRoot, 'global.npmrc');
process.env.npm_config_cache = cacheRoot;
process.env.npm_config_update_notifier = 'false';
process.stdout.write = (chunk, encoding, callback) => capture(stdout, chunk, encoding, callback);
process.stderr.write = (chunk, encoding, callback) => capture(stderr, chunk, encoding, callback);
process.exit = (code = 0) => {
  explicitExitCode = Number(code) || 0;
  process.exitCode = explicitExitCode;
};
process.once('beforeExit', finalize);
emit('npmStarted', {action, version: manifest.version});
process.argv = [process.execPath, cliPath, ...npmArgs];

try {
  if (action === 'integrity-bad' && !fs.existsSync(path.join(roots.integrityBad, 'package-lock.json'))) {
    writeBadIntegrityFixture();
  }
  const result = require(cliPath);
  if (result && typeof result.catch === 'function') {
    result.catch((error) => {
      commandError = error;
      process.exitCode = 1;
    });
  }
} catch (error) {
  commandError = error;
  process.exitCode = 1;
}
