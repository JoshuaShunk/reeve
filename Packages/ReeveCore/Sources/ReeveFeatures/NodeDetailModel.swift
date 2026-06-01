import Foundation
import ReeveModels
import ReeveNetworking
import Observation

/// Drives the node detail screen: full node status plus RRD history for charts.
@MainActor
@Observable
public final class NodeDetailModel {
    public private(set) var status: NodeStatus?
    public private(set) var history: [RRDPoint] = []
    public var errorMessage: String?
    public var timeframe: RRDTimeframe = .hour {
        didSet { if timeframe != oldValue { Task { await loadHistory() } } }
    }

    private let api: ProxmoxAPI
    private let connection: ServerConnection
    public let node: String

    public init(api: ProxmoxAPI, connection: ServerConnection, node: String) {
        self.api = api
        self.connection = connection
        self.node = node
    }

    public func load() async {
        await loadStatus()
        await loadHistory()
    }

    public func loadStatus() async {
        do {
            status = try await api.nodeStatus(connection, node: node)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadHistory() async {
        do {
            history = try await api.nodeRRD(connection, node: node, timeframe: timeframe)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
