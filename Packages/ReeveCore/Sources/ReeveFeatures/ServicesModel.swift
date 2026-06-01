import Foundation
import ReeveModels
import ReeveNetworking
import ReevePersistence
import Observation

/// Drives the Services screen: fans out concurrent status fetches across all
/// configured instances and exposes per-instance state. UI-agnostic, `@MainActor`.
@MainActor
@Observable
public final class ServicesModel {
    public private(set) var states: [UUID: ServiceState] = [:]

    private let catalog: ServiceCatalog
    private let store: ServiceInstanceStore
    private let client: HTTPClient

    public init(
        catalog: ServiceCatalog = .builtIn,
        store: ServiceInstanceStore,
        client: HTTPClient = LiveHTTPClient()
    ) {
        self.catalog = catalog
        self.store = store
        self.client = client
        // Seed from cache so the UI shows last-known values immediately.
        for instance in store.instances {
            if let cached = store.cachedStatus(for: instance.id) {
                states[instance.id] = .loaded(cached)
            }
        }
    }

    public func state(for id: UUID) -> ServiceState {
        states[id] ?? .loading
    }

    public func refresh(_ instance: ServiceInstance) async {
        guard let integration = catalog.integration(for: instance.typeID) else {
            states[instance.id] = .failed(message: "Unknown service type", at: Date())
            return
        }
        if case .loaded = states[instance.id] {} else { states[instance.id] = .loading }
        let secret = store.secret(for: instance)
        do {
            let status = try await integration.fetchStatus(
                for: instance, secret: secret, client: client
            )
            states[instance.id] = .loaded(status)
            store.cache(status, for: instance.id)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            states[instance.id] = .failed(message: message, at: Date())
        }
    }

    /// Fetch the Uptime Kuma status page configured on this instance (by slug).
    public func uptimeKumaStatusPage(
        for instance: ServiceInstance
    ) async throws -> UptimeKumaStatusPage {
        guard let slug = instance.config["statusPageSlug"], !slug.isEmpty,
              let base = instance.baseURL else { throw APIError.invalidURL }
        return try await client.uptimeKumaStatusPage(
            slug: slug, baseURL: base, tls: instance.tlsPolicy
        )
    }

    public func refreshAll() async {
        let enabled = store.instances.filter(\.isEnabled)
        await withTaskGroup(of: Void.self) { group in
            for instance in enabled {
                group.addTask { await self.refresh(instance) }
            }
        }
    }
}
