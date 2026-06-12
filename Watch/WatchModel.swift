import Foundation
import Observation
import ReeveModels
import ReeveNetworking
import ReevePersistence

/// Root state for the watch app: the synced profile store, a shared API client,
/// the WatchConnectivity receiver, and a cached `WatchServer` per profile.
@MainActor
@Observable
final class WatchModel {
    let profiles = ProfileStore()
    // Demo wrapper serves the canned dataset for the built-in demo profile and
    // forwards real servers to the live client, matching the iPhone app.
    let api: ProxmoxAPI = DemoProxmoxAPI(live: LiveProxmoxAPI())

    private(set) var servers: [WatchServer] = []

    @ObservationIgnored private var connectivity: WatchConnectivityManager?

    init() {
        // Mirror the iPhone's Demo Mode so the watch can be explored without a server.
        if ProcessInfo.processInfo.environment["REEVE_DEMO"] == "1" {
            profiles.seedDemoProfile()
        }
        let manager = WatchConnectivityManager(profiles: profiles)
        connectivity = manager
        rebuildServers()
        manager.onUpdate = { [weak self] in self?.rebuildServers() }
    }

    /// Rebuild the server list from the current profiles, preserving already-loaded
    /// `WatchServer` instances (and their fetched data) where the profile id matches.
    func rebuildServers() {
        var next: [WatchServer] = []
        for profile in profiles.profiles {
            if let existing = servers.first(where: { $0.id == profile.id }) {
                next.append(existing)
            } else if let connection = profiles.connection(for: profile) {
                next.append(WatchServer(profile: profile, api: api, connection: connection))
            }
        }
        servers = next
        WatchWidgetSync.refreshDirectory(profiles.profiles)
    }

    func server(withID id: UUID) -> WatchServer? {
        servers.first { $0.id == id }
    }

    func requestSync() {
        connectivity?.requestSync()
    }
}
