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

`scripts/build.sh` creates a native-architecture, ad-hoc signed local app in `dist/`. It does not create a universal binary, notarize, or publish a release.

For a consumer download, use a valid Developer ID Application identity, sign the finished bundle with the hardened runtime, submit the archive through Apple's notarization tools, and staple the accepted ticket. Keep all signing/notarization credentials in the Keychain or protected CI secrets. Verify the finished result on a clean Mac before publication. Do not ask users to disable Gatekeeper.

Package a verified app using `ditto` to preserve its executable permissions and bundle structure:

```sh
ditto -c -k --keepParent "dist/VPN Utility.app" "dist/VPN-Utility.zip"
shasum -a 256 "dist/VPN-Utility.zip"
```

Promote validated changes from `develop` to `main`, then tag that commit when release gates pass. Publish versioned release notes, the artifact checksum, supported architectures/macOS versions, signing status, and known client limitations. Do not label the current unverified binary as a stable release.
