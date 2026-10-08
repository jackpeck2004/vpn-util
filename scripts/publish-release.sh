#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_root/scripts/check-release-tag.sh" "$@"
tag="$1"
: "${GH_TOKEN:?GitHub Actions must provide GH_TOKEN}"
: "${GITHUB_REPOSITORY:?GitHub Actions must provide GITHUB_REPOSITORY}"
command -v gh >/dev/null
repository="$GITHUB_REPOSITORY"
archive="VPN-Utility-${tag}-universal.zip"
checksums="SHA256SUMS-${tag}.txt"
notes="$project_root/dist/release-notes-${tag}.md"
test -s "$project_root/dist/$archive"
test -s "$project_root/dist/$checksums"
test -s "$notes"
(cd "$project_root/dist" && shasum -a 256 -c "$checksums")

if state="$(gh release view "$tag" --repo "$repository" --json isDraft --jq '.isDraft' 2>/dev/null)"; then
    if [ "$state" = "false" ]; then
        # Published downloads are immutable from this pipeline; reruns are safe.
        assets="$(gh release view "$tag" --repo "$repository" --json assets --jq '.assets[].name')"
        printf '%s\n' "$assets" | grep -Fxq "$archive"
        printf '%s\n' "$assets" | grep -Fxq "$checksums"
        printf 'Release %s is already published with its downloads.\n' "$tag"
        exit 0
    fi
    test "$state" = "true"
else
    gh release create "$tag" --repo "$repository" --verify-tag --draft --prerelease \
        --latest=false --title "VPN Utility ${tag} — preview" --notes-file "$notes"
fi

# Only drafts may have assets replaced. An upload failure leaves a recoverable draft.
gh release upload "$tag" "$project_root/dist/$archive" "$project_root/dist/$checksums" \
    --repo "$repository" --clobber
assets="$(gh release view "$tag" --repo "$repository" --json assets --jq '.assets[].name')"
printf '%s\n' "$assets" | grep -Fxq "$archive"
printf '%s\n' "$assets" | grep -Fxq "$checksums"
gh release edit "$tag" --repo "$repository" --draft=false --prerelease --latest=false \
    --title "VPN Utility ${tag} — preview" --notes-file "$notes"
