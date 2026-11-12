#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
version="${2:-2.2.3}"
case "$version" in
  2.2.2)
    expected="86f16f0b61deae8046bf4eef42c24deab0e9832e7d20a4aaee5620d726c86a39"
    supported_versions='{"2.2.2":"86f16f0b61deae8046bf4eef42c24deab0e9832e7d20a4aaee5620d726c86a39","2.2.3":"08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b"}'
    url="https://registry.npmjs.org/json5/-/json5-2.2.2.tgz"
    default_archive="${TMPDIR:-/tmp}/json5-2.2.2.tgz"
    ;;
  2.2.3)
    expected="08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b"
    supported_versions='{"2.2.2":"86f16f0b61deae8046bf4eef42c24deab0e9832e7d20a4aaee5620d726c86a39","2.2.3":"08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b"}'
    url="https://registry.npmjs.org/json5/-/json5-2.2.3.tgz"
    default_archive="${TMPDIR:-/tmp}/json5-2.2.3.tgz"
    ;;
  *)
    echo "Unsupported pinned JSON5 version: $version" >&2
    exit 1
    ;;
esac
archive="${1:-$default_archive}"
esbuild_version="0.25.12"
target="$probe_root/../nodebridge/src/main/assets/a4-json5"
assets="$(cd "$target/.." && pwd)"

if [[ ! -f "$archive" ]]; then
  curl -fL --retry 2 -o "$archive" "$url"
fi
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "JSON5 $version tarball SHA-256 mismatch: $actual" >&2
  exit 1
fi
tar -tzf "$archive" >/dev/null
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -xzf "$archive" -C "$staging" package/package.json package/LICENSE.md package/lib package/dist
node -e 'const p=require(process.argv[1]); if(p.name!=="json5"||p.version!==process.argv[2]||p.main!=="lib/index.js"||p.bin!=="lib/cli.js") process.exit(1)' "$staging/package/package.json" "$version"
rm -rf "$target"
mkdir -p "$target"
cp -R "$staging/package/." "$target/"
rm -f "$assets/a4-json5-esbuild.cjs"
npm exec --yes --package="esbuild@$esbuild_version" -- esbuild \
  "$target/lib/index.js" --bundle --platform=node --format=cjs \
  --outfile="$assets/a4-json5-esbuild.cjs" >/dev/null
cat > "$assets/a4-json5-manifest.json" <<EOF
{"schemaVersion":1,"packageId":"json5","version":"$version","tarballSha256":"$expected","supportedVersions":$supported_versions,"entrypoints":{"json5.bin":"lib/cli.js"}}
EOF
echo "Prepared JSON5 $version and esbuild $esbuild_version assets for the Debug A4 probe."
