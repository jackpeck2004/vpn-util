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

The GitHub Actions workflow runs synthetic checks, builds the app, and verifies its signature on a hosted macOS runner. It has read-only repository permissions, uses a pinned checkout action, and never runs real-profile diagnostics. The workflow has not been executed remotely until this repository is published.

## Validation and release limits

Local validation with Apple's Command Line Tools covered all four installed integrations, detached menu construction, app launch, and code signing. The original build measured approximately 0.6 MB on disk and 24–41 MiB of resident memory, with 0% CPU at idle samples and no idle child processes; these measurements are observations, not performance guarantees.

The subprocess pipe fix was reproduced before the change and all twelve checks pass afterward. Visual menu behavior, actual client handoffs, live connection changes, and compatibility across macOS versions/architectures remain manual release gates. Do not infer those checks from successful compilation or the deployment target.

For an ordinary consumer download, complete the [release checklist](RELEASING.md), Developer ID signing, notarization, and verification on a clean Mac. The build script deliberately does not publish or notarize anything.

## Development and license

`main` holds validated source; `develop` is the integration branch. See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, commit, test, and reporting guidance, and [CHANGELOG.md](CHANGELOG.md) for pending release notes.

Released under the [MIT License](LICENSE). VPN client names identify supported integrations; this project is independent of their vendors.
