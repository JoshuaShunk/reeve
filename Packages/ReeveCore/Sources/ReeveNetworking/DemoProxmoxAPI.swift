import Foundation
import ReeveModels

/// A `ProxmoxAPI` that serves the built-in `DemoDataset` for the magic
/// `DemoMode.host`, and transparently forwards every other connection to the real
/// `live` API. This single seam powers Demo Mode across the whole app (dashboard,
/// guest detail, charts, snapshots, backups, datacenter) without touching any
/// feature view-model.
///
/// Demo Mode satisfies App Store Review Guideline 2.1 (a fully-featured demo in
/// lieu of sharing real server credentials) and lets anyone try the app before
/// connecting their own Proxmox server.
public struct DemoProxmoxAPI: ProxmoxAPI {
    private let live: ProxmoxAPI

    public init(live: ProxmoxAPI = LiveProxmoxAPI()) { self.live = live }

    private func demo(_ conn: ServerConnection) -> Bool { DemoMode.isDemo(host: conn.host) }
    private var upid: String { DemoDataset.upid }

    // MARK: Reads

    public func version(_ conn: ServerConnection) async throws -> PVEVersion {
        demo(conn) ? DemoDataset.version() : try await live.version(conn)
    }
    public func clusterResources(_ conn: ServerConnection) async throws -> [ClusterResource] {
        demo(conn) ? DemoDataset.clusterResources() : try await live.clusterResources(conn)
    }
    public func nodeStatus(_ conn: ServerConnection, node: String) async throws -> NodeStatus {
        demo(conn) ? DemoDataset.nodeStatus() : try await live.nodeStatus(conn, node: node)
    }
    public func guestStatus(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int) async throws -> GuestStatus {
        demo(conn) ? DemoDataset.guestStatus(vmid: vmid, kind: kind) : try await live.guestStatus(conn, node: node, kind: kind, vmid: vmid)
    }
    public func guestRRD(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, timeframe: RRDTimeframe) async throws -> [RRDPoint] {
        demo(conn) ? DemoDataset.guestRRD(vmid: vmid) : try await live.guestRRD(conn, node: node, kind: kind, vmid: vmid, timeframe: timeframe)
    }
    public func nodeRRD(_ conn: ServerConnection, node: String, timeframe: RRDTimeframe) async throws -> [RRDPoint] {
        demo(conn) ? DemoDataset.nodeRRD() : try await live.nodeRRD(conn, node: node, timeframe: timeframe)
    }
    public func nextID(_ conn: ServerConnection) async throws -> Int {
        demo(conn) ? 111 : try await live.nextID(conn)
    }
    public func nodeServices(_ conn: ServerConnection, node: String) async throws -> [NodeService] {
        demo(conn) ? DemoDataset.nodeServices() : try await live.nodeServices(conn, node: node)
    }
    public func snapshots(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int) async throws -> [Snapshot] {
        demo(conn) ? DemoDataset.snapshots() : try await live.snapshots(conn, node: node, kind: kind, vmid: vmid)
    }
    public func backups(_ conn: ServerConnection, node: String, storage: String) async throws -> [BackupFile] {
        demo(conn) ? DemoDataset.backups(storage: storage) : try await live.backups(conn, node: node, storage: storage)
    }
    public func tasks(_ conn: ServerConnection, node: String, limit: Int, vmid: Int?) async throws -> [ProxmoxTaskInfo] {
        demo(conn) ? DemoDataset.tasks() : try await live.tasks(conn, node: node, limit: limit, vmid: vmid)
    }
    public func taskStatus(_ conn: ServerConnection, node: String, upid: String) async throws -> ProxmoxTaskStatus {
        demo(conn) ? DemoDataset.taskStatus(upid: upid) : try await live.taskStatus(conn, node: node, upid: upid)
    }
    public func taskLog(_ conn: ServerConnection, node: String, upid: String, limit: Int) async throws -> [TaskLogLine] {
        demo(conn) ? [] : try await live.taskLog(conn, node: node, upid: upid, limit: limit)
    }
    public func guestConfig(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int) async throws -> GuestConfig {
        demo(conn) ? DemoDataset.guestConfig(vmid: vmid, kind: kind) : try await live.guestConfig(conn, node: node, kind: kind, vmid: vmid)
    }
    public func qemuAgentInterfaces(_ conn: ServerConnection, node: String, vmid: Int) async throws -> AgentNetworkInterfaces {
        demo(conn) ? DemoDataset.emptyAgentInterfaces() : try await live.qemuAgentInterfaces(conn, node: node, vmid: vmid)
    }
    public func vncProxy(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int) async throws -> VNCProxyTicket {
        guard !demo(conn) else { throw APIError.transport("The VNC console isn't available in demo mode.") }
        return try await live.vncProxy(conn, node: node, kind: kind, vmid: vmid)
    }

    // MARK: Reads that are empty in demo (valid empty states)

    public func physicalDisks(_ conn: ServerConnection, node: String) async throws -> [PhysicalDisk] {
        demo(conn) ? [] : try await live.physicalDisks(conn, node: node)
    }
    public func zfsPools(_ conn: ServerConnection, node: String) async throws -> [ZFSPool] {
        demo(conn) ? [] : try await live.zfsPools(conn, node: node)
    }
    public func aptUpdates(_ conn: ServerConnection, node: String) async throws -> [AptUpdate] {
        demo(conn) ? [] : try await live.aptUpdates(conn, node: node)
    }
    public func nodeStorages(_ conn: ServerConnection, node: String, content: String?) async throws -> [StorageSummary] {
        demo(conn) ? [] : try await live.nodeStorages(conn, node: node, content: content)
    }
    public func clusterStatus(_ conn: ServerConnection) async throws -> [ClusterStatusEntry] {
        demo(conn) ? [] : try await live.clusterStatus(conn)
    }
    public func haResources(_ conn: ServerConnection) async throws -> [HAResource] {
        demo(conn) ? [] : try await live.haResources(conn)
    }
    public func users(_ conn: ServerConnection) async throws -> [PVEUser] {
        demo(conn) ? [] : try await live.users(conn)
    }
    public func userTokens(_ conn: ServerConnection, userid: String) async throws -> [PVEToken] {
        demo(conn) ? [] : try await live.userTokens(conn, userid: userid)
    }
    public func firewallRules(_ conn: ServerConnection, basePath: String) async throws -> [FirewallRule] {
        demo(conn) ? [] : try await live.firewallRules(conn, basePath: basePath)
    }
    public func nodeNetwork(_ conn: ServerConnection, node: String) async throws -> [NetworkInterface] {
        demo(conn) ? [] : try await live.nodeNetwork(conn, node: node)
    }
    public func storageContent(_ conn: ServerConnection, node: String, storage: String, content: String?) async throws -> [StorageVolume] {
        demo(conn) ? [] : try await live.storageContent(conn, node: node, storage: storage, content: content)
    }
    public func sdnZones(_ conn: ServerConnection) async throws -> [SDNZone] {
        demo(conn) ? [] : try await live.sdnZones(conn)
    }
    public func sdnVNets(_ conn: ServerConnection) async throws -> [SDNVNet] {
        demo(conn) ? [] : try await live.sdnVNets(conn)
    }
    public func replicationJobs(_ conn: ServerConnection) async throws -> [ReplicationJob] {
        demo(conn) ? [] : try await live.replicationJobs(conn)
    }
    public func backupJobs(_ conn: ServerConnection) async throws -> [BackupJob] {
        demo(conn) ? [] : try await live.backupJobs(conn)
    }

    // MARK: Mutations (no-op in demo; return a believable task id)

    public func power(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, action: PowerAction) async throws -> String {
        demo(conn) ? upid : try await live.power(conn, node: node, kind: kind, vmid: vmid, action: action)
    }
    public func nodeCommand(_ conn: ServerConnection, node: String, command: String) async throws -> String {
        demo(conn) ? upid : try await live.nodeCommand(conn, node: node, command: command)
    }
    public func wakeOnLAN(_ conn: ServerConnection, node: String) async throws -> String {
        demo(conn) ? upid : try await live.wakeOnLAN(conn, node: node)
    }
    public func serviceAction(_ conn: ServerConnection, node: String, service: String, action: String) async throws -> String {
        demo(conn) ? upid : try await live.serviceAction(conn, node: node, service: service, action: action)
    }
    public func createBackup(_ conn: ServerConnection, node: String, vmid: Int, storage: String, mode: String, compress: String, removeOld: Bool) async throws -> String {
        demo(conn) ? upid : try await live.createBackup(conn, node: node, vmid: vmid, storage: storage, mode: mode, compress: compress, removeOld: removeOld)
    }
    public func restoreBackup(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, archive: String, storage: String?, force: Bool) async throws -> String {
        demo(conn) ? upid : try await live.restoreBackup(conn, node: node, kind: kind, vmid: vmid, archive: archive, storage: storage, force: force)
    }
    public func updateFirewallRule(_ conn: ServerConnection, basePath: String, pos: Int, parameters: [String: String]) async throws {
        if !demo(conn) { try await live.updateFirewallRule(conn, basePath: basePath, pos: pos, parameters: parameters) }
    }
    public func deleteFirewallRule(_ conn: ServerConnection, basePath: String, pos: Int) async throws {
        if !demo(conn) { try await live.deleteFirewallRule(conn, basePath: basePath, pos: pos) }
    }
    public func createFirewallRule(_ conn: ServerConnection, basePath: String, parameters: [String: String]) async throws {
        if !demo(conn) { try await live.createFirewallRule(conn, basePath: basePath, parameters: parameters) }
    }
    public func deleteVolume(_ conn: ServerConnection, node: String, storage: String, volid: String) async throws -> String {
        demo(conn) ? upid : try await live.deleteVolume(conn, node: node, storage: storage, volid: volid)
    }
    public func createBackupJob(_ conn: ServerConnection, parameters: [String: String]) async throws {
        if !demo(conn) { try await live.createBackupJob(conn, parameters: parameters) }
    }
    public func updateBackupJob(_ conn: ServerConnection, id: String, parameters: [String: String]) async throws {
        if !demo(conn) { try await live.updateBackupJob(conn, id: id, parameters: parameters) }
    }
    public func deleteBackupJob(_ conn: ServerConnection, id: String) async throws {
        if !demo(conn) { try await live.deleteBackupJob(conn, id: id) }
    }
    public func createGuest(_ conn: ServerConnection, node: String, kind: GuestKind, parameters: [String: String]) async throws -> String {
        demo(conn) ? upid : try await live.createGuest(conn, node: node, kind: kind, parameters: parameters)
    }
    public func cloneGuest(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, newID: Int, name: String?, full: Bool, targetStorage: String?) async throws -> String {
        demo(conn) ? upid : try await live.cloneGuest(conn, node: node, kind: kind, vmid: vmid, newID: newID, name: name, full: full, targetStorage: targetStorage)
    }
    public func deleteGuest(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, purge: Bool) async throws -> String {
        demo(conn) ? upid : try await live.deleteGuest(conn, node: node, kind: kind, vmid: vmid, purge: purge)
    }
    public func migrateGuest(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, target: String, online: Bool) async throws -> String {
        demo(conn) ? upid : try await live.migrateGuest(conn, node: node, kind: kind, vmid: vmid, target: target, online: online)
    }
    public func convertToTemplate(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int) async throws -> String {
        demo(conn) ? upid : try await live.convertToTemplate(conn, node: node, kind: kind, vmid: vmid)
    }
    public func updateGuestConfig(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, parameters: [String: String]) async throws {
        if !demo(conn) { try await live.updateGuestConfig(conn, node: node, kind: kind, vmid: vmid, parameters: parameters) }
    }
    public func resizeDisk(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, disk: String, size: String) async throws -> String {
        demo(conn) ? upid : try await live.resizeDisk(conn, node: node, kind: kind, vmid: vmid, disk: disk, size: size)
    }
    public func createSnapshot(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String, description: String?, includeRAM: Bool) async throws -> String {
        demo(conn) ? upid : try await live.createSnapshot(conn, node: node, kind: kind, vmid: vmid, name: name, description: description, includeRAM: includeRAM)
    }
    public func deleteSnapshot(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String) async throws -> String {
        demo(conn) ? upid : try await live.deleteSnapshot(conn, node: node, kind: kind, vmid: vmid, name: name)
    }
    public func rollbackSnapshot(_ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String) async throws -> String {
        demo(conn) ? upid : try await live.rollbackSnapshot(conn, node: node, kind: kind, vmid: vmid, name: name)
    }
}
