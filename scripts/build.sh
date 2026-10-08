#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/ModuleCache"
swift build -c release --product VPNUtility
binary_directory="$(swift build -c release --show-bin-path)"
app_directory="$project_root/dist/VPN Utility.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/VPNUtility" "$app_directory/Contents/MacOS/VPNUtility"
cp "$project_root/Resources/Info.plist" "$app_directory/Contents/Info.plist"
cp "$project_root/LICENSE" "$app_directory/Contents/Resources/LICENSE.txt"
swift "$project_root/scripts/Icon.swift" "$project_root/.build/VPNUtility.iconset"
iconutil -c icns "$project_root/.build/VPNUtility.iconset" -o "$app_directory/Contents/Resources/VPNUtility.icns"
codesign --force --sign - "$app_directory"
codesign --verify --strict "$app_directory"
printf 'Built %s\n' "$app_directory"
