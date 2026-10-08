# Contributing

Build and run checks on macOS with Swift 5.9 or later and Apple's Command Line Tools:

```sh
bash scripts/test.sh
bash scripts/build.sh
git diff --check
```

No .env configuration, third-party packages, or VPN credentials are required. Tests use synthetic fixtures and never change a VPN connection. Live checks are optional and must be deliberately initiated by the tester.

`main` holds validated source. Start a short-lived `feat/<name>` or `fix/<name>` branch from `develop` and target `develop` with pull requests. Promote validated changes to `main` with a fast-forward merge. Use concise Conventional Commits such as `fix: handle unavailable VPN status`.

Keep the utility small: use native AppKit controls and supported client interfaces. Preserve client-owned authentication; do not add credential handling or click automation. Add a focused regression check for behavior changes.

For bug reports, include macOS, Swift, and client versions, what you expected, and what happened. Redact profile names, VPN hostnames, addresses, usernames, and local paths before sharing diagnostics or screenshots. Never attach VPN profiles, certificates, passwords, tokens, or raw client databases.

See [SECURITY.md](SECURITY.md) for private vulnerability reporting and [RELEASING.md](RELEASING.md) for release gates.
