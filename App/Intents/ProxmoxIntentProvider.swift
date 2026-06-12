import Foundation
import ReeveModels
import ReeveNetworking
import ReevePersistence

/// Builds Proxmox connections off the main actor (App Intents run in the
/// background), mirroring `ProfileStore.connection(for:)` without touching the
/// `@MainActor` store. All inputs are `Sendable`.
nonisolated struct IntentProfileResolver: Sendable {
    private let keychain = KeychainStore()
    private let storageKey = "homelab.serverProfiles"

    func profiles() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data)
        else { return [] }
        return decoded
    }

    func profile(id: String) -> ServerProfile? {
        profiles().first { $0.id.uuidString == id }
    }

    func connection(for profile: ServerProfile) -> ServerConnection? {
        if profile.isDemo { return profile.connection(secret: "demo") }
        guard let secret = keychain.secret(for: profile.id) else { return nil }
        return profile.connection(secret: secret)
    }
}

/// The App Intents dependency: a shared Proxmox client plus guest enumeration and
/// connection resolution. Registered once in `ReeveApp.init` via
/// `AppDependencyManager` so every intent/query reaches it with `@Dependency`.
nonisolated final class ProxmoxIntentProvider: Sendable {
    let api: ProxmoxAPI
    private let resolver = IntentProfileResolver()

    init(api: ProxmoxAPI = DemoProxmoxAPI(live: LiveProxmoxAPI())) {
        self.api = api
    }

    var serverCount: Int { resolver.profiles().count }

    /// Every non-template guest across all configured servers, as entities.
    /// Servers are queried concurrently so one unreachable server can't blow the
    /// App Intent's short time budget (a slow server only delays its own results).
    func allGuests() async -> [GuestEntity] {
        await withTaskGroup(of: [GuestEntity].self) { group in
            for profile in resolver.profiles() {
                group.addTask {
                    guard let conn = self.resolver.connection(for: profile),
                          let resources = try? await self.api.clusterResources(conn) else { return [] }
                    return resources.compactMap { GuestEntity(resource: $0, profile: profile) }
                }
            }
            var result: [GuestEntity] = []
            for await chunk in group { result.append(contentsOf: chunk) }
            return result
        }
    }

    /// Resolve an entity to the connection + addressing an action needs.
    func target(
        for guest: GuestEntity
    ) -> (conn: ServerConnection, node: String, kind: GuestKind, vmid: Int)? {
        guard let profile = resolver.profile(id: guest.profileID),
              let conn = resolver.connection(for: profile) else { return nil }
        return (conn, guest.node, guest.kind.guestKind, guest.vmid)
    }

    /// Offline fallback: rebuild a minimal entity from its encoded id.
    func reconstruct(id: String) -> GuestEntity? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let vmid = Int(parts[3]) else { return nil }
        let kind: GuestKindOption = parts[2] == "lxc" ? .container : .vm
        let serverName = resolver.profile(id: parts[0])?.name ?? "Server"
        return GuestEntity(
            id: id, profileID: parts[0], node: parts[1], vmid: vmid, kind: kind,
            name: "\(kind == .container ? "Container" : "VM") \(vmid)",
            status: .unknown, cpuPercent: 0, serverName: serverName
        )
    }
}
