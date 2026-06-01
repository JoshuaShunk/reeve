import Foundation
import ReeveModels

/// Demo data for the Services tab. A handful of `ServiceInstance`s plus a
/// `ServiceCatalog.demo` whose integrations return canned `ServiceStatus` values,
/// so the Services tab is fully populated in Demo Mode without any network calls.
/// Display names and logos still come from `ServiceCatalog.builtIn` (the UI looks
/// them up by `typeID`), so these stubs only need the right id + a canned status.
public enum DemoServices {
    /// Stable ids so the keychain/store stay consistent across launches.
    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: "DE505E00-0000-0000-0000-0000000000\(String(format: "%02d", n))")!
    }

    public static func instances() -> [ServiceInstance] {
        func make(_ n: Int, _ typeID: String, _ name: String) -> ServiceInstance {
            ServiceInstance(id: id(n), typeID: typeID, name: name,
                            baseURLString: "https://\(DemoMode.host)")
        }
        return [
            make(1, "adguard-home", "AdGuard Home"),
            make(2, "immich", "Immich"),
            make(3, "uptime-kuma", "Uptime Kuma"),
            make(4, "jellyfin", "Jellyfin"),
            make(5, "qbittorrent", "qBittorrent"),
        ]
    }

    /// Canned status keyed by service type.
    public static func status(for typeID: String) -> ServiceStatus {
        switch typeID {
        case "adguard-home":
            return ServiceStatus(
                health: .ok, summary: "19,066 blocked today",
                stats: [
                    Stat(id: "blocked", label: "Blocked", value: "19,066", raw: 19066, emphasis: .highlighted),
                    Stat(id: "rate", label: "Block rate", value: "24.6", unit: "%", raw: 24.6, emphasis: .highlighted),
                    Stat(id: "queries", label: "Queries", value: "77,412", raw: 77412),
                ], version: "v0.107.52")
        case "immich":
            return ServiceStatus(
                health: .ok, summary: "42,318 photos · 1.2 TB",
                stats: [
                    Stat(id: "photos", label: "Photos", value: "42,318", raw: 42318, emphasis: .highlighted),
                    Stat(id: "videos", label: "Videos", value: "3,104", raw: 3104, emphasis: .highlighted),
                    Stat(id: "disk", label: "Disk used", value: "61", unit: "%", raw: 61),
                ], version: "v1.106.4")
        case "uptime-kuma":
            return ServiceStatus(
                health: .warn, summary: "11/12 monitors up",
                stats: [
                    Stat(id: "up", label: "Up", value: "11", raw: 11, emphasis: .highlighted),
                    Stat(id: "down", label: "Down", value: "1", raw: 1, emphasis: .highlighted),
                ])
        case "jellyfin":
            return ServiceStatus(
                health: .ok, summary: "2 streaming now",
                stats: [
                    Stat(id: "streams", label: "Streams", value: "2", raw: 2, emphasis: .highlighted),
                ], version: "10.9.11")
        case "qbittorrent":
            return ServiceStatus(
                health: .ok, summary: "↓ 8.4 MB/s · 3 active",
                stats: [
                    Stat(id: "dl", label: "Download", value: "8.4 MB/s", raw: 8_400_000, emphasis: .highlighted),
                    Stat(id: "up", label: "Upload", value: "1.2 MB/s", raw: 1_200_000, emphasis: .highlighted),
                    Stat(id: "torrents", label: "Torrents", value: "42", raw: 42),
                ], version: "v5.0.3")
        default:
            return ServiceStatus(health: .ok, summary: "Demo service")
        }
    }
}

// Thin per-type integrations. Distinct types are required because `ServiceCatalog`
// keys on the static `typeID`; each just returns the canned status for its id.
private protocol DemoServiceIntegration: ServiceIntegration {}
extension DemoServiceIntegration {
    public var displayName: String { Self.typeID }
    public var category: ServiceCategory { .other }
    public var iconAsset: ServiceIcon { .symbol("square.grid.2x2") }
    public var authMethod: AuthMethod { .none }
    public var configFields: [ConfigField] { [] }
    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        DemoServices.status(for: Self.typeID)
    }
}

public struct DemoAdGuardService: DemoServiceIntegration { public static let typeID = "adguard-home"; public init() {} }
public struct DemoImmichService: DemoServiceIntegration { public static let typeID = "immich"; public init() {} }
public struct DemoUptimeKumaService: DemoServiceIntegration { public static let typeID = "uptime-kuma"; public init() {} }
public struct DemoJellyfinService: DemoServiceIntegration { public static let typeID = "jellyfin"; public init() {} }
public struct DemoQBittorrentService: DemoServiceIntegration { public static let typeID = "qbittorrent"; public init() {} }

extension ServiceCatalog {
    /// The catalog used by the Services tab in Demo Mode.
    public static let demo = ServiceCatalog([
        DemoAdGuardService(), DemoImmichService(), DemoUptimeKumaService(),
        DemoJellyfinService(), DemoQBittorrentService(),
    ])
}
