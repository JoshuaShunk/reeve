# Design brief: a pluggable, capability-based "Services" feature

Status: proposal / design brief. Targets the existing layering in
[`ARCHITECTURE.md`](./ARCHITECTURE.md). Swift 6.2, `@Observable`, `Sendable`,
minimal third-party deps, logic in the `ReeveCore` SPM package, secrets in
Keychain keyed per-instance UUID.

The goal: let users monitor a *heterogeneous, partially-overlapping* set of
self-hosted services (Jellyfin, AdGuard Home, TrueNAS, Home Assistant, Uptime
Kuma, Pi-hole, Sonarr/Radarr, Portainer, …). Not everyone runs the same ones.
Adding a new service must be a self-contained file a contributor drops in and
registers, never a core refactor.

---

## 0. TL;DR recommendation

- **One `ServiceIntegration` protocol per service type**: each a `Sendable` value
  that *declares* its identity, config schema, and auth method as **data**, and
  *implements* a single `fetchStatus(instance:secret:client:) async throws ->
  ServiceStatus`.
- **A registry of conformers** (`ServiceCatalog`), an array assembled at launch.
  This is the sweet spot between a closed `enum` (not extensible) and a fully
  data-driven YAML manifest (powerful but needs an interpreter + remote schema).
  Swift gives us type-safety and testability for free; the registry stays
  contributor-friendly because adding a service = add one file + one array entry.
- **A uniform, generic result model** (`ServiceStatus` with `health`, `[Stat]`,
  `[DetailRow]`) that is `Codable`/`Sendable`, so the SwiftUI list/detail and the
  WidgetKit extension render *any* service with no bespoke views, and results
  cache + cross the App Group boundary cleanly.
- **Config schema is declared as data** (`[ConfigField]`) so the "Add service"
  form is generated generically, no per-service SwiftUI.
- **One small async HTTP client** (`HTTPClient` protocol) injected into every
  integration; each integration only builds requests + maps responses. The same
  `URLProtocol` mock already in the repo tests them offline.

The whole contributor story becomes: *"implement `ServiceIntegration`, return a
`ServiceStatus`, add yourself to `ServiceCatalog.builtIn`."*

---

## 1. Architecture: protocol-oriented, capability-based plugin system

### 1.1 The three nouns

Keep these strictly separated, it's the key to genericity:

| Concept | What it is | Lifetime | Where it lives |
|---|---|---|---|
| **Service *type*** (`ServiceIntegration`) | A stateless descriptor + behavior: id, display name, icon, config schema, auth method, and the fetch logic. One per supported product. | Compile-time, singleton-ish | code, in `ServiceCatalog` |
| **Configured *instance*** (`ServiceInstance`) | A user's concrete deployment: which type, friendly name, base URL, non-secret config values, TLS policy, instance `UUID`. | User data | `Codable` JSON in App Group `UserDefaults` |
| **Secret** | API key / password / token for that instance. | User data | **Keychain**, keyed by instance `UUID` (reuse `KeychainStore`) |
| **Result** (`ServiceStatus`) | The uniform health + metrics snapshot the UI renders. | Ephemeral / cached | memory + on-disk cache (App Group) |

This mirrors what the repo already does for Proxmox (`ServerProfile` = instance,
Keychain secret keyed by UUID, `ServerConnection` = profile+secret). We are
generalizing that pattern.

### 1.2 The core protocol

```swift
import Foundation

/// A *type* of self-hosted service the app can monitor (Jellyfin, AdGuard, …).
/// Stateless and `Sendable`: it holds no per-user data, only the behavior and the
/// metadata that lets the UI configure and render instances generically.
public protocol ServiceIntegration: Sendable {
    /// Stable, lowercase, dns-style id. Persisted in `ServiceInstance.typeID`,
    /// so NEVER rename once shipped (migrate instead). e.g. "adguard-home".
    static var typeID: String { get }

    /// Human-facing metadata for the picker + list rows.
    var displayName: String { get }        // "AdGuard Home"
    var category: ServiceCategory { get }   // .dns, .media, .storage, .automation…
    var iconAsset: ServiceIcon { get }      // SF Symbol or bundled asset name

    /// The auth mechanism; drives header construction + the form's secret field.
    var authMethod: AuthMethod { get }

    /// The *data-driven* config schema. The Add/Edit form is generated from this.
    var configFields: [ConfigField] { get }

    /// The one method every integration must implement: fetch + map to the
    /// uniform result. `client` is injected (testable). `instance` carries URL +
    /// non-secret config; `secret` is read from Keychain by the caller.
    func fetchStatus(
        for instance: ServiceInstance,
        secret: String?,
        client: HTTPClient
    ) async throws -> ServiceStatus
}

public extension ServiceIntegration {
    var typeID: String { Self.typeID }    // instance-side convenience
}
```

`typeID` is `static` so the registry and decoder can look up a type without an
instance. Everything the UI needs to *configure* (`configFields`, `authMethod`)
and *render* (`displayName`, `iconAsset`, the returned `ServiceStatus`) is
declared as data, so there is **zero bespoke SwiftUI per service**.

### 1.3 The registry (recommended approach)

```swift
/// The set of integrations the app knows about. The ONLY place a contributor
/// edits besides their own new file.
public struct ServiceCatalog: Sendable {
    public let integrations: [any ServiceIntegration]
    private let byID: [String: any ServiceIntegration]

    public init(_ integrations: [any ServiceIntegration]) {
        self.integrations = integrations
        self.byID = Dictionary(
            integrations.map { (type(of: $0).typeID, $0) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    public func integration(for typeID: String) -> (any ServiceIntegration)? {
        byID[typeID]
    }

    /// Built-in reference integrations. ADD YOUR INTEGRATION HERE.
    public static let builtIn = ServiceCatalog([
        AdGuardHomeIntegration(),
        JellyfinIntegration(),
        TrueNASIntegration(),
        HomeAssistantIntegration(),
        UptimeKumaIntegration(),
        PiHoleIntegration(),
    ])
}
```

#### Why a registry of conformers, not an enum or YAML manifest

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **`enum ServiceType` with associated logic** | Exhaustive `switch`, compact | Every new service edits the same giant enum + every `switch` over it → merge conflicts, not "drop-in"; can't be split across files | ❌ Not scalable for many contributors |
| **Data-driven YAML/JSON manifests** (Homepage/Dashy style) | Add a service with no recompile; remotely updatable | Needs a generic API-mapping interpreter (JSONPath, templating), runtime schema validation, and a sandbox for arbitrary endpoints; loses Swift type-safety and compile-time tests; security surface (arbitrary URLs from config) | ➖ Powerful but heavy; revisit later as a *secondary* loader |
| **Registry of protocol conformers** (recommended) | Each integration is one isolated `Sendable` file; type-safe response mapping; trivially unit-testable; "add file + 1 line"; previews/mocks for free | Requires recompile to add (fine for a native app shipped via App Store) | ✅ **Recommended** |

A native, App-Store-distributed app recompiles to ship anyway, so the YAML
manifest's headline advantage (no recompile) is largely moot, while its costs
(interpreter, schema validation, arbitrary-endpoint security) are real. The
registry keeps Swift's type system doing the heavy lifting. If you later want
user-defined "custom HTTP" services, add a single *generic* `CustomHTTPIntegration`
conformer that itself reads a small JSON mapping, you get the manifest model as
**one optional plugin**, not as the foundation of the whole system.

### 1.4 Module placement (fits existing layering)

```
ReeveModels        ServiceStatus, ServiceInstance, ConfigField, AuthMethod, Health, Stat …
                     (pure Codable/Sendable value types, no I/O)
ReeveNetworking    HTTPClient protocol + LiveHTTPClient; ServiceIntegration protocol;
                     ServiceCatalog; one file per integration (Integrations/…)
ReevePersistence   ServiceInstanceStore (JSON) + reuse KeychainStore for secrets
ReeveFeatures      @Observable @MainActor ServicesModel (list refresh, caching)
App                  Generic ServicesListView / ServiceDetailView / AddServiceView
```

---

## 2. How existing dashboards model heterogeneous services (and what to borrow)

| Project | Integration model | Mapping to display stats | Contributor story | Borrow |
|---|---|---|---|---|
| **Homepage** (`gethomepage`) | Per-service **widget** = `src/widgets/<name>/widget.js` (metadata: `api` URL template, `proxyHandler`, `mappings`/`allowedEndpoints`) + `component.jsx` (renders `Block`s). Registered in `widgets.js` + `components.js`. Configured by users in `services.yaml`. ([tutorial](https://gethomepage.dev/widgets/authoring/tutorial/), [widgets docs](https://gethomepage.dev/widgets/), [repo](https://github.com/gethomepage/homepage)) | `widget.js` declares which endpoint(s) to hit; component pulls a handful of fields into labeled `Block`s with localized number formatting. | "Add a folder with 2 files, register in 2 arrays alphabetically." Very close to our registry story. | **The split of *metadata file* (declares endpoint + mapping) from *render* (small fixed set of stat blocks). Our `ServiceIntegration` fuses both but keeps the same shape: declare endpoint/auth as data, map to a few labeled stats.** A server-side **proxy** also hides secrets from the client, analogous to us keeping secrets in Keychain, not in synced config. |
| **Homarr** (`homarr-labs`) | **Integration = ready-made widget + credential manager**; 40+ apps. No YAML. UI-driven; API keys **encrypted at rest** and injected at runtime via a Secrets manager. ([docs](https://homarr.dev/docs/category/integrations/), [repo](https://github.com/homarr-labs/homarr)) | Each integration knows its app's API and surfaces app-specific widgets. | Code-level integrations (TypeScript), added per-app. | **Encrypt/secure secrets separate from config + inject at runtime** → our Keychain-keyed-by-UUID model. UI-driven add flow (no hand-edited config) → our generated form. |
| **Dashy** | Widgets defined in `conf.yml`; large catalog of pre-built widgets + a generic **`custom` widget** that maps an arbitrary endpoint via options. | YAML options pick fields. | YAML + docs. | **The "generic custom-HTTP widget as escape hatch"** → our optional `CustomHTTPIntegration`. |
| **Glance** | YAML `glance.yml`; widgets incl. a generic `custom-api` widget with a Go-template to extract fields. | Template extracts/format fields. | YAML. | **Confirms the two-tier idea: first-class typed widgets *plus* one generic templated widget.** |
| **Heimdall** | "Enhanced apps", a fixed registry of app classes; each maps its API to a couple of live stats; everything else is just a link tile. | Per-app class. | Add a PHP app class. | **Graceful degradation: a service with no/failed integration still shows as a launchable tile** → our `health == .unknown` + link-only fallback. |

Net takeaways for a native app:

1. **Declare endpoint + mapping as data; render a small fixed set of labeled
   stats.** (Homepage)
2. **Secrets live apart from config and are injected at runtime.** (Homarr)
3. **Ship typed integrations *plus* one generic custom-HTTP escape hatch.**
   (Dashy/Glance)
4. **Always degrade to a plain link tile when monitoring is absent/down.**
   (Heimdall)
5. **Keep "add a service" to: one isolated unit + one registration line.**
   (Homepage)

---

## 3. The uniform metrics / health model

Pure value types in `ReeveModels`. Everything is `Codable` + `Sendable` so it
caches to disk, crosses the App Group boundary, and feeds WidgetKit timeline
entries with no conversion.

```swift
public enum Health: String, Codable, Sendable, CaseIterable {
    case ok, warn, down, unknown
}

/// One labeled metric. `value` is pre-formatted for display; keep `raw` for
/// sorting/threshold logic and for widgets that re-format compactly.
public struct Stat: Codable, Sendable, Identifiable, Hashable {
    public var id: String          // stable key, e.g. "queries_blocked"
    public var label: String       // "Blocked today"
    public var value: String       // "12,431", already localized by the integration
    public var unit: String?       // "%", "GB", "ms" (nil if baked into value)
    public var raw: Double?         // optional numeric for charts/thresholds
    public var emphasis: Emphasis  // .normal / .highlighted (drives the hero stats)

    public enum Emphasis: String, Codable, Sendable { case normal, highlighted }
}

/// An optional free-form key/value row for the detail screen.
public struct DetailRow: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var value: String
}

/// The uniform result EVERY integration returns. The list shows `health` +
/// highlighted `stats`; the detail shows all `stats` + `details`.
public struct ServiceStatus: Codable, Sendable, Hashable {
    public var health: Health
    public var summary: String?        // one-line ("3 of 4 monitors up")
    public var stats: [Stat]           // ordered; mark 1–3 .highlighted
    public var details: [DetailRow]    // extra rows for the detail screen
    public var fetchedAt: Date
    public var version: String?        // server version if cheaply available

    public init(
        health: Health,
        summary: String? = nil,
        stats: [Stat] = [],
        details: [DetailRow] = [],
        fetchedAt: Date = .now,
        version: String? = nil
    ) {
        self.health = health; self.summary = summary; self.stats = stats
        self.details = details; self.fetchedAt = fetchedAt; self.version = version
    }
}

/// What the UI actually binds to per instance (status or the error).
public enum ServiceState: Codable, Sendable {
    case loading
    case loaded(ServiceStatus)
    case failed(message: String, at: Date)   // keep stale-but-shown UX simple
}
```

Design notes:

- **Integration formats the display string** (locale, units) because only it
  knows the semantics; `raw` is retained for sortable widgets/charts. This avoids
  a giant shared "unit system" enum while keeping numbers available.
- **`emphasis`** lets the generic list pick 1–3 hero numbers without the
  integration needing to know about layout.
- **Codable end-to-end** → the same value is the cache record *and* the
  `TimelineEntry` payload. No widget-specific DTOs.
- **`fetchedAt`** drives "Updated 2m ago" and staleness styling generically.

---

## 4. Per-integration networking

### 4.1 One injected client, many request builders

Each service differs only in (a) how it authenticates and (b) how it shapes a
request and decodes a response. Capture (a) as data and give every integration a
shared client to do (b).

```swift
public struct HTTPRequest: Sendable {
    public var method: String = "GET"
    public var url: URL
    public var headers: [String: String] = [:]
    public var body: Data? = nil
}

/// Injected into every integration. Live impl wraps URLSession; tests inject a
/// mock (or use the existing URLProtocol mock). Mirrors the ProxmoxAPI protocol
/// pattern already in the repo.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest, tls: TLSPolicy) async throws -> (Data, HTTPURLResponse)
}

public extension HTTPClient {
    /// Convenience: send + status check + JSON decode in one call.
    func getJSON<T: Decodable>(
        _ type: T.Type, from request: HTTPRequest, tls: TLSPolicy
    ) async throws -> T {
        let (data, response) = try await send(request, tls: tls)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.badStatus(response.statusCode,
                                     body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }
}
```

`LiveHTTPClient` reuses the existing self-signed-cert handling
(`ProxmoxTrustDelegate` / `TLSPolicy`) so homelab TLS quirks are solved once for
all services, homelab services are overwhelmingly self-signed too.

### 4.2 Auth as data

```swift
public enum AuthMethod: Sendable, Codable, Hashable {
    case none
    case bearer                       // Authorization: Bearer <secret>
    case basic(usernameField: String) // Authorization: Basic base64(user:secret)
    case header(name: String)         // <name>: <secret>   e.g. X-Emby-Token
    case queryItem(name: String)      // ?<name>=<secret>
    case sessionToken                 // login → SID → reuse (Pi-hole v6)
    case custom                       // integration builds it entirely itself
}
```

A tiny helper applies `bearer` / `basic` / `header` / `queryItem` to an
`HTTPRequest`, so most integrations write zero auth code. Stateful/handshake auth
(`sessionToken`, socket.io) is `case custom` / `case sessionToken` and the
integration owns it (see §7 Pi-hole / Uptime Kuma).

### 4.3 Testability

- Every integration takes `client: HTTPClient` → inject a stub returning canned
  JSON. Assert the produced `ServiceStatus` (`health`, specific `Stat`s).
- For an end-to-end path test, point `LiveHTTPClient` at the repo's existing
  `MockURLProtocol` (`Tests/.../MockURLProtocol.swift`) so the real `URLSession`
  code path runs offline. This is the Apple-endorsed approach to network testing.
  ([URLProtocol](https://developer.apple.com/documentation/foundation/urlprotocol),
  [Hacking with Swift: testing networking](https://www.hackingwithswift.com/articles/153/how-to-test-ios-networking-code-the-easy-way),
  [Donny Wals: mocking a network connection](https://www.donnywals.com/mocking-a-network-connection-in-your-swift-tests/))
- Because integrations are `Sendable` value types with no hidden state, each test
  is independent and parallelizable under Swift Testing.

---

## 5. Config & secrets

### 5.1 The configured instance

```swift
public struct ServiceInstance: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var typeID: String                 // -> ServiceCatalog.integration(for:)
    public var name: String                   // user label ("Living-room Pi-hole")
    public var baseURLString: String
    public var tlsPolicy: TLSPolicy
    /// Non-secret config values keyed by ConfigField.key (e.g. username, port).
    public var config: [String: String]
    public var isEnabled: Bool

    public var baseURL: URL? { URL(string: baseURLString) }
    // The secret is NOT here, it is in the Keychain, keyed by `id`.
}
```

Stored as a JSON array in **App Group `UserDefaults`** (so the app, the macOS
menu-bar extension, and the widget all read the same list). This is exactly the
`ServerProfile` pattern, generalized: profile-without-secret in defaults, secret
in Keychain keyed by the instance `UUID`.

### 5.2 Secrets

Reuse `KeychainStore` verbatim, it already stores a string secret per `UUID`
with an `accessGroup` for App-Group sharing
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, good for background widget
refresh). Use a distinct `service` string (e.g. `com.homelabmonitor.services`)
to keep service secrets namespaced apart from Proxmox token secrets. No new
crypto code. (Apple Keychain Services:
<https://developer.apple.com/documentation/security/keychain-services>.)

### 5.3 Generic "Add service" form from the schema

The config schema is data, so one SwiftUI form renders any service:

```swift
public struct ConfigField: Identifiable, Codable, Sendable, Hashable {
    public var id: String { key }
    public var key: String          // stored into ServiceInstance.config[key]
    public var label: String        // "Username"
    public var kind: Kind           // drives the control + keyboard + secure entry
    public var placeholder: String?
    public var defaultValue: String?
    public var isRequired: Bool

    public enum Kind: String, Codable, Sendable {
        case text, url, number, port, toggle, secret
    }
}
```

`AddServiceView` flow: pick a type from `ServiceCatalog` → render `name`,
`baseURL`, TLS picker, then one control per `configFields` entry, plus a secure
field iff `authMethod != .none`. `.secret`-kind values and the auth secret go to
`KeychainStore`; everything else to `ServiceInstance.config`. **No integration
ships any SwiftUI.**

---

## 6. Contributor ergonomics, the end-to-end story

> **To add a service:** create `Integrations/<Name>Integration.swift` conforming
> to `ServiceIntegration`, then add one line to `ServiceCatalog.builtIn`. Add a
> test with canned JSON. Done, the picker, add-form, list row, detail screen,
> caching, and widget all work automatically.

### Worked example: AdGuard Home (`GET /control/stats`, Basic auth)

AdGuard Home's REST API lives under `/control`; if password protection is on it
uses HTTP Basic auth, and dashboards read `/control/stats` for the headline
numbers. ([OpenAPI spec](https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml),
[REST API reference](https://deepwiki.com/AdguardTeam/AdGuardHome/9.1-rest-api-reference))

```swift
import Foundation
import ReeveModels

public struct AdGuardHomeIntegration: ServiceIntegration {
    public static let typeID = "adguard-home"

    public let displayName = "AdGuard Home"
    public let category: ServiceCategory = .dns
    public let iconAsset: ServiceIcon = .symbol("shield.lefthalf.filled")
    public let authMethod: AuthMethod = .basic(usernameField: "username")

    public var configFields: [ConfigField] {
        [ ConfigField(key: "username", label: "Username",
                      kind: .text, isRequired: true) ]
        // password is the Keychain secret; URL + TLS are part of the base form.
    }

    public init() {}

    // Matches GET /control/stats
    private struct Stats: Decodable {
        let num_dns_queries: Int
        let num_blocked_filtering: Int
        let avg_processing_time: Double      // seconds
    }

    public func fetchStatus(
        for instance: ServiceInstance,
        secret: String?,
        client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        var req = HTTPRequest(url: base.appendingPathComponent("control/stats"))

        // Basic auth from username (config) + password (secret).
        if let user = instance.config["username"], let pass = secret,
           let token = "\(user):\(pass)".data(using: .utf8)?.base64EncodedString() {
            req.headers["Authorization"] = "Basic \(token)"
        }

        let s = try await client.getJSON(Stats.self, from: req, tls: instance.tlsPolicy)
        let blockPct = s.num_dns_queries > 0
            ? Double(s.num_blocked_filtering) / Double(s.num_dns_queries) * 100 : 0

        return ServiceStatus(
            health: .ok,
            summary: "\(s.num_blocked_filtering) blocked today",
            stats: [
                Stat(id: "blocked", label: "Blocked", value: "\(s.num_blocked_filtering)",
                     unit: nil, raw: Double(s.num_blocked_filtering), emphasis: .highlighted),
                Stat(id: "block_pct", label: "Block rate",
                     value: String(format: "%.1f", blockPct), unit: "%",
                     raw: blockPct, emphasis: .highlighted),
                Stat(id: "queries", label: "Queries", value: "\(s.num_dns_queries)",
                     unit: nil, raw: Double(s.num_dns_queries), emphasis: .normal),
                Stat(id: "latency", label: "Avg latency",
                     value: String(format: "%.0f", s.avg_processing_time * 1000),
                     unit: "ms", raw: s.avg_processing_time * 1000, emphasis: .normal),
            ]
        )
    }
}
```

Register it (the only edit outside the new file):

```swift
public static let builtIn = ServiceCatalog([
    AdGuardHomeIntegration(),   // ← added
    // …
])
```

Test it offline:

```swift
@Test func adguardMapsStats() async throws {
    let json = #"{"num_dns_queries":1000,"num_blocked_filtering":250,"avg_processing_time":0.012}"#
    let client = StubHTTPClient(data: Data(json.utf8))
    let status = try await AdGuardHomeIntegration().fetchStatus(
        for: .init(id: UUID(), typeID: "adguard-home", name: "Pi",
                   baseURLString: "http://10.0.0.2", tlsPolicy: .allowInsecure,
                   config: ["username": "admin"], isEnabled: true),
        secret: "pw", client: client)
    #expect(status.health == .ok)
    #expect(status.stats.first { $0.id == "block_pct" }?.value == "25.0")
}
```

That is the entire surface area for a contributor.

### Feature/view-model glue (built once, in `ReeveFeatures`)

```swift
@MainActor @Observable
public final class ServicesModel {
    public private(set) var states: [UUID: ServiceState] = [:]
    private let catalog: ServiceCatalog
    private let store: ServiceInstanceStore
    private let keychain: KeychainStore
    private let client: HTTPClient

    public init(catalog: ServiceCatalog = .builtIn, store: ServiceInstanceStore,
                keychain: KeychainStore, client: HTTPClient) {
        self.catalog = catalog; self.store = store
        self.keychain = keychain; self.client = client
    }

    public func refresh(_ instance: ServiceInstance) async {
        guard let integration = catalog.integration(for: instance.typeID) else {
            states[instance.id] = .failed(message: "Unknown service type", at: .now); return
        }
        states[instance.id] = .loading
        do {
            let secret = keychain.secret(for: instance.id)
            let status = try await integration.fetchStatus(
                for: instance, secret: secret, client: client)
            states[instance.id] = .loaded(status)
            try? store.cache(status, for: instance.id)   // App Group, for widgets
        } catch {
            states[instance.id] = .failed(
                message: (error as? LocalizedError)?.errorDescription
                          ?? error.localizedDescription, at: .now)
        }
    }

    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for instance in store.instances where instance.isEnabled {
                group.addTask { await self.refresh(instance) }
            }
        }
    }
}
```

`@Observable` + `@MainActor` matches the existing `DashboardModel`; the concurrent
`withTaskGroup` fan-out gives parallel refresh for free, and each integration's
`Sendable`-ness makes that safe under Swift 6.
([Apple: Observable](https://developer.apple.com/documentation/Observation),
[Apple: Sendable](https://developer.apple.com/documentation/swift/sendable),
[Swift.org: protocol-oriented programming](https://www.swift.org/documentation/api-design-guidelines/)).

---

## 7. Starter set: endpoints + auth for reference integrations

One or two cheap monitoring endpoints + the auth header for each. Verify exact
field names against each project's current OpenAPI/docs when implementing.

| Service | Endpoint(s) | Auth | Headline stats | Notes / source |
|---|---|---|---|---|
| **AdGuard Home** | `GET /control/stats` (also `GET /control/status`) | HTTP **Basic** (`Authorization: Basic base64(user:pass)`) | queries, blocked, block %, avg latency | `/control` base path; Basic auth when protected. ([OpenAPI](https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml)) |
| **Jellyfin** | `GET /System/Info` (health/version); `GET /Sessions` (active streams) | API key in header **`X-Emby-Token: <key>`** (or `Authorization: MediaBrowser Token="…"`) | version, active sessions, transcodes | API key created in dashboard. ([auth gist](https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f), [API overview](https://jmshrv.com/posts/jellyfin-api/)) |
| **TrueNAS SCALE** | `GET /api/v2.0/system/info`; `GET /api/v2.0/pool` | **Bearer** API key (`Authorization: Bearer <key>`) | uptime, version, pool health/usage | REST v2.0 (25.04+ also exposes JSON-RPC over WebSocket). ([API hub](https://www.truenas.com/docs/scale/api/)) |
| **Home Assistant** | `GET /api/` (ping); `GET /api/states` or `/api/states/<entity_id>` | **Bearer** long-lived access token | entity states, # entities, version | Token from user profile page; `Authorization: Bearer <token>`. ([REST API docs](https://developers.home-assistant.io/docs/api/rest/)) |
| **Uptime Kuma** | `GET /metrics` (Prometheus text) | HTTP **Basic** (user:pass) until first API key, then **API-key** Basic auth | monitors up/down, response time, cert days, uptime ratio | No clean per-monitor REST/JSON; parse Prometheus gauges (`monitor_status`, `monitor_response_time`, `monitor_cert_days_remaining`). socket.io is the realtime channel but heavy, start with `/metrics`. ([Prometheus integration wiki](https://github.com/louislam/uptime-kuma/wiki/Prometheus-Integration)) |
| **Pi-hole v6** | `POST /api/auth` → SID, then `GET /api/stats/summary` (send `sid`) | **Session token**: POST app-password → get `SID`, pass it on subsequent calls; SID expires on inactivity | queries, blocked, block %, domains on lists | v6 replaced the old `?auth=` token; integration owns the login→SID handshake (`AuthMethod.sessionToken`). ([API docs](https://docs.pi-hole.net/api/), [auth](https://docs.pi-hole.net/api/auth/)) |

Implementation order suggestion: AdGuard Home and Home Assistant first (simple
single-call + simple header) to validate the abstraction, then TrueNAS/Jellyfin
(header variants), then Uptime Kuma (non-JSON parsing) and Pi-hole v6 (stateful
session) to prove `custom`/`sessionToken` auth and the degradation paths.

---

## 8. Open items / future

- **Generic `CustomHTTPIntegration`**: one conformer that reads a small JSON
  field-mapping from `ServiceInstance.config`, gives users the Dashy/Glance
  "custom-api" escape hatch without making the whole system data-driven.
- **Capabilities beyond status**: extend the protocol with optional capability
  protocols (e.g. `ServiceActions` for power/restart, `ServiceHistory` for charts)
  so integrations opt in à la carte without bloating the base protocol: this is
  capability-based composition, the same way `ProxmoxAPI` already separates read
  vs. power.
- **Health thresholds**: let integrations return `health` directly (they own
  semantics); optionally allow user-tunable warn/down thresholds on a named `Stat`
  via `raw`.
- **WidgetKit**: the cached `ServiceStatus` is already `Codable`/`Sendable`, so a
  timeline provider just reads the App Group cache, no extra modeling.

## Sources

- Homepage, [widget authoring tutorial](https://gethomepage.dev/widgets/authoring/tutorial/), [widgets](https://gethomepage.dev/widgets/), [repo](https://github.com/gethomepage/homepage)
- Homarr, [integrations docs](https://homarr.dev/docs/category/integrations/), [repo](https://github.com/homarr-labs/homarr)
- AdGuard Home, [OpenAPI](https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml), [REST reference](https://deepwiki.com/AdguardTeam/AdGuardHome/9.1-rest-api-reference)
- Jellyfin, [API auth gist](https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f), [API overview](https://jmshrv.com/posts/jellyfin-api/)
- TrueNAS SCALE, [API reference hub](https://www.truenas.com/docs/scale/api/)
- Home Assistant, [REST API](https://developers.home-assistant.io/docs/api/rest/)
- Uptime Kuma, [Prometheus integration](https://github.com/louislam/uptime-kuma/wiki/Prometheus-Integration)
- Pi-hole, [API docs](https://docs.pi-hole.net/api/), [auth](https://docs.pi-hole.net/api/auth/)
- Apple, [Observation](https://developer.apple.com/documentation/Observation), [Sendable](https://developer.apple.com/documentation/swift/sendable), [URLProtocol](https://developer.apple.com/documentation/foundation/urlprotocol), [Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- Swift architecture, [Swift.org API design guidelines](https://www.swift.org/documentation/api-design-guidelines/), [Hacking with Swift: testing networking](https://www.hackingwithswift.com/articles/153/how-to-test-ios-networking-code-the-easy-way), [Donny Wals: mocking network connections](https://www.donnywals.com/mocking-a-network-connection-in-your-swift-tests/)
