# Changelog

## Unreleased — 0.1.0 preview

- Native AppKit menu bar utility with zero third-party runtime dependencies.
- Automatic discovery of Tailscale, Cisco Secure Client hosts, OpenVPN Connect profiles, and macOS L2TP/IPsec services.
- Supported direct connection controls with client-owned authentication and explicit client handoffs.
- Bounded subprocess timeouts, output size, and pipe lifetimes, including commands with background descendants.
- Synthetic test fixtures, macOS CI configuration, and source-release documentation.
- Tag-triggered GitHub preview releases with universal app ZIPs, SHA-256 checksums, recoverable draft uploads, and offline publication tests.

- Generate a checksum-pinned Homebrew cask with every preview release; document using the source repository as a tap.

Visual menu behavior, actual client handoffs, live connection changes, broader macOS/architecture compatibility, and notarized distribution remain release gates. See [RELEASING.md](RELEASING.md).
