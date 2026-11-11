#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
bridge_root="$probe_root/../nodebridge"
archive="${1:-${TMPDIR:-/tmp}/aggregate-nodejs-mobile-android-24.20.0-0.zip}"
ndk_root="${2:-${ANDROID_NDK_HOME:-}}"
license_file="${3:-${TMPDIR:-/tmp}/aggregate-nodejs-mobile-LICENSE-v24.20.0-0}"
expected="f5ffbaf4f2679fa9180b0758c637c2f8fc8828300f95129badf213a028fb37bb"
url="https://github.com/digidem/nodejs-mobile/releases/download/v24.20.0-0/nodejs-mobile-android-24.20.0-0.zip"
license_expected="c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66"
license_url="https://raw.githubusercontent.com/digidem/nodejs-mobile/v24.20.0-0/LICENSE"

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
if [[ ! -f "$license_file" ]]; then
  curl -fL --retry 2 -o "$license_file" "$license_url"
fi
license_actual="$(shasum -a 256 "$license_file" | awk '{print $1}')"
if [[ "$license_actual" != "$license_expected" ]]; then
  echo "A3 license SHA-256 mismatch: $license_actual" >&2
  exit 1
fi
unzip -tq "$archive" >/dev/null
mkdir -p "$bridge_root/src/main/jniLibs/arm64-v8a" "$bridge_root/vendor"
unzip -p "$archive" bin/arm64-v8a/libnode.so > "$bridge_root/src/main/jniLibs/arm64-v8a/libnode.so"
cp "$cpp_runtime" "$bridge_root/src/main/jniLibs/arm64-v8a/libc++_shared.so"
unzip -oq "$archive" 'include/node/*' -d "$bridge_root/vendor"
cp "$license_file" "$bridge_root/src/main/assets/nodejs-mobile-LICENSE.txt"
# AGP may reuse the JNI object after ignored vendor headers change.
touch "$bridge_root/src/main/cpp/node_probe.cpp"
echo "Prepared experimental arm64 Node 24.20.0 probe from verified archive."
