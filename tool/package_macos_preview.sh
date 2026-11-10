#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$root/work/release"}
version=$(sed -n 's/^version: \([^+]*\).*/\1/p' "$root/app/pubspec.yaml")
if [ -z "$version" ]; then
  echo 'app/pubspec.yaml 缺少版本号' >&2
  exit 1
fi
archive="$output_dir/Aggregate-macOS-stage3-preview-v$version.zip"
if [ -e "$archive" ]; then
  echo "目标已存在：$archive" >&2
  exit 1
fi

mkdir -p "$output_dir"
cd "$root/app"
flutter build macos --release --dart-define="APP_VERSION=$version"

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
source_app="$root/app/build/macos/Build/Products/Release/Aggregate.app"
ditto "$source_app" "$temporary/Aggregate.app"
codesign --force --deep --sign - "$temporary/Aggregate.app"
codesign --verify --deep --strict "$temporary/Aggregate.app"
ditto -c -k --sequesterRsrc --keepParent "$temporary/Aggregate.app" "$archive"
mkdir "$temporary/extracted"
ditto -x -k "$archive" "$temporary/extracted"
codesign --verify --deep --strict "$temporary/extracted/Aggregate.app"
shasum -a 256 "$archive"
echo "预览包：$archive"
echo '签名：ad hoc；未公证，不是正式分发包。'
