# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Graphical VNC console** for QEMU VMs: an in-house RFB 3.8 client (no
  third-party dependencies) over Proxmox's `vncproxy`, token-only, with
  pinch-to-zoom/pan, tap-to-click, and an on-screen keyboard with console keys.
- **Temperature & fan monitoring:** node CPU/drive temperatures and fan speeds via
  `sensors` over SSH, surfaced on the node detail screen, a dashboard KPI tile, and
  an optional high-temperature alert threshold.
- **Privacy policy** (`PRIVACY.md`) and App Store submission guide
  (`docs/APP_STORE_REVIEW.md`).
- Community health files: security policy, issue/PR templates, support guide,
  Dependabot config.

### Changed
- Network discovery now validates that each candidate is genuinely Proxmox before
  listing it, keeping discovery single-purpose (only the user's Proxmox servers).
- Declared `ITSAppUsesNonExemptEncryption` for streamlined App Store submission.

[Unreleased]: https://github.com/joshuashunk/reeve/commits/main
