import Foundation
import ReeveModels

/// A *type* of self-hosted service the app can monitor (Jellyfin, AdGuard, …).
/// Stateless and `Sendable`: it declares its identity, config schema, and auth as
/// data, and implements a single `fetchStatus` that maps the service's API onto
/// the uniform `ServiceStatus`. Adding a service = one file conforming to this +
/// one line in `ServiceCatalog.builtIn`.
public protocol ServiceIntegration: Sendable {
    /// Stable dns-style id persisted in `ServiceInstance.typeID`. Never rename
    /// once shipped (migrate instead). e.g. "adguard-home".
    static var typeID: String { get }

    var displayName: String { get }
    var category: ServiceCategory { get }
    var iconAsset: ServiceIcon { get }
    var authMethod: AuthMethod { get }
    var configFields: [ConfigField] { get }
    /// dashboard-icons slug for the real logo (defaults to the typeID). The UI
    /// loads `…/dashboard-icons/png/<iconSlug>.png` and falls back to `iconAsset`.
    var iconSlug: String { get }

    func fetchStatus(
        for instance: ServiceInstance,
        secret: String?,
        client: HTTPClient
    ) async throws -> ServiceStatus
}

extension ServiceIntegration {
    /// Instance-side convenience.
    public var typeID: String { Self.typeID }
    /// Default logo slug = the type id (chosen to match dashboard-icons slugs).
    public var iconSlug: String { Self.typeID }
}

/// The set of integrations the app knows about. The only place a contributor
/// edits besides their own new file.
public struct ServiceCatalog: Sendable {
    public let integrations: [any ServiceIntegration]
    private let byID: [String: any ServiceIntegration]

    public init(_ integrations: [any ServiceIntegration]) {
        self.integrations = integrations
        self.byID = Dictionary(
            integrations.map { (Swift.type(of: $0).typeID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func integration(for typeID: String) -> (any ServiceIntegration)? {
        byID[typeID]
    }

    /// Built-in reference integrations. ADD YOUR INTEGRATION HERE.
    public static let builtIn = ServiceCatalog([
        AdGuardHomeIntegration(),
        JellyfinIntegration(),
        PlexIntegration(),
        HomeAssistantIntegration(),
        TrueNASIntegration(),
        ProxmoxBackupServerIntegration(),
        NextcloudIntegration(),
        SonarrIntegration(),
        RadarrIntegration(),
        ProwlarrIntegration(),
        JellyseerrIntegration(),
        OverseerrIntegration(),
        PortainerIntegration(),
        GrafanaIntegration(),
        UptimeKumaIntegration(),
    ])
}
