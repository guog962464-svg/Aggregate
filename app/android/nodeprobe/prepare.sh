#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
bridge_root="$probe_root/../nodebridge"
archive="${1:-${TMPDIR:-/tmp}/aggregate-nodejs-mobile-android-24.22.1-0.zip}"
ndk_root="${2:-${ANDROID_NDK_HOME:-}}"
license_file="${3:-${TMPDIR:-/tmp}/aggregate-nodejs-mobile-LICENSE-v24.22.1-0}"
expected="d6fd9f610fe5d81fede8f0d400c5a62723247725a19831835f15abf4f0604250"
url="https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-android-24.22.1-0.zip"
license_expected="c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66"
license_url="https://raw.githubusercontent.com/fogtape/nodejs-mobile/v24.22.1-0/LICENSE"

if [[ -z "$ndk_root" ]]; then
  sdk_root="$(sed -n 's/^sdk.dir=//p' "$probe_root/../local.properties")"
  ndk_root="$sdk_root/ndk/28.2.13676358"
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
mkdir -p "$bridge_root/vendor"
rm -rf "$bridge_root/vendor/include/node"
for abi in arm64-v8a armeabi-v7a x86_64; do
  case "$abi" in
    arm64-v8a) ndk_arch=aarch64-linux-android ;;
    armeabi-v7a) ndk_arch=arm-linux-androideabi ;;
    x86_64) ndk_arch=x86_64-linux-android ;;
  esac
  cpp_runtime="$(find "$ndk_root/toolchains/llvm/prebuilt" -path "*/$ndk_arch/libc++_shared.so" -print -quit)"
  if [[ ! -f "$cpp_runtime" ]]; then
    echo "NDK $abi libc++_shared.so not found under $ndk_root" >&2
    exit 1
  fi
  if [[ "$abi" == arm64-v8a ]]; then
    target="$bridge_root/src/main/jniLibs/$abi"
  else
    target="$bridge_root/src/allAbis/jniLibs/$abi"
    rm -rf "$bridge_root/src/main/jniLibs/$abi"
  fi
  mkdir -p "$target"
  unzip -p "$archive" "bin/$abi/libnode.so" > "$target/libnode.so"
  cp "$cpp_runtime" "$target/libc++_shared.so"
done
unzip -oq "$archive" 'include/node/*' -d "$bridge_root/vendor"
cp "$license_file" "$bridge_root/src/main/assets/nodejs-mobile-LICENSE.txt"
# AGP may reuse the JNI object after ignored vendor headers change.
touch "$bridge_root/src/main/cpp/node_probe.cpp"
echo "Prepared experimental three-ABI Node 24.22.1 prerelease probe from verified archive."
