const fs = require('fs');
const path = require('path');
const {pathToFileURL} = require('url');

const output = process.argv[2];
const events = process.argv[4];
function emit(type, data = {}) {
  fs.appendFileSync(events, JSON.stringify({type, ...data}) + '\n');
}

(async () => {
  emit('ready', {version: process.version});
  const packageRoot = path.join(__dirname, 'node_modules', 'json5');
  const metadata = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
  const input = "{unquoted: 'works', trailing: [1, 2,],}";
  const original = require(packageRoot);
  const dynamicName = path.join(packageRoot, 'lib', 'index.js');
  const dynamic = require(dynamicName);
  const packageBundle = require(path.join(packageRoot, 'dist', 'index.js'));
  const esbuildBundle = require(path.join(__dirname, 'a4-json5-esbuild.cjs'));
  const imported = await import(pathToFileURL(path.join(packageRoot, 'dist', 'index.mjs')).href);
  const values = [original, dynamic, packageBundle, esbuildBundle, imported.default]
      .map((module) => module.parse(input));
  if (values.some((value) => value.unquoted !== 'works' || value.trailing.length !== 2)) {
    throw new Error('JSON5 implementations disagree');
  }
  const config = path.join(__dirname, 'a4-config.json5');
  fs.writeFileSync(config, original.stringify({version: metadata.version, enabled: true}));
  const persisted = original.parse(fs.readFileSync(config, 'utf8'));
  const result = {
    node: process.version,
    package: metadata.name,
    version: metadata.version,
    entry: metadata.main,
    bin: metadata.bin,
    source: values[0].unquoted,
    dynamic: values[1].unquoted,
    bundled: values[3].unquoted,
    esm: values[4].unquoted,
    configPrivate: config.startsWith(__dirname + path.sep),
    configVersion: persisted.version,
  };
  fs.writeFileSync(output, JSON.stringify(result));
  emit('packageResult', {
    package: metadata.name,
    version: metadata.version,
    esbuildMatches: values.every((value) => value.unquoted === values[3].unquoted),
    esbuildBundleBytes: fs.statSync(path.join(__dirname, 'a4-json5-esbuild.cjs')).size,
    packageTreeBytes: treeBytes(packageRoot),
  });
})().catch((error) => {
  emit('exception', {message: error.stack || String(error)});
  process.exitCode = 1;
});

function treeBytes(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).reduce((total, item) => {
    const itemPath = path.join(directory, item.name);
    return total + (item.isDirectory() ? treeBytes(itemPath) : fs.statSync(itemPath).size);
  }, 0);
}
