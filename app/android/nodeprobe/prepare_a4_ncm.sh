#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
fixture="$probe_root/fixtures/a4-ncm"
assets="$(cd "$probe_root/../nodebridge/src/main/assets" && pwd)"
expected_lock_sha256="64b01d9e8f90ea92086d4e8950e891a630b85922528b50224d5c2522e2296f7a"
if [[ ! -f "$assets/a4-npm-cli/bin/npm-cli.js" || ! -f "$assets/a4-npm-manifest.json" ]]; then
  echo "Prepare the pinned A4.4 npm runtime before preparing the A4.6 fixture" >&2
  exit 1
fi

if [[ ! -f "$fixture/package.json" || ! -f "$fixture/package-lock.json" ]]; then
  echo "Pinned A4.6 package and lockfile are missing" >&2
  exit 1
fi

actual_lock_sha256="$(shasum -a 256 "$fixture/package-lock.json" | awk '{print $1}')"
if [[ "$actual_lock_sha256" != "$expected_lock_sha256" ]]; then
  echo "A4.6 lockfile SHA-256 mismatch" >&2
  exit 1
fi

node -e '
const fs = require("fs");
const packageJson = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const lock = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (packageJson.name !== "aggregate-a4-ncm-cli-fixture"
    || packageJson.dependencies?.["@music163/ncm-cli"] !== "0.1.7"
    || lock.lockfileVersion !== 3
    || lock.packages?.["node_modules/@music163/ncm-cli"]?.version !== "0.1.7"
    || lock.packages?.["node_modules/ffprobe-static"]?.version !== "3.1.0") {
  process.exit(1);
}
' "$fixture/package.json" "$fixture/package-lock.json"

cp "$fixture/package.json" "$assets/a4-ncm-package.json"
cp "$fixture/package-lock.json" "$assets/a4-ncm-package-lock.json"
cat > "$assets/a4-ncm-manifest.json" <<EOF
{"schemaVersion":1,"packageId":"@music163/ncm-cli","version":"0.1.7","lockfileVersion":3,"lockSha256":"$actual_lock_sha256"}
EOF

echo "Prepared pinned @music163/ncm-cli 0.1.7 lockfile for the A4.6 Debug device probe."
