#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
archive="${1:-${TMPDIR:-/tmp}/json5-2.2.3.tgz}"
expected="08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b"
url="https://registry.npmjs.org/json5/-/json5-2.2.3.tgz"
target="$probe_root/../nodebridge/src/main/assets/a4-json5"

if [[ ! -f "$archive" ]]; then
  curl -fL --retry 2 -o "$archive" "$url"
fi
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "JSON5 2.2.3 tarball SHA-256 mismatch: $actual" >&2
  exit 1
fi
tar -tzf "$archive" >/dev/null
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -xzf "$archive" -C "$staging" package/package.json package/LICENSE.md package/lib package/dist
node -e 'const p=require(process.argv[1]); if(p.name!=="json5"||p.version!=="2.2.3"||p.main!=="lib/index.js"||p.bin!=="lib/cli.js") process.exit(1)' "$staging/package/package.json"
rm -rf "$target"
mkdir -p "$target"
cp -R "$staging/package/." "$target/"
echo "Prepared pinned JSON5 2.2.3 source and distribution assets for the Debug A4 probe."
