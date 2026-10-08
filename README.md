# VPN Utility

A lightweight, native macOS menu bar utility for VPN clients you already have installed. Launch it to discover existing clients and profiles; no onboarding, configuration, or credential import is required.

**Status:** early source preview, version 0.1.0. The source is MIT licensed. Local builds are ad-hoc signed; a stable, notarized public download is not yet available. See [RELEASING.md](RELEASING.md) for the remaining validation gates.

## Requirements

- macOS 13 or later; currently validated locally on Apple Silicon only.
- Swift 5.9 or later and Apple's Command Line Tools to build. The full Xcode app is not required.
- Existing, configured VPN clients or macOS L2TP/IPsec services. You do not need all supported clients installed.

## Build and launch

Clone or download the source, then run these commands from the repository root:

```sh
bash scripts/build.sh
open "dist/VPN Utility.app"
```

If Apple's Command Line Tools are missing, install them with `xcode-select --install` first. The build produces a native-architecture app in `dist/`, verifies its ad-hoc signature, and bundles no VPN client software.

You may move the resulting app to Applications. Use its network icon in the menu bar; it has no Dock icon or main window. The app starts only when launched. Quit leaves existing VPN sessions running.

## Supported controls

| Client | Discovery and status | Connection controls |
| --- | --- | --- |
| Tailscale | Bundled CLI reports connection state. | Connect/disconnect directly; login opens Tailscale. |
| Cisco Secure Client | CLI lists existing hosts and connection state. | Profile actions open Cisco; disconnect applies to its active session. |
| OpenVPN Connect | CLI lists existing profile names and identifiers. | Opens the original client for profile selection, connection, and disconnection. Status is shown in that client. |
| macOS L2TP/IPsec | macOS lists existing services and their state. | Starts/stops existing services; Open VPN Settings handles authentication or permissions. |

Cisco and OpenVPN profile entries do **not** automatically select a profile: choose it in the original client after the app opens it. Unsupported commands, missing profiles, corporate restrictions, and unavailable clients fall back to the original app or VPN Settings. Tunnelblick, Viscosity, legacy AnyConnect, and arbitrary VPN extensions are outside the first release.

Discovery runs on launch and whenever the menu opens. It refreshes every five seconds while the menu stays open; there is no idle polling. The neutral icon does not imply an aggregate connection state. The utility never automatically disconnects another VPN or edits existing client settings.

## Configuration and privacy

No `.env` file or environment settings are required. `.env.example` documents this; an optional local `.env` is ignored and is not loaded by the app. Do not add VPN passwords, tokens, certificates, or profiles to either file.

VPN clients retain ownership of authentication, saved credentials, MFA, certificates, and tunnels. The utility keeps discovered profile information in memory and has no analytics, updater, login item, credential database, administrator helper, or third-party runtime dependencies. It does not make its own network requests; the installed clients may do so during requested actions.

See [SECURITY.md](SECURITY.md) for the local command execution model and vulnerability reporting.

## Tests and diagnostics

```sh
bash scripts/test.sh
"dist/VPN Utility.app/Contents/MacOS/VPNUtility" --diagnose
```

The twelve portable checks cover parsing, duplicate discovery, missing clients, failure isolation, argument handling, output limits, pipe draining, inherited pipes, and timeout termination. They use synthetic fixtures and never connect/disconnect a VPN. A small executable supplies assertions, so testing does not depend on XCTest or Xcode.

Diagnostics reads real profiles and status and validates the detached menu structure without activating connection actions. **Its output contains private profile names, hostnames, identifiers, and local paths.** It is not saved by the app; redact it before sharing and never commit raw diagnostic output.

The GitHub Actions workflow runs synthetic checks, ten offline release/cask checks, builds the app, and verifies its signature on a hosted macOS runner. Pull-request and branch checks have read-only permissions. Only the tag-triggered release job has repository write permission, with its GitHub token supplied only to the publication step. The pinned checkout action does not retain credentials, and CI never runs real-profile diagnostics. Hosted execution requires publishing the repository first.

## Downloadable GitHub previews

After this source is on GitHub, pushing a version tag such as `v0.1.0` triggers tests and builds a universal Apple Silicon + Intel app. The tag must refer to a commit on `main`, and its numeric version must match `Resources/Info.plist`. The workflow uploads a versioned ZIP and SHA-256 checksum to a GitHub release, then publishes it as a **prerelease**. Find the downloads under the repository's **Releases** page.

```sh
# After configuring origin and pushing the branches:
git tag -a v0.1.0 -m "VPN Utility 0.1.0 preview"
git push origin v0.1.0
```

The preview pipeline needs no personal access token or signing secrets: it uses GitHub Actions' built-in token. Downloads are ad-hoc signed and not notarized, so normal macOS per-app security approval may be necessary. The pipeline does not advertise them as stable or Gatekeeper-ready builds. Failed uploads leave a draft; reruns can resume drafts but do not replace published downloads.

To produce the same ZIP locally without contacting GitHub:

```sh
bash scripts/package-release.sh v0.1.0
```

The result is `dist/VPN-Utility-v0.1.0-universal.zip` and `dist/SHA256SUMS-v0.1.0.txt`. Extract the ZIP, verify the checksum, and move the app to Applications. The universal build compiles both architectures; runtime compatibility across both still needs manual validation.

## Install with Homebrew

This source repository can also serve as your own Homebrew tap; a second
repository is not required. Each automated release includes `vpn-utility.rb`
with a versioned download URL and the exact ZIP checksum. Commit that file to
`Casks/` on `main` after publishing the release to activate or update the tap.
See [the maintainer steps](RELEASING.md#homebrew-distribution).

Once the first release is published and its cask is committed to `Casks/` on `main`, install from this repository:

```sh
brew tap jackpeck2004/vpn-utility https://github.com/jackpeck2004/vpn-util.git
brew install --cask jackpeck2004/vpn-utility/vpn-utility
open "/Applications/VPN Utility.app"
```

Installing the released app does not require Swift or Command Line Tools.
Homebrew handles installing and upgrading the app; it does not start it,
install VPN clients, configure VPNs, or bypass macOS security approval.

```sh
brew update
brew upgrade --cask jackpeck2004/vpn-utility/vpn-utility
brew uninstall --cask jackpeck2004/vpn-utility/vpn-utility
```

Quit VPN Utility before upgrading or uninstalling it. Removing the utility
leaves the original VPN clients and their configurations in place. The current
preview retains its ad-hoc signing and notarization limits.

## First launch: macOS security approval

The current preview is ad-hoc signed and is not notarized by Apple. After
installing it through Homebrew or downloading the release ZIP, macOS may display
**“VPN Utility” Not Opened** and say Apple could not verify that it is free of
malware. A successful bundle signature check verifies integrity; it does not
establish Apple approval or prove the app is free of malware.

If you trust this build and want to open it:

1. Click **Done** in the warning.
2. Open **System Settings → Privacy & Security**.
3. Find the VPN Utility warning and click **Open Anyway**.
4. Authenticate if prompted, then confirm **Open**.

See [Apple's instructions for safely opening apps](https://support.apple.com/102445).
This grants an exception for this app. Do not disable Gatekeeper or remove
quarantine protections globally. If your organization manages these settings,
its policies may prevent approval.

Removing this warning for public users requires Developer ID signing and Apple
notarization, using an Apple Developer account. These are not yet part of the
preview release pipeline.

## Validation and release limits

Local validation with Apple's Command Line Tools covered all four installed integrations, detached menu construction, app launch, and code signing. The original build measured approximately 0.6 MB on disk and 24–41 MiB of resident memory, with 0% CPU at idle samples and no idle child processes; these measurements are observations, not performance guarantees.

The subprocess pipe fix was reproduced before the change and all twelve checks pass afterward. Visual menu behavior, actual client handoffs, live connection changes, and compatibility across macOS versions/architectures remain manual release gates. Do not infer those checks from successful compilation or the deployment target.

For an ordinary consumer download, complete the [release checklist](RELEASING.md), Developer ID signing, notarization, and verification on a clean Mac. The build script deliberately does not publish or notarize anything.

## Development and license

`main` holds validated source; `develop` is the integration branch. See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, commit, test, and reporting guidance, and [CHANGELOG.md](CHANGELOG.md) for pending release notes.

Released under the [MIT License](LICENSE). VPN client names identify supported integrations; this project is independent of their vendors.
