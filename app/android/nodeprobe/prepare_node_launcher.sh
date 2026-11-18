#!/usr/bin/env bash
set -euo pipefail

probe_root="$(cd "$(dirname "$0")" && pwd)"
bridge_root="$probe_root/../nodebridge"
ndk_root="${1:-${ANDROID_NDK_HOME:-}}"
if [[ -z "$ndk_root" || ! -d "$ndk_root/toolchains/llvm/prebuilt" ]]; then
  echo "Android NDK root is required to build the NodeProbe launcher" >&2
  exit 1
fi

include_dir="$bridge_root/vendor/include/node"
source_file="$probe_root/native/node_launcher.cpp"
if [[ ! -f "$include_dir/node.h" || ! -f "$source_file" ]]; then
  echo "Node headers or launcher source are missing; run prepare.sh first" >&2
  exit 1
fi

compile_launcher() {
  local abi="$1"
  local compiler_name="$2"
  local library_dir="$3"
  local compiler=""
  local readelf=""
  local output="$library_dir/libnode_cli.so"

  compiler="$(find "$ndk_root/toolchains/llvm/prebuilt" -path "*/bin/$compiler_name" -print -quit)"
  readelf="$(find "$ndk_root/toolchains/llvm/prebuilt" -path '*/bin/llvm-readelf' -print -quit)"
  if [[ ! -x "$compiler" || ! -x "$readelf" ]]; then
    echo "NDK compiler/readelf for $abi not found under $ndk_root" >&2
    exit 1
  fi
  if [[ ! -f "$library_dir/libnode.so" || ! -f "$library_dir/libc++_shared.so" ]]; then
    echo "Node libraries for $abi are missing in $library_dir; run prepare.sh first" >&2
    exit 1
  fi

  "$compiler" -std=c++20 -stdlib=libc++ -fPIE -pie \
    -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 \
    -Wl,-rpath,'$ORIGIN' -Wl,--no-undefined \
    -I "$include_dir" "$source_file" \
    -L "$library_dir" -lnode -landroid -llog -ldl -lm -lc++_shared \
    -o "$output"
  chmod 755 "$output"

  local header
  local program_headers
  header="$("$readelf" -hW "$output")"
  grep -Eq 'Type:[[:space:]]+DYN' <<< "$header" || {
    echo "$abi launcher is not a PIE shared object" >&2
    exit 1
  }
  program_headers="$("$readelf" -lW "$output")"
  grep -Fq '/system/bin/linker' <<< "$program_headers" || {
    echo "$abi launcher does not use the Android dynamic linker" >&2
    exit 1
  }
  if ! awk '$1 == "LOAD" { count++; if ($NF != "0x4000") bad = 1 } END { exit (count == 0 || bad) }' <<< "$program_headers"; then
    echo "$abi launcher contains a PT_LOAD segment below 16 KB alignment" >&2
    exit 1
  fi
  local dynamic
  dynamic="$("$readelf" -dW "$output")"
  grep -Fq 'Library runpath: [$ORIGIN]' <<< "$dynamic" || {
    echo "$abi launcher is missing its sibling-library RUNPATH" >&2
    exit 1
  }
  for dependency in libnode.so libc++_shared.so; do
    grep -Fq "Shared library: [$dependency]" <<< "$dynamic" || {
      echo "$abi launcher is missing DT_NEEDED $dependency" >&2
      exit 1
    }
  done
  echo "Built and checked $abi NodeProbe CLI launcher: $output"
}

compile_launcher arm64-v8a aarch64-linux-android24-clang++ \
  "$bridge_root/src/main/jniLibs/arm64-v8a"
compile_launcher armeabi-v7a armv7a-linux-androideabi24-clang++ \
  "$bridge_root/src/allAbis/jniLibs/armeabi-v7a"
compile_launcher x86_64 x86_64-linux-android24-clang++ \
  "$bridge_root/src/allAbis/jniLibs/x86_64"
