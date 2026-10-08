#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_root/scripts/check-release-tag.sh" "$@"
tag="$1"
bash "$project_root/scripts/build.sh" --universal
app="$project_root/dist/VPN Utility.app"
lipo "$app/Contents/MacOS/VPNUtility" -verify_arch arm64
lipo "$app/Contents/MacOS/VPNUtility" -verify_arch x86_64
codesign --verify --strict --all-architectures "$app"
archive="VPN-Utility-${tag}-universal.zip"
ditto -c -k --keepParent "$app" "$project_root/dist/$archive"
cd "$project_root/dist"
shasum -a 256 "$archive" > "SHA256SUMS-${tag}.txt"
shasum -a 256 -c "SHA256SUMS-${tag}.txt"
cat > "release-notes-${tag}.md" <<EOF
VPN Utility ${tag} — preview

Download ${archive}, extract VPN Utility.app, and move it to Applications.
The universal app contains Apple Silicon (arm64) and Intel (x86_64) executables;
its deployment target is macOS 13 or later. Both architectures are compiled
and the host architecture runs the synthetic tests. Broader runtime and
live-client validation remains a manual release gate.

This app is ad-hoc signed, not Developer ID signed or notarized. macOS may
require its normal per-app security approval; this is not a Gatekeeper-ready
stable release. No signing secrets or app configuration are required by this
preview pipeline. Never disable system security protections to install it.

Verify the download using SHA256SUMS-${tag}.txt and shasum -a 256 -c.
Cisco and OpenVPN profile actions open the original clients for selection and
authentication. See README.md, CHANGELOG.md, and RELEASING.md in the source.
EOF
printf 'Packaged %s\n' "$project_root/dist/$archive"
