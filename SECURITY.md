# Security and privacy

VPN Utility is a local controller for installed VPN clients. It does not implement VPN protocols, collect telemetry, store credentials, import VPN configurations, or make its own network requests. Existing clients own authentication and tunnel management, including any network requests they make in response to actions.

The app runs as the current user without an administrator helper or App Sandbox entitlement. It queries supported local command interfaces and opens existing apps. CLI arguments are passed as separate arguments, not interpolated into shell commands. Read operations have a five-second timeout; requested connection operations have a sixty-second timeout. Output is limited to 256 KiB per stream and kept in memory.

Normal operation does not write profile data to files. The explicitly invoked `--diagnose` command prints profile names, identifiers, hostnames, application paths, and connection state. Treat this output as private and redact it before sharing. `.env`, logs, build outputs, and packaged applications are excluded from Git.

## Reporting a vulnerability

Use the GitHub repository's **Security → Report a vulnerability** feature if the maintainer enables private reporting after publication. If it is unavailable, contact the maintainer privately through their GitHub profile. Do not disclose exploitable vulnerabilities or sensitive diagnostics in public issues.

Include the affected commit/version, reproduction steps using synthetic data where possible, expected behavior, and impact. No response SLA or independent security audit is claimed for this early source preview.

## Distribution

Local builds are ad-hoc signed. They are not Developer ID signed or notarized and should not be described as Gatekeeper-ready downloads. Signing keys, certificates, passwords, and notarization credentials belong in a local Keychain or protected CI secrets, never the repository or `.env.example`.
