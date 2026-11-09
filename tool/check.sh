#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed app/lib app/test packages spikes/phase0/bin
flutter analyze
sh spikes/phase0/check_boundary.sh
dart test packages/aggregate_contracts/test packages/aggregate_domain/test packages/aggregate_connectors/test packages/aggregate_runtime/test
flutter test app/test
cd app
flutter build macos --debug
