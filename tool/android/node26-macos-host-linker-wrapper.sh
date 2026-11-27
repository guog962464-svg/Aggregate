#!/bin/bash
set -euo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    -Wl,--start-group|-Wl,--end-group) ;;
    *) args+=("$arg") ;;
  esac
done
args+=(-framework CoreFoundation)
exec /usr/bin/clang++ "${args[@]}"
