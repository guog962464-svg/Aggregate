#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$probe_root/../../.." && pwd)"
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
ndk_root="${ANDROID_NDK_HOME:-}"
if [[ -z "$ndk_root" ]]; then
  if [[ -z "$sdk_root" ]]; then
    echo "Set ANDROID_NDK_HOME or ANDROID_HOME/ANDROID_SDK_ROOT" >&2
    exit 1
  fi
  ndk_root="$sdk_root/ndk/28.2.13676358"
fi

case "$(uname -s)" in
  Darwin) host_tag="darwin-x86_64" ;;
  Linux) host_tag="linux-x86_64" ;;
  *) echo "Unsupported NDK host: $(uname -s)" >&2; exit 1 ;;
esac

toolchain="$ndk_root/toolchains/llvm/prebuilt/$host_tag/bin"
compiler="$toolchain/aarch64-linux-android24-clang"
readelf="$toolchain/llvm-readelf"
headers="$repo_root/app/android/nodebridge/vendor/include/node"
node_library="$repo_root/app/android/nodebridge/src/main/jniLibs/arm64-v8a/libnode.so"
source="$probe_root/fixtures/a4-boundary/addon.c"
assets="$repo_root/app/android/nodebridge/src/main/assets"
output="$assets/a4-boundary-native-addon.node"

if [[ ! -x "$compiler" || ! -x "$readelf" ]]; then
  echo "NDK r28c arm64 API 24 compiler/readelf not found under $toolchain" >&2
  exit 1
fi
if [[ ! -f "$headers/node_api.h" ]]; then
  echo "Prepare the pinned nodejs-mobile headers before building the addon" >&2
  exit 1
fi
if [[ ! -f "$node_library" ]]; then
  echo "Prepare the pinned arm64 nodejs-mobile library before building the addon" >&2
  exit 1
fi

"$compiler" -shared -fPIC -O2 -DNAPI_VERSION=8 \
  -I "$headers" -L "$(dirname "$node_library")" \
  -Wl,--no-as-needed -l:libnode.so -Wl,-z,max-page-size=16384 \
  -o "$output" "$source"
"$readelf" -h "$output" | rg -q 'Machine:.*AArch64'
"$readelf" -l "$output" | rg -q 'LOAD.*0x4000'

echo "Prepared an arm64 Android N-API 8 fixture at $output"
