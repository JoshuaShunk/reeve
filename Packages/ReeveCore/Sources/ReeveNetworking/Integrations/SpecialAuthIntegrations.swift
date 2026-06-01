import Foundation
import ReeveModels

// MARK: - Nextcloud (Basic + app password, serverinfo app, OCS header)

public struct NextcloudIntegration: ServiceIntegration {
    public static let typeID = "nextcloud"
    public let displayName = "Nextcloud"
    public let category: ServiceCategory = .storage
    public let iconAsset: ServiceIcon = .symbol("cloud.fill")
    public let authMethod: AuthMethod = .basic(usernameField: "username")
    public var configFields: [ConfigField] {
        [ConfigField(key: "username", label: "Username", kind: .text, isRequired: true)]
    }
    public init() {}

    private struct Response: Decodable {
        struct OCS: Decodable {
            struct Meta: Decodable { let status: String? }
            struct Data: Decodable {
                struct NC: Decodable {
                    struct System: Decodable { let version: String? }
                    struct Storage: Decodable { let num_users: Int?; let num_files: Int? }
                    let system: System?; let storage: Storage?
                }
                struct ActiveUsers: Decodable { let last24hours: Int? }
                let nextcloud: NC?; let activeUsers: ActiveUsers?
            }
            let meta: Meta?; let data: Data?
        }
        let ocs: OCS
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL,
              let url = URL(string: base.absoluteString
                  + "/ocs/v2.php/apps/serverinfo/api/v1/info?format=json")
        else { throw APIError.invalidURL }
        var req = HTTPRequest(url: url)
        req.applyAuth(authMethod, secret: secret, config: instance.config)
        req.headers["OCS-APIRequest"] = "true"
        let response = try await client.getJSON(Response.self, from: req, tls: instance.tlsPolicy)
        let nc = response.ocs.data?.nextcloud
        return ServiceStatus(
            health: response.ocs.meta?.status == "ok" ? .ok : .warn,
            summary: "\(nc?.storage?.num_users ?? 0) users",
            stats: [
                Stat(id: "users", label: "Users", value: "\(nc?.storage?.num_users ?? 0)",
                     raw: Double(nc?.storage?.num_users ?? 0), emphasis: .highlighted),
                Stat(id: "active", label: "Active (24h)",
                     value: "\(response.ocs.data?.activeUsers?.last24hours ?? 0)",
                     emphasis: .highlighted),
                Stat(id: "files", label: "Files", value: "\(nc?.storage?.num_files ?? 0)",
                     raw: Double(nc?.storage?.num_files ?? 0)),
            ],
            version: nc?.system?.version
        )
    }
}

// MARK: - Proxmox Backup Server (PBSAPIToken)

public struct ProxmoxBackupServerIntegration: ServiceIntegration {
    public static let typeID = "proxmox-backup-server"
    public let displayName = "Proxmox Backup Server"
    public let category: ServiceCategory = .storage
    public let iconAsset: ServiceIcon = .symbol("externaldrive.badge.timemachine")
    public let authMethod: AuthMethod = .custom
    public var configFields: [ConfigField] {
        [ConfigField(key: "tokenID", label: "Token ID (user@realm!name)",
                     kind: .text, isRequired: true)]
    }
    public init() {}

    private struct Datastore: Decodable {
        let store: String?; let total: Int?; let used: Int?
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        var req = HTTPRequest(url: base.appendingPathComponent("api2/json/status/datastore-usage"))
        if let tokenID = instance.config["tokenID"], let secret {
            req.headers["Authorization"] = "PBSAPIToken=\(tokenID):\(secret)"
        }
        let stores = try await client.getJSON(
            ProxmoxResponse<[Datastore]>.self, from: req, tls: instance.tlsPolicy
        ).data
        let totalUsed = stores.compactMap(\.used).reduce(0, +)
        let totalSize = stores.compactMap(\.total).reduce(0, +)
        let pct = totalSize > 0 ? Double(totalUsed) / Double(totalSize) * 100 : 0
        return ServiceStatus(
            health: .ok,
            summary: "\(stores.count) datastore(s)",
            stats: [
                Stat(id: "datastores", label: "Datastores", value: "\(stores.count)",
                     raw: Double(stores.count), emphasis: .highlighted),
                Stat(id: "usage", label: "Used", value: String(format: "%.0f", pct), unit: "%",
                     raw: pct, emphasis: .highlighted),
            ],
            details: stores.map { DetailRow(id: $0.store ?? "?", label: $0.store ?? "datastore",
                                            value: "\(ByteCountFormatter.string(fromByteCount: Int64($0.used ?? 0), countStyle: .binary))") }
        )
    }
}

// MARK: - Uptime Kuma (Basic on Prometheus /metrics)

public struct UptimeKumaIntegration: ServiceIntegration {
    public static let typeID = "uptime-kuma"
    public let displayName = "Uptime Kuma"
    public let category: ServiceCategory = .monitoring
    public let iconAsset: ServiceIcon = .symbol("waveform.path.ecg")
    public let authMethod: AuthMethod = .basic(usernameField: "username")
    public var configFields: [ConfigField] {
        [
            ConfigField(key: "statusPageSlug", label: "Status page slug",
                        kind: .text, placeholder: "e.g. homelab"),
            ConfigField(key: "username", label: "Username (for /metrics)", kind: .text),
        ]
    }
    public init() {}

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }

        // Prefer the public status page when a slug is configured: no auth needed
        // and it mirrors the dashboard the user built.
        if let slug = instance.config["statusPageSlug"], !slug.isEmpty {
            let page = try await client.uptimeKumaStatusPage(
                slug: slug, baseURL: base, tls: instance.tlsPolicy
            )
            let monitors = page.groups.flatMap(\.monitors)
            let up = monitors.filter { $0.latestStatus == 1 }.count
            let down = monitors.filter { $0.latestStatus == 0 }.count
            return ServiceStatus(
                health: monitors.isEmpty ? .unknown : (down == 0 ? .ok : .down),
                summary: "\(up)/\(monitors.count) monitors up",
                stats: [
                    Stat(id: "up", label: "Up", value: "\(up)", raw: Double(up), emphasis: .highlighted),
                    Stat(id: "down", label: "Down", value: "\(down)", raw: Double(down),
                         emphasis: down > 0 ? .highlighted : .normal),
                ]
            )
        }

        var req = HTTPRequest(url: base.appendingPathComponent("metrics"))
        req.applyAuth(authMethod, secret: secret, config: instance.config)
        let (data, response) = try await client.send(req, tls: instance.tlsPolicy)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.badStatus(response.statusCode, body: nil)
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        var up = 0, down = 0
        for line in text.split(separator: "\n") where line.hasPrefix("monitor_status") {
            guard let value = line.split(separator: " ").last, let number = Double(value) else { continue }
            if number == 1 { up += 1 } else if number == 0 { down += 1 }
        }
        let total = up + down
        return ServiceStatus(
            health: total == 0 ? .unknown : (down == 0 ? .ok : .down),
            summary: "\(up)/\(total) monitors up",
            stats: [
                Stat(id: "up", label: "Up", value: "\(up)", raw: Double(up), emphasis: .highlighted),
                Stat(id: "down", label: "Down", value: "\(down)", raw: Double(down),
                     emphasis: down > 0 ? .highlighted : .normal),
            ]
        )
    }
}
