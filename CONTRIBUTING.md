# Contributing

Thanks for your interest in improving Reeve! Issues and pull requests are welcome.

## Getting set up

```sh
git clone https://github.com/joshuashunk/reeve.git
cd reeve
cp Local.xcconfig.sample Local.xcconfig   # set your own DEVELOPMENT_TEAM + APP_BUNDLE_ID
open Reeve.xcodeproj
```

A one-time toolchain component is needed for the terminal dependency:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Before opening a PR

- **Format:** run `swift format --in-place --recursive .` (config in `.swift-format`).
- **Test:** `swift test --package-path Packages/ReeveCore` must be green.
- **Build:** the iOS Simulator build should succeed
  (`xcodebuild -scheme Reeve -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`).
  CI runs the same on every push.

## Project layout

- `App/`: SwiftUI layer (a file-system-synchronized group, so adding/moving files needs no
  `.pbxproj` edits). Grouped by feature: `Agent/`, `Alerts/`, `SSH/`, `Settings/`, `Views/…`.
- `Packages/ReeveCore/`: all logic as a local Swift package (`ReeveModels`,
  `ReeveNetworking`, `ReevePersistence`, `ReeveFeatures`, `ReeveTerminal`). Keep UI out of here.
- `Widget/`: the WidgetKit extension.
- `docs/`: architecture and design notes.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the rationale.

## Conventions

- **Swift 6**, `@Observable` view models, default-`MainActor` isolation; no third-party deps in the
  app/monitoring path (the only ones are Citadel + SwiftTerm, confined to `ReeveTerminal`).
- **Comments explain *why*, not *what*.** Use `///` doc comments on public/non-obvious API.
- **Never commit secrets or personal identifiers.** `Local.xcconfig` (team/bundle id) is gitignored,
  and credentials live only in the Keychain. Use placeholder hosts (`pve.example.com`, `192.168.x.x`)
  in examples and tests.

## Adding a service integration

Implementing a new self-hosted service monitor is a single file conforming to `ServiceIntegration`.
See [docs/SERVICES_INTEGRATIONS_DESIGN.md](docs/SERVICES_INTEGRATIONS_DESIGN.md).
