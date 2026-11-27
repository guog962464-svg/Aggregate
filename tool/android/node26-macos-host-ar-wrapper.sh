#!/bin/bash
set -euo pipefail
operation="$1"
archive="$2"
shift 2
members=()
for argument in "$@"; do
  if [[ "$argument" == @* ]]; then
    while IFS= read -r member; do
      [[ -z "$member" ]] || members+=("$member")
    done < "${argument#@}"
  else
    members+=("$argument")
  fi
done
if [[ "$operation" == *T* ]]; then
  exec /usr/bin/libtool -static -o "$archive" "${members[@]}"
fi
exec /usr/bin/ar "$operation" "$archive" "${members[@]}"
