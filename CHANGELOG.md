# Changelog

## 0.2.0 preview

- Add a green menu bar dot for observed connected Tailscale, Cisco, or native VPN sources.
- Add top-level disconnect and client/settings shortcuts for each active source; Cisco remains client-level.
- Refresh known statuses every 15 seconds while closed and five seconds while open without enumerating profiles or invoking OpenVPN in the background.
- Add checks for active-source selection, multiple Cisco profiles, polling scope, and failed reads clearing the indicator.

## 0.1.1 preview

- Route native L2TP/IPsec connection requests through VPN Settings, preserving system-owned authentication and avoiding credential-free `scutil start` requests. Direct disconnect remains supported.
- Clarify that Tailscale status describes the tailnet backend, which can differ from the macOS VPN extension indicator.
- Add a synthetic regression check that native connect never launches a credential-free command.

## 0.1.0 preview

- Native AppKit menu bar utility with zero third-party runtime dependencies.
- Automatic discovery of Tailscale, Cisco Secure Client hosts, OpenVPN Connect profiles, and macOS L2TP/IPsec services.
- Supported direct connection controls with client-owned authentication and explicit client handoffs.
- Bounded subprocess timeouts, output size, and pipe lifetimes, including commands with background descendants.
- Synthetic test fixtures, macOS CI configuration, and source-release documentation.
- Tag-triggered GitHub preview releases with universal app ZIPs, SHA-256 checksums, recoverable draft uploads, and offline publication tests.

- Generate a checksum-pinned Homebrew cask with every preview release; document using the source repository as a tap.

Visual menu behavior, actual client handoffs, live connection changes, broader macOS/architecture compatibility, and notarized distribution remain release gates. See [RELEASING.md](RELEASING.md).
