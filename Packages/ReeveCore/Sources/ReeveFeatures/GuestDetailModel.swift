import Foundation
import ReeveModels
import ReeveNetworking
import Observation

/// Drives a single guest's detail screen: live status plus RRD time-series for
/// the charts, with a selectable timeframe.
@MainActor
@Observable
public final class GuestDetailModel {
    public private(set) var status: GuestStatus?
    public private(set) var history: [RRDPoint] = []
    public private(set) var config: GuestConfig?
    public private(set) var ipAddresses: [String] = []
    public private(set) var recentTasks: [ProxmoxTaskInfo] = []
    public private(set) var errorMessage: String?
    public var timeframe: RRDTimeframe = .hour {
        didSet { if timeframe != oldValue { Task { await loadHistory() } } }
    }

    private let api: ProxmoxAPI
    private let connection: ServerConnection
    public let node: String
    public let kind: GuestKind
    public let vmid: Int

    public init(
        api: ProxmoxAPI, connection: ServerConnection,
        node: String, kind: GuestKind, vmid: Int
    ) {
        self.api = api
        self.connection = connection
        self.node = node
        self.kind = kind
        self.vmid = vmid
    }

    public func load() async {
        await loadStatus()
        await loadHistory()
        await loadConfig()
        await loadTasks()
        await resolveIPs()
    }

    public func loadConfig() async {
        config = try? await api.guestConfig(connection, node: node, kind: kind, vmid: vmid)
    }

    public func loadTasks() async {
        recentTasks = (try? await api.tasks(connection, node: node, limit: 10, vmid: vmid)) ?? []
    }

    /// Containers expose IPs in their config; VMs need the guest agent (best effort).
    public func resolveIPs() async {
        var ips = config?.configuredIPs ?? []
        if kind == .qemu,
           let agent = try? await api.qemuAgentInterfaces(connection, node: node, vmid: vmid) {
            ips += agent.ipv4Addresses
        }
        ipAddresses = Array(Set(ips)).sorted()
    }

    public func loadStatus() async {
        do {
            status = try await api.guestStatus(
                connection, node: node, kind: kind, vmid: vmid
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadHistory() async {
        do {
            history = try await api.guestRRD(
                connection, node: node, kind: kind, vmid: vmid, timeframe: timeframe
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
