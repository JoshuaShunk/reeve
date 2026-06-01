import Foundation
import ReeveModels

/// Read + power-management surface of the Proxmox VE API that the app needs.
/// A protocol so the UI can be driven by a mock in previews and tests.
public protocol ProxmoxAPI: Sendable {
    /// `GET /version`, also serves as a connection/credential test.
    func version(_ conn: ServerConnection) async throws -> PVEVersion

    /// `GET /cluster/resources`, one call backing the whole dashboard.
    func clusterResources(_ conn: ServerConnection) async throws -> [ClusterResource]

    /// `GET /nodes/{node}/status`.
    func nodeStatus(_ conn: ServerConnection, node: String) async throws -> NodeStatus

    /// `GET /nodes/{node}/{kind}/{vmid}/status/current`.
    func guestStatus(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> GuestStatus

    /// `GET /nodes/{node}/{kind}/{vmid}/rrddata`.
    func guestRRD(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        timeframe: RRDTimeframe
    ) async throws -> [RRDPoint]

    /// `GET /nodes/{node}/rrddata`.
    func nodeRRD(
        _ conn: ServerConnection, node: String, timeframe: RRDTimeframe
    ) async throws -> [RRDPoint]

    /// `POST /nodes/{node}/{kind}/{vmid}/status/{action}`, returns the task UPID.
    @discardableResult
    func power(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        action: PowerAction
    ) async throws -> String

    /// `GET /cluster/nextid`, a free VMID to suggest for clone/create.
    func nextID(_ conn: ServerConnection) async throws -> Int

    // MARK: - Node operations & hardware

    /// `POST /nodes/{node}/status`, `command` is `reboot` or `shutdown`.
    @discardableResult
    func nodeCommand(_ conn: ServerConnection, node: String, command: String) async throws -> String

    /// `POST /nodes/{node}/wakeonlan`, send a WoL magic packet to power the node on.
    @discardableResult
    func wakeOnLAN(_ conn: ServerConnection, node: String) async throws -> String

    /// `GET /nodes/{node}/services`.
    func nodeServices(_ conn: ServerConnection, node: String) async throws -> [NodeService]

    /// `POST /nodes/{node}/services/{service}/{action}`, start/stop/restart/reload.
    @discardableResult
    func serviceAction(
        _ conn: ServerConnection, node: String, service: String, action: String
    ) async throws -> String

    /// `GET /nodes/{node}/disks/list`.
    func physicalDisks(_ conn: ServerConnection, node: String) async throws -> [PhysicalDisk]

    /// `GET /nodes/{node}/disks/zfs`.
    func zfsPools(_ conn: ServerConnection, node: String) async throws -> [ZFSPool]

    /// `GET /nodes/{node}/apt/update`, available package updates.
    func aptUpdates(_ conn: ServerConnection, node: String) async throws -> [AptUpdate]

    /// `GET /nodes/{node}/storage`, storages (optionally filtered by content type).
    func nodeStorages(
        _ conn: ServerConnection, node: String, content: String?
    ) async throws -> [StorageSummary]

    // MARK: - Backup / restore

    /// `POST /nodes/{node}/vzdump`, back up one guest now. Returns the task UPID.
    @discardableResult
    func createBackup(
        _ conn: ServerConnection, node: String, vmid: Int,
        storage: String, mode: String, compress: String, removeOld: Bool
    ) async throws -> String

    /// Restore a guest from a backup volume. `POST /nodes/{node}/{qemu|lxc}`.
    /// Returns the task UPID.
    @discardableResult
    func restoreBackup(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        archive: String, storage: String?, force: Bool
    ) async throws -> String

    // MARK: - Cluster / HA / users / firewall

    /// `GET /cluster/status`.
    func clusterStatus(_ conn: ServerConnection) async throws -> [ClusterStatusEntry]

    /// `GET /cluster/ha/resources`.
    func haResources(_ conn: ServerConnection) async throws -> [HAResource]

    /// `GET /access/users`.
    func users(_ conn: ServerConnection) async throws -> [PVEUser]

    /// `GET /access/users/{userid}/token`.
    func userTokens(_ conn: ServerConnection, userid: String) async throws -> [PVEToken]

    /// `GET {basePath}/rules`, firewall rules (basePath e.g. `nodes/x/firewall`).
    func firewallRules(_ conn: ServerConnection, basePath: String) async throws -> [FirewallRule]

    /// `PUT {basePath}/rules/{pos}`, update a rule (e.g. enable on/off).
    func updateFirewallRule(
        _ conn: ServerConnection, basePath: String, pos: Int, parameters: [String: String]
    ) async throws

    /// `DELETE {basePath}/rules/{pos}`.
    func deleteFirewallRule(_ conn: ServerConnection, basePath: String, pos: Int) async throws

    /// `POST {basePath}/rules`, append a new rule.
    func createFirewallRule(
        _ conn: ServerConnection, basePath: String, parameters: [String: String]
    ) async throws

    // MARK: - Infrastructure views

    /// `GET /nodes/{node}/network`.
    func nodeNetwork(_ conn: ServerConnection, node: String) async throws -> [NetworkInterface]

    /// `GET /nodes/{node}/storage/{storage}/content` (optionally a content filter).
    func storageContent(
        _ conn: ServerConnection, node: String, storage: String, content: String?
    ) async throws -> [StorageVolume]

    /// `DELETE /nodes/{node}/storage/{storage}/content/{volid}`.
    @discardableResult
    func deleteVolume(
        _ conn: ServerConnection, node: String, storage: String, volid: String
    ) async throws -> String

    /// `GET /cluster/sdn/zones`.
    func sdnZones(_ conn: ServerConnection) async throws -> [SDNZone]

    /// `GET /cluster/sdn/vnets`.
    func sdnVNets(_ conn: ServerConnection) async throws -> [SDNVNet]

    /// `GET /cluster/replication`.
    func replicationJobs(_ conn: ServerConnection) async throws -> [ReplicationJob]

    // MARK: - Scheduled backup jobs

    /// `GET /cluster/backup`.
    func backupJobs(_ conn: ServerConnection) async throws -> [BackupJob]

    /// `POST /cluster/backup`, create a scheduled job.
    func createBackupJob(_ conn: ServerConnection, parameters: [String: String]) async throws

    /// `PUT /cluster/backup/{id}`, update a job.
    func updateBackupJob(
        _ conn: ServerConnection, id: String, parameters: [String: String]
    ) async throws

    /// `DELETE /cluster/backup/{id}`.
    func deleteBackupJob(_ conn: ServerConnection, id: String) async throws

    /// `POST /nodes/{node}/{qemu|lxc}`, create a new guest. Returns the task UPID.
    @discardableResult
    func createGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, parameters: [String: String]
    ) async throws -> String

    // MARK: - Guest lifecycle management

    /// `POST …/{kind}/{vmid}/clone`, clone a guest/template. Returns the task UPID.
    @discardableResult
    func cloneGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        newID: Int, name: String?, full: Bool, targetStorage: String?
    ) async throws -> String

    /// `DELETE …/{kind}/{vmid}`, destroy a guest. Returns the task UPID.
    @discardableResult
    func deleteGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, purge: Bool
    ) async throws -> String

    /// `POST …/{kind}/{vmid}/migrate`, migrate to another node. Returns the task UPID.
    @discardableResult
    func migrateGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        target: String, online: Bool
    ) async throws -> String

    /// `POST …/{kind}/{vmid}/template`, convert a guest into a template.
    @discardableResult
    func convertToTemplate(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> String

    /// `PUT …/{kind}/{vmid}/config`, update config (cores/memory/name/…). Synchronous.
    func updateGuestConfig(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        parameters: [String: String]
    ) async throws

    /// `PUT …/{kind}/{vmid}/resize`, grow a disk (size like "+8G"). Returns the task UPID.
    @discardableResult
    func resizeDisk(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        disk: String, size: String
    ) async throws -> String

    /// `GET …/{kind}/{vmid}/snapshot`.
    func snapshots(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> [Snapshot]

    /// `POST …/{kind}/{vmid}/snapshot`, returns the task UPID.
    @discardableResult
    func createSnapshot(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        name: String, description: String?, includeRAM: Bool
    ) async throws -> String

    /// `DELETE …/{kind}/{vmid}/snapshot/{name}`, returns the task UPID.
    @discardableResult
    func deleteSnapshot(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String
    ) async throws -> String

    /// `POST …/{kind}/{vmid}/snapshot/{name}/rollback`, returns the task UPID.
    @discardableResult
    func rollbackSnapshot(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String
    ) async throws -> String

    /// `GET /nodes/{node}/storage/{storage}/content?content=backup`.
    func backups(
        _ conn: ServerConnection, node: String, storage: String
    ) async throws -> [BackupFile]

    /// `GET /nodes/{node}/tasks/{upid}/status`.
    func taskStatus(
        _ conn: ServerConnection, node: String, upid: String
    ) async throws -> ProxmoxTaskStatus

    /// `GET /nodes/{node}/tasks`, recent + running tasks (optionally one guest).
    func tasks(
        _ conn: ServerConnection, node: String, limit: Int, vmid: Int?
    ) async throws -> [ProxmoxTaskInfo]

    /// `GET …/{kind}/{vmid}/config`, the guest's configuration.
    func guestConfig(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> GuestConfig

    /// `GET …/qemu/{vmid}/agent/network-get-interfaces`. IPs from the guest agent.
    func qemuAgentInterfaces(
        _ conn: ServerConnection, node: String, vmid: Int
    ) async throws -> AgentNetworkInterfaces

    /// `GET /nodes/{node}/tasks/{upid}/log`.
    func taskLog(
        _ conn: ServerConnection, node: String, upid: String, limit: Int
    ) async throws -> [TaskLogLine]

    /// `POST …/{kind}/{vmid}/vncproxy`, open a VNC proxy on the node for a
    /// graphical console. Returns the connect port + one-time ticket (the VNC
    /// password). Works with an API token; the proxy only listens briefly.
    func vncProxy(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> VNCProxyTicket
}
