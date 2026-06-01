# Architecture & rationale

This document records the design decisions behind Reeve and the
research that informed them (current as of the Xcode 26 / Swift 6.x era).

## Layering

```
App (SwiftUI)  ──►  ReeveFeatures  ──►  ReeveNetworking  ──►  ReeveModels
                          │                       ▲
                          └──► ReevePersistence ─┘ (Keychain + profiles)
```

- **ReeveModels:** pure `Codable`/`Sendable` value types mirroring the
  Proxmox API. No I/O, trivially testable, safe to share across actors.
- **ReeveNetworking:** `ProxmoxAPI` protocol + `LiveProxmoxAPI` over
  `async`/`await` `URLSession`. The protocol lets the UI and tests swap in mocks.
- **ReevePersistence:** `ServerProfile` storage (JSON in `UserDefaults`) with
  secrets isolated in the **Keychain** (`KeychainStore`), keyed per profile.
- **ReeveFeatures:** `@Observable`, `@MainActor` view models that are
  UI-agnostic, so logic is tested without SwiftUI.
- **App:** a thin SwiftUI layer; the only place with `#if os(macOS)`.

Putting everything except the UI in a **local Swift package** means the core
builds and tests on the command line (`swift test`) with no simulator, and the
module boundaries enforce a one-way dependency graph.

## Key decisions

| Decision | Why |
|---|---|
| Single **multiplatform** target | ~All code is shared; only `MenuBarExtra` is macOS-only. |
| **Local SPM package** for logic | Fast, simulator-free tests; clean module seams. |
| **Swift 6** language mode + default `MainActor` isolation | Modern concurrency safety with minimal friction; the package keeps explicit isolation. |
| **`@Observable`** (not `ObservableObject`) | Granular view invalidation, less boilerplate (iOS 17+). |
| **Swift Testing** + `URLProtocol` mock | Exercises the real `URLSession` path offline; current Apple direction. |
| **File-system-synchronized groups** (Xcode 16+) | `App/` auto-syncs into the target, minimal `.pbxproj` churn, clean clone-and-open, no XcodeGen/Tuist needed. |
| **Minimal dependencies** | First-party frameworks cover the app + monitoring/management; the only third-party packages are Citadel (SSH) + SwiftTerm (terminal), confined to the `ReeveTerminal` module behind the SSH-console feature. |
| **Keychain-only secrets** | Token secrets never touch source, JSON, or `UserDefaults`. |
| **TLS trust-on-first-use pinning** | Homelab Proxmox uses self-signed certs; pin the leaf SHA-256 per host. |

## Proxmox API notes

- Auth header: `Authorization: PVEAPIToken=user@realm!tokenid=secret`, **no**
  `Bearer` prefix, **no** CSRF token needed for token auth.
- `GET /cluster/resources` is one call backing the whole dashboard.
- `…/rrddata?timeframe=…&cf=AVERAGE` feeds the history charts.
- Units: `cpu` is a 0–1 fraction; `mem`/`disk`/`netin`/`netout` are bytes
  (cumulative in status, per-second rates in rrddata); `uptime` is seconds.

## Extending beyond Proxmox

The `ReeveNetworking` layer is structured so additional homelab services can
be added behind their own client protocols and surfaced in a "Services" screen:
Home Assistant (Bearer + WebSocket), AdGuard Home (`/control/stats`, Basic auth),
TrueNAS (`/api/v2.0`, Bearer), Jellyfin (`MediaBrowser` token), and Uptime Kuma
(Socket.IO / `/metrics`).
