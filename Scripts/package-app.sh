#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
app_dir="$project_dir/.build/GittingToIt.app"

swift build --disable-sandbox -c "$configuration"
binary_dir=$(swift build --disable-sandbox -c "$configuration" --show-bin-path)

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/GittingToIt" "$app_dir/Contents/MacOS/GittingToIt"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
printf 'APPL????' > "$app_dir/Contents/PkgInfo"
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir" >/dev/null

printf '%s\n' "$app_dir"
