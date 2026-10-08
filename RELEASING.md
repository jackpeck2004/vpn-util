# Release checklist

Source may be published under the MIT license. Version 0.1.0 is an early preview; a stable downloadable binary requires the manual checks below.

## Validate source

1. Run `bash scripts/test.sh`, `bash scripts/build.sh`, and `git diff --check` on a clean checkout.
2. Confirm no `.env`, build output, diagnostic logs, real VPN profiles, private keys, credentials, or machine-specific test fixtures are tracked. Review both the files and Git history before publishing.
3. Review the diff from the previous release. Set `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist` when producing a new binary version.
4. Have the macOS CI workflow pass after publication. The workflow uses synthetic tests and does not query a maintainer's VPN profiles.

## Manually validate the application

- Launch the packaged app; confirm the menu bar icon appears with no Dock icon or setup flow.
- Open each menu, keep a submenu open through refresh, and close the menu. Check keyboard navigation, responsiveness, and that polling stops when closed.
- Check installed, missing, and unavailable clients. Confirm discovered Cisco/OpenVPN profiles open the original apps and do not claim to select a profile automatically.
- Deliberately test Tailscale and native VPN connect/disconnect, Cisco disconnect, client-owned login/MFA, VPN Settings, and failures. Do not automate connection changes on a maintainer's machine.
- Confirm Quit leaves existing VPN sessions running. Measure idle CPU, resident memory, and child processes after startup settles.
- Validate on each advertised macOS version/architecture. The deployment target alone is not proof of compatibility; current local validation covers Apple Silicon only.

## Distribute binaries

`scripts/build.sh` creates a native-architecture, ad-hoc signed local app in `dist/`; `--universal` builds Apple Silicon and Intel executables into one app. Neither mode notarizes or publishes anything.

### Automated preview releases

Push the repository and its `main` branch to GitHub first. Enable Actions if repository policy disables it, and permit the release job's `contents: write` token permission. No personal access token or `.env` values are needed.

1. Set the numeric app version in `Resources/Info.plist`; increment its build number for subsequent binary versions. Complete the relevant manual checks above.
2. Commit to `develop`, validate, and promote to `main`. Push `main` before its tag.
3. Create and push an annotated version tag:

   ```sh
   git tag -a v0.1.0 -m "VPN Utility 0.1.0 preview"
   git push origin v0.1.0
   ```

The `macOS CI and releases` workflow runs core and offline publication checks, verifies that the tagged commit belongs to `main` and matches the app version, builds the universal app, checks its ad-hoc signature, and creates a ZIP and checksum. Tags such as `v0.1.0-rc.1` also work when the numeric app version is `0.1.0`.

Only the tag release job receives write permission. It creates a draft, uploads the ZIP, checksum, and generated Homebrew cask, checks their presence, and publishes a prerelease that is not marked Latest. An upload failure leaves the draft unpublished; rerun the failed workflow to resume it. A rerun of a published release verifies the download names and skips replacing them; an incomplete published release fails and requires maintainer attention. Per-tag concurrency prevents overlapping runs from racing.

Download `VPN-Utility-<tag>-universal.zip` and `SHA256SUMS-<tag>.txt` from GitHub Releases. The versioned release notes explicitly state signing and validation limits. This pipeline does not create a GitHub repository, push source, create tags, or publish stable/notarized builds.

For local packaging and offline script checks:

```sh
python3 Tests/ReleaseTests/test_release.py -v
bash scripts/package-release.sh v0.1.0
```

### Stable distribution

For a consumer download, use a valid Developer ID Application identity, sign the finished bundle with the hardened runtime, submit the archive through Apple's notarization tools, and staple the accepted ticket. Keep all signing/notarization credentials in the Keychain or protected CI secrets. Verify the finished result on a clean Mac before publication. Do not ask users to disable Gatekeeper.

Package a verified app using `ditto` to preserve its executable permissions and bundle structure:

```sh
ditto -c -k --keepParent "dist/VPN Utility.app" "dist/VPN-Utility.zip"
shasum -a 256 "dist/VPN-Utility.zip"
```

The current automation intentionally publishes previews only. Add and validate a Developer ID signing/notarization stage before changing it to publish stable binaries. Publish versioned release notes, the artifact checksum, supported architectures/macOS versions, signing status, and known client limitations. Do not label an unverified binary as a stable release.

## Homebrew distribution

The same GitHub source repository is the tap. No extra repository, access token,
Homebrew formula, or source compilation on the user's Mac is needed. The cask
installs the universal `.app` from a versioned release URL and verifies SHA-256.

1. Publish the GitHub preview using the tag workflow. Download `vpn-utility.rb`
   from that release and inspect its repository, version, and checksum.
2. Commit it as `Casks/vpn-utility.rb` on `develop`, validate, promote to `main`,
   and push both branches. Users of the tap read `main`, so this commit activates
   the Homebrew version. Never advertise a cask before its download is published.
3. Give users the `brew tap` and `brew install --cask` commands from README.md,
   replacing `OWNER` and `REPOSITORY` with your GitHub names. The explicit clone
   URL allows the source repository to have any name.

For a locally packaged release, generate a cask before committing it:

```sh
python3 scripts/generate-cask.py OWNER/REPOSITORY v0.1.0 \
  dist/VPN-Utility-v0.1.0-universal.zip Casks/vpn-utility.rb
ruby -c Casks/vpn-utility.rb
```

Use this only when that exact ZIP is the published download. Locally rebuilt
ZIPs may have different checksums; prefer the cask generated by the release
workflow. A cask update is a normal source commit after a release, not a new
app release/tag. CI does not directly push to your protected default branch.

After pushing, validate the tapped cask with
`brew info --cask OWNER/vpn-utility/vpn-utility`. Test installation and upgrade on a clean Mac with
Homebrew. Check the downloaded bundle, launch, and normal security approval.
Do not use `--no-quarantine` or add hooks that disable Gatekeeper. The current
preview is not Developer ID signed or notarized; Homebrew does not change that.

For every subsequent app release, repeat the download/review/commit steps with
its generated cask. `brew update` then retrieves the new cask, and
`brew upgrade --cask OWNER/vpn-utility/vpn-utility` installs that version.
