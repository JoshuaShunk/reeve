# Security Policy

Reeve handles sensitive credentials (Proxmox API tokens, SSH passwords,
AI provider keys) and connects to a user's own infrastructure, so security reports
are taken seriously.

## Supported versions

Security fixes land on `main` and ship in the next release. Please verify an issue
against the latest `main` (or latest release) before reporting.

| Version | Supported |
| ------- | --------- |
| Latest release / `main` | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private vulnerability reporting: go to the repository's **Security**
tab → **Report a vulnerability** (GitHub Security Advisories). This opens a private
channel with the maintainers.

Please include:

- A description of the issue and its impact.
- Steps to reproduce (a minimal proof of concept if possible).
- Affected version / commit, platform (iOS / iPadOS / macOS), and configuration.

**Do not include real secrets.** Redact tokens, passwords, hostnames, and IPs.

### What to expect

- Acknowledgement within a few days.
- An assessment and, for confirmed issues, a fix on a best-effort timeline
  appropriate to severity.
- Credit in the release notes if you'd like it (let us know).

## Scope

In scope: the application code in this repository.

Out of scope:

- Proxmox VE itself and other third-party services the app connects to. Report
  those to their respective projects.
- User misconfiguration (e.g. choosing "Allow insecure" TLS, weak tokens, exposing
  a server to the internet).
- Issues requiring a physical, unlocked device.

## How the app handles secrets (for context)

- There is **no backend**; the app talks only to servers the user configures.
- Secrets are stored in the device **Keychain**, never in plists/UserDefaults and
  never transmitted anywhere except to authenticate with the user's own servers.
- Self-signed TLS is supported via explicit per-host trust (system / pinned
  SHA-256 / allow-insecure), not a blanket bypass.

See [PRIVACY.md](PRIVACY.md) for the data-handling summary.
