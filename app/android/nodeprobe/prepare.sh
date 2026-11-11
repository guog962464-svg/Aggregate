#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
archive="${1:-${TMPDIR:-/tmp}/aggregate-nodejs-mobile-v18.20.4-android.zip}"
ndk_root="${2:-${ANDROID_NDK_HOME:-}}"
expected="bd7321eaa1a7602fbe0bb87302df2d79d87835cf4363fbdd17c350dbb485c2af"
url="https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v18.20.4/nodejs-mobile-v18.20.4-android.zip"

if [[ -z "$ndk_root" ]]; then
  sdk_root="$(sed -n 's/^sdk.dir=//p' "$probe_root/../local.properties")"
  ndk_root="$sdk_root/ndk/28.2.13676358"
fi
cpp_runtime="$(find "$ndk_root/toolchains/llvm/prebuilt" -path '*/aarch64-linux-android/libc++_shared.so' -print -quit)"
if [[ ! -f "$cpp_runtime" ]]; then
  echo "NDK arm64 libc++_shared.so not found under $ndk_root" >&2
  exit 1
fi

if [[ ! -f "$archive" ]]; then
  curl -fL --retry 2 -o "$archive" "$url"
fi
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "A3 archive SHA-256 mismatch: $actual" >&2
  exit 1
fi
unzip -tq "$archive" >/dev/null
mkdir -p "$probe_root/src/main/jniLibs/arm64-v8a" "$probe_root/vendor"
unzip -p "$archive" bin/arm64-v8a/libnode.so > "$probe_root/src/main/jniLibs/arm64-v8a/libnode.so"
cp "$cpp_runtime" "$probe_root/src/main/jniLibs/arm64-v8a/libc++_shared.so"
unzip -oq "$archive" 'include/node/*' -d "$probe_root/vendor"
echo "Prepared experimental arm64 Node 18 probe from verified archive."
