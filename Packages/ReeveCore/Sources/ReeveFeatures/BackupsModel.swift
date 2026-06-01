import Foundation
import ReeveModels
import ReeveNetworking
import Observation

/// Lists vzdump backups across a node's backup-capable storages.
@MainActor
@Observable
public final class BackupsModel {
    public private(set) var backups: [BackupFile] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let api: ProxmoxAPI
    private let connection: ServerConnection
    private let node: String
    private let storages: [String]

    public init(
        api: ProxmoxAPI, connection: ServerConnection, node: String, storages: [String]
    ) {
        self.api = api
        self.connection = connection
        self.node = node
        self.storages = storages
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        var collected: [BackupFile] = []
        for storage in storages {
            do {
                collected += try await api.backups(connection, node: node, storage: storage)
            } catch {
                // A single inaccessible storage shouldn't fail the whole list.
                if collected.isEmpty {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
        backups = collected.sorted { ($0.ctime ?? 0) > ($1.ctime ?? 0) }
    }
}
