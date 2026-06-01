import Foundation
import ReeveModels
import ReeveNetworking
import Observation

/// Lists and manages a guest's snapshots. Create / rollback / delete are async
/// Proxmox tasks, so each is issued then polled to completion before reloading.
@MainActor
@Observable
public final class SnapshotsModel {
    public private(set) var snapshots: [Snapshot] = []
    public private(set) var isLoading = false
    /// Non-nil while an operation runs (drives a progress overlay + disables UI).
    public private(set) var busyMessage: String?
    public var errorMessage: String?

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

    /// Real snapshots (excludes the `current` pseudo-entry), newest first.
    public var listed: [Snapshot] {
        snapshots
            .filter { !$0.isCurrent }
            .sorted { ($0.snaptime ?? 0) > ($1.snaptime ?? 0) }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshots = try await api.snapshots(connection, node: node, kind: kind, vmid: vmid)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    public func create(name: String, description: String, includeRAM: Bool) async {
        await runTask("Creating snapshot…") {
            try await self.api.createSnapshot(
                self.connection, node: self.node, kind: self.kind, vmid: self.vmid,
                name: name, description: description, includeRAM: includeRAM
            )
        }
    }

    public func rollback(_ snapshot: Snapshot) async {
        await runTask("Rolling back…") {
            try await self.api.rollbackSnapshot(
                self.connection, node: self.node, kind: self.kind, vmid: self.vmid,
                name: snapshot.name
            )
        }
    }

    public func delete(_ snapshot: Snapshot) async {
        await runTask("Deleting snapshot…") {
            try await self.api.deleteSnapshot(
                self.connection, node: self.node, kind: self.kind, vmid: self.vmid,
                name: snapshot.name
            )
        }
    }

    private func runTask(_ message: String, _ operation: @Sendable () async throws -> String) async {
        busyMessage = message
        defer { busyMessage = nil }
        do {
            let upid = try await operation()
            try await waitForTask(upid)
            await load()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Poll a task UPID until it stops; throw on failure.
    private func waitForTask(_ upid: String) async throws {
        guard let parsed = UPID(upid) else { return }
        for _ in 0..<90 {
            let status = try await api.taskStatus(connection, node: parsed.node, upid: upid)
            if !status.isRunning {
                if let failure = status.failureMessage {
                    throw APIError.badStatus(500, body: failure)
                }
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    static func describe(_ error: Error) -> String {
        if case APIError.badStatus(403, _) = error {
            return "Permission denied. This API token needs the VM.Snapshot and "
                + "VM.Snapshot.Rollback privileges for snapshot management."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
