import Foundation
import ReeveModels
import ReeveNetworking
import Observation

/// Drives the main dashboard for a single server connection: fetches
/// `/cluster/resources`, splits it into nodes / guests / storage, and exposes
/// power controls. UI-agnostic and `@MainActor`, so SwiftUI can observe it
/// directly and tests can poke it without a UI.
@MainActor
@Observable
public final class DashboardModel {
    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var state: LoadState = .idle
    public private(set) var resources: [ClusterResource] = []
    public private(set) var recentTasks: [ProxmoxTaskInfo] = []
    public private(set) var lastUpdated: Date?

    private let api: ProxmoxAPI
    private let connection: ServerConnection
    private let now: @Sendable () -> Date

    public init(
        api: ProxmoxAPI,
        connection: ServerConnection,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.connection = connection
        self.now = now
    }

    // MARK: - Derived views of the resource list

    public var nodes: [ClusterResource] {
        resources.filter { $0.type == .node }
    }

    public var guests: [ClusterResource] {
        resources
            .filter { ($0.type == .qemu || $0.type == .lxc) && !$0.isTemplate }
            .sorted { ($0.vmid ?? 0) < ($1.vmid ?? 0) }
    }

    public var storages: [ClusterResource] {
        resources.filter { $0.type == .storage }
    }

    public var runningGuestCount: Int {
        guests.filter { $0.status?.isUp == true }.count
    }

    // MARK: - Loading

    public func refresh() async {
        if state != .loaded { state = .loading }
        do {
            resources = try await api.clusterResources(connection)
            // Best-effort recent tasks per node (drives the activity log and
            // task-completion notifications). A failure here must not fail the
            // whole dashboard.
            var tasks: [ProxmoxTaskInfo] = []
            for node in nodes {
                guard let name = node.node else { continue }
                if let t = try? await api.tasks(connection, node: name, limit: 50, vmid: nil) {
                    tasks.append(contentsOf: t)
                }
            }
            recentTasks = tasks
            lastUpdated = now()
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Poll on an interval until the surrounding `Task` is cancelled.
    public func autoRefresh(every seconds: Double) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    // MARK: - Power controls

    /// Issue a power action against a guest and refresh. Returns the task UPID.
    @discardableResult
    public func perform(
        _ action: PowerAction, on guest: ClusterResource
    ) async throws -> String {
        guard let node = guest.node, let vmid = guest.vmid,
              let kind = guest.type.guestKind
        else { throw APIError.invalidURL }
        let upid = try await api.power(
            connection, node: node, kind: kind, vmid: vmid, action: action
        )
        await refresh()
        return upid
    }
}

extension ResourceType {
    public var guestKind: GuestKind? {
        switch self {
        case .qemu: .qemu
        case .lxc: .lxc
        default: nil
        }
    }
}
