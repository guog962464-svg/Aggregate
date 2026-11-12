#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
assets="$(cd "$probe_root/../nodebridge/src/main/assets" && pwd)"
version="12.2.2"
archive="${1:-${TMPDIR:-/tmp}/npm-$version.tgz}"
expected_integrity="KglgbZyacf7jH+FHuNRqVuCzQi8VhI2a7J87Ix43FsPTuZoGWmIXXGdZtBUOA79vwL+IJREqURVzupA7PsQTcA=="
url="https://registry.npmjs.org/npm/-/npm-$version.tgz"

if [[ ! -f "$archive" ]]; then
  curl -fL --retry 2 -o "$archive" "$url"
fi
actual_integrity="$(openssl dgst -sha512 -binary "$archive" | openssl base64 -A)"
if [[ "$actual_integrity" != "$expected_integrity" ]]; then
  echo "npm $version tarball SHA-512 mismatch" >&2
  exit 1
fi
tar -tzf "$archive" >/dev/null

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -xzf "$archive" -C "$staging" \
  package/bin package/lib package/node_modules package/package.json package/LICENSE
node -e 'const p=require(process.argv[1]); if(p.name!=="npm"||p.version!==process.argv[2]||!p.engines.node.includes("24.15.0")) process.exit(1)' \
  "$staging/package/package.json" "$version"

target="$assets/a4-npm-cli"
rm -rf "$target"
mkdir -p "$target"
cp -R "$staging/package/." "$target/"
generated="$assets/a4-npm-generated"
rm -rf "$generated"
mkdir -p "$generated"
cp -R "$target/node_modules/@sigstore/protobuf-specs/dist/__generated__/." "$generated/"
cat > "$assets/a4-npm-manifest.json" <<EOF
{"schemaVersion":1,"packageId":"npm","version":"$version","tarballIntegrity":"sha512-$expected_integrity","entrypoint":"bin/npm-cli.js"}
EOF

fixture="$staging/fixture/package"
mkdir -p "$fixture"
cp "$probe_root/fixtures/a4-npm-install-script/package.json" "$fixture/package.json"
cp "$probe_root/fixtures/a4-npm-install-script/install.js" "$fixture/install.js"
tar -czf "$assets/a4-npm-install-script.tgz" -C "$staging/fixture" package

echo "Prepared pinned npm $version CLI and local lifecycle-script fixture for the Debug A4.4 probe."
