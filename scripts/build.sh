#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/ModuleCache"
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--universal" ]; }; then
    printf 'Usage: bash scripts/build.sh [--universal]\n' >&2
    exit 2
fi
mkdir -p "$project_root/.build" "$project_root/dist"
# Package in a fresh directory so stale bundle resources cannot enter a release.
package_directory="$(mktemp -d "$project_root/.build/package.XXXXXX")"
if [ "${1:-}" = "--universal" ]; then
    for architecture in arm64 x86_64; do
        triple="${architecture}-apple-macosx13.0"
        scratch="$project_root/.build/$architecture"
        swift build -c release --product VPNUtility --triple "$triple" --scratch-path "$scratch"
        binary_directory="$(swift build -c release --product VPNUtility --triple "$triple" --scratch-path "$scratch" --show-bin-path)"
        cp "$binary_directory/VPNUtility" "$package_directory/$architecture"
    done
    lipo -create "$package_directory/arm64" "$package_directory/x86_64" -output "$package_directory/VPNUtility"
    lipo "$package_directory/VPNUtility" -verify_arch arm64
    lipo "$package_directory/VPNUtility" -verify_arch x86_64
else
    swift build -c release --product VPNUtility
    binary_directory="$(swift build -c release --product VPNUtility --show-bin-path)"
    cp "$binary_directory/VPNUtility" "$package_directory/VPNUtility"
fi
app_directory="$package_directory/VPN Utility.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$package_directory/VPNUtility" "$app_directory/Contents/MacOS/VPNUtility"
cp "$project_root/Resources/Info.plist" "$app_directory/Contents/Info.plist"
cp "$project_root/LICENSE" "$app_directory/Contents/Resources/LICENSE.txt"
swift "$project_root/scripts/Icon.swift" "$project_root/.build/VPNUtility.iconset"
iconutil -c icns "$project_root/.build/VPNUtility.iconset" -o "$app_directory/Contents/Resources/VPNUtility.icns"
codesign --force --sign - "$app_directory"
codesign --verify --strict --all-architectures "$app_directory"
destination="$project_root/dist/VPN Utility.app"
if [ -e "$destination" ]; then
    mv "$destination" "$package_directory/previous.app"
fi
mv "$app_directory" "$destination"
printf 'Built %s\n' "$destination"
