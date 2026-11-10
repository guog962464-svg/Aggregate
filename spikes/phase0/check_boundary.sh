#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
if rg -n 'dart:io|dart:ffi|package:flutter_pty2|package:mcp_dart|\bPlatform\.|platform/macos' \
  packages/aggregate_contracts/lib packages/aggregate_domain/lib \
  packages/aggregate_connectors/lib packages/aggregate_runtime/lib \
  app/lib/app app/lib/features app/lib/widgets app/lib/preview; then
  echo "Public Flutter/core boundary contains platform dependency" >&2
  exit 1
fi
echo "PASS public Flutter/core boundary"
