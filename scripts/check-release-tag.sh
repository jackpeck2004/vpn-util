#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 1 ]; then
    printf 'Usage: bash scripts/check-release-tag.sh v<version>[-<preview>]\n' >&2
    exit 2
fi
tag="$1"
pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'
if [[ ! "$tag" =~ $pattern ]]; then
    printf 'Invalid release tag. Use v0.1.0 or v0.1.0-rc.1.\n' >&2
    exit 2
fi
tag_version="${tag#v}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
if [ "${tag_version%%-*}" != "$version" ]; then
    printf 'Release tag version does not match Resources/Info.plist (%s).\n' "$version" >&2
    exit 2
fi
