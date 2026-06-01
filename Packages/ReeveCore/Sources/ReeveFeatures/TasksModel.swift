import Foundation
import ReeveModels
import ReeveNetworking
import Observation

/// Lists a node's recent and running tasks, and fetches a task's log.
@MainActor
@Observable
public final class TasksModel {
    public private(set) var tasks: [ProxmoxTaskInfo] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let api: ProxmoxAPI
    private let connection: ServerConnection
    public let node: String

    public init(api: ProxmoxAPI, connection: ServerConnection, node: String) {
        self.api = api
        self.connection = connection
        self.node = node
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await api.tasks(connection, node: node, limit: 50, vmid: nil)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func log(for task: ProxmoxTaskInfo) async throws -> [TaskLogLine] {
        try await api.taskLog(connection, node: node, upid: task.upid, limit: 500)
    }
}
