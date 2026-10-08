#!/usr/bin/env python3
"""Generate a Homebrew cask from a verified local release ZIP; no network."""
import argparse
import hashlib
from pathlib import Path
import re


def render(repository, tag, archive):
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9_.-]+", repository):
        raise ValueError("repository must be a GitHub owner/repository name")
    if repository.split("/")[1] in {".", ".."}:
        raise ValueError("invalid repository name")
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?", tag):
        raise ValueError("tag must be vX.Y.Z, optionally with a prerelease suffix")
    if archive.name != f"VPN-Utility-{tag}-universal.zip" or not archive.is_file():
        raise ValueError("archive must be the versioned universal release ZIP")
    checksum = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            checksum.update(chunk)
    digest = checksum.hexdigest()
    return f'''cask "vpn-utility" do
  version "{tag[1:]}"
  sha256 "{digest}"

  url "https://github.com/{repository}/releases/download/v#{{version}}/VPN-Utility-v#{{version}}-universal.zip"
  name "VPN Utility"
  desc "Menu bar controls for existing VPN clients"
  homepage "https://github.com/{repository}"

  depends_on macos: :ventura

  app "VPN Utility.app"

  caveats <<~EOS
    This preview is ad-hoc signed and is not notarized.
    macOS may require its normal per-app security approval when opening it.
    Existing VPN clients remain responsible for login and authentication.
  EOS
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", help="GitHub owner/repository")
    parser.add_argument("tag")
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        content = render(args.repository, args.tag, args.archive)
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content)


if __name__ == "__main__":
    main()
