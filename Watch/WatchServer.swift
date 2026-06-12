import Foundation
import Observation
import ReeveModels
import ReeveNetworking
import ReevePersistence

/// A single monitored Proxmox server on the watch. Deliberately lighter than the
/// phone's `DashboardModel`: it makes one `cluster/resources` call (no per-node
/// task history) to stay fast and battery-friendly on the wrist, then derives the
/// node/guest summaries the watch UI shows.
@MainActor
@Observable
final class WatchServer: Identifiable {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    let id: UUID
    private(set) var profile: ServerProfile
    private let api: ProxmoxAPI
    private let connection: ServerConnection

    private(set) var state: LoadState = .idle
    private(set) var resources: [ClusterResource] = []
    private(set) var lastUpdated: Date?

    init(profile: ServerProfile, api: ProxmoxAPI, connection: ServerConnection) {
        self.id = profile.id
        self.profile = profile
        self.api = api
        self.connection = connection
    }

    private func guestKind(for type: ResourceType) -> GuestKind? {
        switch type {
        case .qemu: .qemu
        case .lxc: .lxc
        default: nil
        }
    }

    var nodes: [ClusterResource] {
        resources.filter { $0.type == .node }
    }

    var guests: [ClusterResource] {
        resources
            .filter { ($0.type == .qemu || $0.type == .lxc) && !$0.isTemplate }
            .sorted { lhs, rhs in
                let l = lhs.status?.isUp == true ? 0 : 1
                let r = rhs.status?.isUp == true ? 0 : 1
                if l != r { return l < r }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    /// Average node CPU as a 0...1 fraction (nil if no nodes loaded yet).
    var cpuFraction: Double? {
        let values = nodes.compactMap(\.cpu)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Aggregate memory used / total across nodes as a 0...1 fraction.
    var memoryFraction: Double? {
        let used = nodes.compactMap(\.mem).reduce(0, +)
        let total = nodes.compactMap(\.maxmem).reduce(0, +)
        guard total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    var guestsUp: Int { guests.filter { $0.status?.isUp == true }.count }
    var guestsTotal: Int { guests.count }

    var nodesOnline: Int { nodes.filter { $0.status?.isUp == true }.count }

    /// Overall health, driven by node reachability (guests are often intentionally off).
    var health: Health {
        if case .failed = state { return .down }
        guard !nodes.isEmpty else { return .unknown }
        let down = nodes.count - nodesOnline
        if down == nodes.count { return .down }
        if down > 0 { return .warn }
        return .ok
    }

    func refresh() async {
        if resources.isEmpty { state = .loading }
        do {
            resources = try await api.clusterResources(connection)
            lastUpdated = Date()
            state = .loaded
            WatchWidgetSync.write(
                profile: profile,
                cpuFraction: cpuFraction,
                memoryFraction: memoryFraction,
                guestsUp: guestsUp,
                guestsTotal: guestsTotal,
                health: health
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Issue a power action against a guest, then refresh. Returns the task UPID.
    @discardableResult
    func power(_ action: PowerAction, on guest: ClusterResource) async throws -> String {
        guard let node = guest.node, let vmid = guest.vmid,
              let kind = guestKind(for: guest.type) else {
            throw APIError.invalidURL
        }
        let upid = try await api.power(connection, node: node, kind: kind, vmid: vmid, action: action)
        await refresh()
        return upid
    }
}
