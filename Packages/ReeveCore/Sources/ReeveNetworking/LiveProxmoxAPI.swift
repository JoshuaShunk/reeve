import Foundation
import ReeveModels

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Concrete `ProxmoxAPI` over `async`/`await` `URLSession`.
///
/// Construct with `LiveProxmoxAPI()` for normal use (it builds a session backed
/// by a `ProxmoxTrustDelegate` so self-signed/pinned certs work), or inject a
/// custom `URLSession` (e.g. a `URLProtocol`-mocked one) for tests.
public final class LiveProxmoxAPI: ProxmoxAPI {
    private let session: URLSession
    private let trustDelegate: ProxmoxTrustDelegate?
    private let decoder: JSONDecoder

    /// Production initialiser: owns a session whose TLS trust is driven per-host
    /// by the connection's `tlsPolicy`.
    public init() {
        let delegate = ProxmoxTrustDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.trustDelegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.decoder = JSONDecoder()
    }

    /// Test/preview initialiser with an injected session (TLS policy ignored).
    public init(session: URLSession) {
        self.session = session
        self.trustDelegate = nil
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    public func version(_ conn: ServerConnection) async throws -> PVEVersion {
        try await get(conn, path: "version")
    }

    public func clusterResources(_ conn: ServerConnection) async throws -> [ClusterResource] {
        try await get(conn, path: "cluster/resources")
    }

    public func nodeStatus(_ conn: ServerConnection, node: String) async throws -> NodeStatus {
        try await get(conn, path: "nodes/\(node)/status")
    }

    public func guestStatus(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> GuestStatus {
        try await get(conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/status/current")
    }

    public func guestRRD(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        timeframe: RRDTimeframe
    ) async throws -> [RRDPoint] {
        try await get(
            conn,
            path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/rrddata",
            query: ["timeframe": timeframe.rawValue, "cf": "AVERAGE"]
        )
    }

    public func nodeRRD(
        _ conn: ServerConnection, node: String, timeframe: RRDTimeframe
    ) async throws -> [RRDPoint] {
        try await get(
            conn,
            path: "nodes/\(node)/rrddata",
            query: ["timeframe": timeframe.rawValue, "cf": "AVERAGE"]
        )
    }

    @discardableResult
    public func power(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        action: PowerAction
    ) async throws -> String {
        try await post(
            conn,
            path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/status/\(action.rawValue)"
        )
    }

    // MARK: - Node operations & hardware

    @discardableResult
    public func nodeCommand(
        _ conn: ServerConnection, node: String, command: String
    ) async throws -> String {
        try await post(conn, path: "nodes/\(node)/status", query: ["command": command])
    }

    @discardableResult
    public func wakeOnLAN(_ conn: ServerConnection, node: String) async throws -> String {
        try await post(conn, path: "nodes/\(node)/wakeonlan")
    }

    public func nodeServices(_ conn: ServerConnection, node: String) async throws -> [NodeService] {
        try await get(conn, path: "nodes/\(node)/services")
    }

    @discardableResult
    public func serviceAction(
        _ conn: ServerConnection, node: String, service: String, action: String
    ) async throws -> String {
        try await post(conn, path: "nodes/\(node)/services/\(service)/\(action)")
    }

    public func physicalDisks(_ conn: ServerConnection, node: String) async throws -> [PhysicalDisk] {
        try await get(conn, path: "nodes/\(node)/disks/list")
    }

    public func zfsPools(_ conn: ServerConnection, node: String) async throws -> [ZFSPool] {
        try await get(conn, path: "nodes/\(node)/disks/zfs")
    }

    public func aptUpdates(_ conn: ServerConnection, node: String) async throws -> [AptUpdate] {
        try await get(conn, path: "nodes/\(node)/apt/update")
    }

    public func nodeStorages(
        _ conn: ServerConnection, node: String, content: String?
    ) async throws -> [StorageSummary] {
        var query: [String: String] = [:]
        if let content { query["content"] = content }
        return try await get(conn, path: "nodes/\(node)/storage", query: query)
    }

    @discardableResult
    public func createBackup(
        _ conn: ServerConnection, node: String, vmid: Int,
        storage: String, mode: String, compress: String, removeOld: Bool
    ) async throws -> String {
        try await post(conn, path: "nodes/\(node)/vzdump", query: [
            "vmid": String(vmid), "storage": storage, "mode": mode,
            "compress": compress, "remove": removeOld ? "1" : "0",
        ])
    }

    @discardableResult
    public func restoreBackup(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        archive: String, storage: String?, force: Bool
    ) async throws -> String {
        var query: [String: String] = ["vmid": String(vmid), "force": force ? "1" : "0"]
        switch kind {
        case .qemu:
            query["archive"] = archive
        case .lxc:
            query["ostemplate"] = archive
            query["restore"] = "1"
        }
        if let storage, !storage.isEmpty { query["storage"] = storage }
        return try await post(conn, path: "nodes/\(node)/\(kind.pathSegment)", query: query)
    }

    @discardableResult
    public func createGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, parameters: [String: String]
    ) async throws -> String {
        try await post(conn, path: "nodes/\(node)/\(kind.pathSegment)", query: parameters)
    }

    // MARK: - Guest lifecycle management

    public func nextID(_ conn: ServerConnection) async throws -> Int {
        // `/cluster/nextid` returns the id as a JSON string, e.g. {"data":"108"}.
        let value: String = try await get(conn, path: "cluster/nextid")
        return Int(value) ?? 100
    }

    @discardableResult
    public func cloneGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        newID: Int, name: String?, full: Bool, targetStorage: String?
    ) async throws -> String {
        var query = ["newid": String(newID), "full": full ? "1" : "0"]
        if let name, !name.isEmpty {
            // QEMU uses `name`, LXC uses `hostname`.
            query[kind == .qemu ? "name" : "hostname"] = name
        }
        if full, let targetStorage, !targetStorage.isEmpty { query["storage"] = targetStorage }
        return try await post(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/clone", query: query
        )
    }

    @discardableResult
    public func deleteGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, purge: Bool
    ) async throws -> String {
        try await delete(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)",
            query: purge ? ["purge": "1", "destroy-unreferenced-disks": "1"] : [:]
        )
    }

    @discardableResult
    public func migrateGuest(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        target: String, online: Bool
    ) async throws -> String {
        var query = ["target": target]
        // QEMU live-migrates with `online`; LXC uses `restart` to move a running CT.
        query[kind == .qemu ? "online" : "restart"] = online ? "1" : "0"
        return try await post(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/migrate", query: query
        )
    }

    @discardableResult
    public func convertToTemplate(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> String {
        try await post(conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/template")
    }

    public func updateGuestConfig(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        parameters: [String: String]
    ) async throws {
        _ = try await put(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/config", query: parameters
        )
    }

    @discardableResult
    public func resizeDisk(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        disk: String, size: String
    ) async throws -> String {
        try await put(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/resize",
            query: ["disk": disk, "size": size]
        )
    }

    // MARK: - Cluster / HA / users / firewall

    public func clusterStatus(_ conn: ServerConnection) async throws -> [ClusterStatusEntry] {
        try await get(conn, path: "cluster/status")
    }

    public func haResources(_ conn: ServerConnection) async throws -> [HAResource] {
        try await get(conn, path: "cluster/ha/resources")
    }

    public func users(_ conn: ServerConnection) async throws -> [PVEUser] {
        try await get(conn, path: "access/users")
    }

    public func userTokens(_ conn: ServerConnection, userid: String) async throws -> [PVEToken] {
        let encoded = userid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userid
        return try await get(conn, path: "access/users/\(encoded)/token")
    }

    public func firewallRules(
        _ conn: ServerConnection, basePath: String
    ) async throws -> [FirewallRule] {
        try await get(conn, path: "\(basePath)/rules")
    }

    public func updateFirewallRule(
        _ conn: ServerConnection, basePath: String, pos: Int, parameters: [String: String]
    ) async throws {
        _ = try await put(conn, path: "\(basePath)/rules/\(pos)", query: parameters)
    }

    public func deleteFirewallRule(
        _ conn: ServerConnection, basePath: String, pos: Int
    ) async throws {
        _ = try await delete(conn, path: "\(basePath)/rules/\(pos)")
    }

    public func createFirewallRule(
        _ conn: ServerConnection, basePath: String, parameters: [String: String]
    ) async throws {
        _ = try await post(conn, path: "\(basePath)/rules", query: parameters)
    }

    // MARK: - Infrastructure views

    public func nodeNetwork(_ conn: ServerConnection, node: String) async throws -> [NetworkInterface] {
        try await get(conn, path: "nodes/\(node)/network")
    }

    public func storageContent(
        _ conn: ServerConnection, node: String, storage: String, content: String?
    ) async throws -> [StorageVolume] {
        var query: [String: String] = [:]
        if let content { query["content"] = content }
        return try await get(conn, path: "nodes/\(node)/storage/\(storage)/content", query: query)
    }

    @discardableResult
    public func deleteVolume(
        _ conn: ServerConnection, node: String, storage: String, volid: String
    ) async throws -> String {
        let encoded = volid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? volid
        return try await delete(conn, path: "nodes/\(node)/storage/\(storage)/content/\(encoded)")
    }

    public func sdnZones(_ conn: ServerConnection) async throws -> [SDNZone] {
        try await get(conn, path: "cluster/sdn/zones")
    }

    public func sdnVNets(_ conn: ServerConnection) async throws -> [SDNVNet] {
        try await get(conn, path: "cluster/sdn/vnets")
    }

    public func replicationJobs(_ conn: ServerConnection) async throws -> [ReplicationJob] {
        try await get(conn, path: "cluster/replication")
    }

    public func backupJobs(_ conn: ServerConnection) async throws -> [BackupJob] {
        try await get(conn, path: "cluster/backup")
    }

    public func createBackupJob(_ conn: ServerConnection, parameters: [String: String]) async throws {
        _ = try await post(conn, path: "cluster/backup", query: parameters)
    }

    public func updateBackupJob(
        _ conn: ServerConnection, id: String, parameters: [String: String]
    ) async throws {
        _ = try await put(conn, path: "cluster/backup/\(id)", query: parameters)
    }

    public func deleteBackupJob(_ conn: ServerConnection, id: String) async throws {
        _ = try await delete(conn, path: "cluster/backup/\(id)")
    }

    // MARK: - Snapshots / backups / tasks

    public func snapshots(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> [Snapshot] {
        try await get(conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/snapshot")
    }

    @discardableResult
    public func createSnapshot(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int,
        name: String, description: String?, includeRAM: Bool
    ) async throws -> String {
        var query = ["snapname": name]
        if let description, !description.isEmpty { query["description"] = description }
        if kind == .qemu && includeRAM { query["vmstate"] = "1" }
        return try await post(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/snapshot", query: query
        )
    }

    @discardableResult
    public func deleteSnapshot(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String
    ) async throws -> String {
        try await delete(conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/snapshot/\(name)")
    }

    @discardableResult
    public func rollbackSnapshot(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int, name: String
    ) async throws -> String {
        try await post(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/snapshot/\(name)/rollback"
        )
    }

    public func backups(
        _ conn: ServerConnection, node: String, storage: String
    ) async throws -> [BackupFile] {
        try await get(
            conn, path: "nodes/\(node)/storage/\(storage)/content", query: ["content": "backup"]
        )
    }

    public func taskStatus(
        _ conn: ServerConnection, node: String, upid: String
    ) async throws -> ProxmoxTaskStatus {
        // The UPID contains ':' and '!', percent-encode the whole thing as one
        // path segment (urlPathAllowed doesn't escape ':' so encode aggressively).
        let encoded = upid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? upid
        guard let url = URL(
            string: "\(conn.baseURL.absoluteString)/api2/json/nodes/\(node)/tasks/\(encoded)/status"
        ) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(conn.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, conn: conn)
    }

    public func tasks(
        _ conn: ServerConnection, node: String, limit: Int, vmid: Int?
    ) async throws -> [ProxmoxTaskInfo] {
        var query = ["limit": String(limit), "source": "all"]
        if let vmid { query["vmid"] = String(vmid) }
        return try await get(conn, path: "nodes/\(node)/tasks", query: query)
    }

    public func guestConfig(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> GuestConfig {
        try await get(conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/config")
    }

    public func qemuAgentInterfaces(
        _ conn: ServerConnection, node: String, vmid: Int
    ) async throws -> AgentNetworkInterfaces {
        try await get(
            conn, path: "nodes/\(node)/qemu/\(vmid)/agent/network-get-interfaces"
        )
    }

    public func taskLog(
        _ conn: ServerConnection, node: String, upid: String, limit: Int
    ) async throws -> [TaskLogLine] {
        let encoded = upid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? upid
        guard var components = URLComponents(
            string: "\(conn.baseURL.absoluteString)/api2/json/nodes/\(node)/tasks/\(encoded)/log"
        ) else { throw APIError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "start", value: "0"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(conn.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, conn: conn)
    }

    public func vncProxy(
        _ conn: ServerConnection, node: String, kind: GuestKind, vmid: Int
    ) async throws -> VNCProxyTicket {
        let request = try makeRequest(
            conn, path: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/vncproxy", method: "POST",
            query: ["websocket": "0"]
        )
        return try await send(request, conn: conn)
    }

    // MARK: - Request plumbing

    private func get<T: Decodable & Sendable>(
        _ conn: ServerConnection, path: String, query: [String: String] = [:]
    ) async throws -> T {
        let request = try makeRequest(conn, path: path, method: "GET", query: query)
        return try await send(request, conn: conn)
    }

    private func post(
        _ conn: ServerConnection, path: String, query: [String: String] = [:]
    ) async throws -> String {
        let request = try makeRequest(conn, path: path, method: "POST", query: query)
        // Worker-spawning endpoints return `{ "data": "UPID:..." }` (the task id).
        let upid: String? = try await send(request, conn: conn)
        return upid ?? ""
    }

    private func put(
        _ conn: ServerConnection, path: String, query: [String: String] = [:]
    ) async throws -> String {
        let request = try makeRequest(conn, path: path, method: "PUT", query: query)
        let upid: String? = try await send(request, conn: conn)
        return upid ?? ""
    }

    private func delete(
        _ conn: ServerConnection, path: String, query: [String: String] = [:]
    ) async throws -> String {
        let request = try makeRequest(conn, path: path, method: "DELETE", query: query)
        let upid: String? = try await send(request, conn: conn)
        return upid ?? ""
    }

    private func makeRequest(
        _ conn: ServerConnection, path: String, method: String, query: [String: String]
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: conn.baseURL.appendingPathComponent("api2/json/\(path)"),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(conn.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable & Sendable>(
        _ request: URLRequest, conn: ServerConnection
    ) async throws -> T {
        trustDelegate?.setPolicy(conn.tlsPolicy, forHost: conn.host)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorServerCertificateUntrusted
                || nsError.code == NSURLErrorCancelled {
                throw APIError.untrustedCertificate(host: conn.host)
            }
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            return try decoder.decode(ProxmoxResponse<T>.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
