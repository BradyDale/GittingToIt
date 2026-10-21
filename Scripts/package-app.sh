#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
app_dir="$project_dir/.build/GittingToIt.app"
staging_root=$(mktemp -d "${TMPDIR:-/tmp}/GittingToIt-package.XXXXXX")
staged_app="$staging_root/GittingToIt.app"

swift build --disable-sandbox -c "$configuration"
binary_dir=$(swift build --disable-sandbox -c "$configuration" --show-bin-path)

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/GittingToIt" "$staged_app/Contents/MacOS/GittingToIt"
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_dir/Resources/GittingToIt.icns" "$staged_app/Contents/Resources/GittingToIt.icns"
printf 'APPL????' > "$staged_app/Contents/PkgInfo"
xattr -cr "$staged_app"
codesign --force --deep --sign - "$staged_app" >/dev/null

# Assemble and sign outside synced folders, where File Provider metadata can
# otherwise make codesign reject an otherwise valid app bundle.
if [ -e "$app_dir" ]; then
    mv "$app_dir" "$staging_root/previous.app"
fi
mv "$staged_app" "$app_dir"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"

printf '%s\n' "$app_dir"
