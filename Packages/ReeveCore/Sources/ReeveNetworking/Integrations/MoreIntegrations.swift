import Foundation
import ReeveModels

// MARK: - Overseerr / Jellyseerr (shared: X-Api-Key, /api/v1)

enum SeerrStatus {
    private struct Status: Decodable { let version: String? }
    private struct Counts: Decodable {
        let total: Int?; let pending: Int?; let available: Int?; let processing: Int?
    }

    static func fetch(
        instance: ServiceInstance, secret: String?, client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.applyAuth(.header(name: "X-Api-Key"), secret: secret, config: instance.config)
            return req
        }
        let status = try await client.getJSON(Status.self, from: request("api/v1/status"),
                                               tls: instance.tlsPolicy)
        let counts = try await client.getJSON(Counts.self, from: request("api/v1/request/count"),
                                              tls: instance.tlsPolicy)
        return ServiceStatus(
            health: .ok,
            summary: "\(counts.pending ?? 0) pending request(s)",
            stats: [
                Stat(id: "pending", label: "Pending", value: "\(counts.pending ?? 0)",
                     raw: Double(counts.pending ?? 0), emphasis: .highlighted),
                Stat(id: "available", label: "Available", value: "\(counts.available ?? 0)",
                     raw: Double(counts.available ?? 0), emphasis: .highlighted),
                Stat(id: "total", label: "Total requests", value: "\(counts.total ?? 0)",
                     raw: Double(counts.total ?? 0)),
            ],
            version: status.version
        )
    }
}

public struct JellyseerrIntegration: ServiceIntegration {
    public static let typeID = "jellyseerr"
    public let displayName = "Jellyseerr"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("popcorn")
    public let authMethod: AuthMethod = .header(name: "X-Api-Key")
    public var configFields: [ConfigField] { [] }
    public init() {}
    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        try await SeerrStatus.fetch(instance: instance, secret: secret, client: client)
    }
}

public struct OverseerrIntegration: ServiceIntegration {
    public static let typeID = "overseerr"
    public let displayName = "Overseerr"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("popcorn")
    public let authMethod: AuthMethod = .header(name: "X-Api-Key")
    public var configFields: [ConfigField] { [] }
    public init() {}
    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        try await SeerrStatus.fetch(instance: instance, secret: secret, client: client)
    }
}

// MARK: - Portainer (X-API-Key)

public struct PortainerIntegration: ServiceIntegration {
    public static let typeID = "portainer"
    public let displayName = "Portainer"
    public let category: ServiceCategory = .containers
    public let iconAsset: ServiceIcon = .symbol("shippingbox")
    public let authMethod: AuthMethod = .header(name: "X-API-Key")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct SystemStatus: Decodable { let Version: String? }
    private struct Endpoint: Decodable { let Status: Int? }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.applyAuth(authMethod, secret: secret, config: instance.config)
            return req
        }
        let status = try await client.getJSON(SystemStatus.self, from: request("api/system/status"),
                                               tls: instance.tlsPolicy)
        let endpoints = (try? await client.getJSON([Endpoint].self, from: request("api/endpoints"),
                                                    tls: instance.tlsPolicy)) ?? []
        let up = endpoints.filter { $0.Status == 1 }.count
        return ServiceStatus(
            health: endpoints.isEmpty ? .unknown : (up == endpoints.count ? .ok : .warn),
            summary: "\(up)/\(endpoints.count) environments up",
            stats: [
                Stat(id: "environments", label: "Environments", value: "\(endpoints.count)",
                     raw: Double(endpoints.count), emphasis: .highlighted),
                Stat(id: "up", label: "Up", value: "\(up)", raw: Double(up), emphasis: .highlighted),
            ],
            version: status.Version
        )
    }
}

// MARK: - Grafana (Bearer)

public struct GrafanaIntegration: ServiceIntegration {
    public static let typeID = "grafana"
    public let displayName = "Grafana"
    public let category: ServiceCategory = .monitoring
    public let iconAsset: ServiceIcon = .symbol("chart.xyaxis.line")
    public let authMethod: AuthMethod = .bearer
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Health: Decodable { let database: String?; let version: String? }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        var req = HTTPRequest(url: base.appendingPathComponent("api/health"))
        req.applyAuth(authMethod, secret: secret, config: instance.config)
        let health = try await client.getJSON(Health.self, from: req, tls: instance.tlsPolicy)
        return ServiceStatus(
            health: health.database == "ok" ? .ok : .warn,
            summary: "Database \(health.database ?? "-")",
            stats: [
                Stat(id: "database", label: "Database", value: health.database ?? "-",
                     emphasis: .highlighted),
            ],
            version: health.version
        )
    }
}

// MARK: - Plex (X-Plex-Token; force JSON via Accept)

public struct PlexIntegration: ServiceIntegration {
    public static let typeID = "plex"
    public let displayName = "Plex"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("play.rectangle.fill")
    public let authMethod: AuthMethod = .header(name: "X-Plex-Token")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Root: Decodable {
        let MediaContainer: Container
        struct Container: Decodable { let friendlyName: String?; let version: String?; let size: Int? }
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.applyAuth(authMethod, secret: secret, config: instance.config)
            return req
        }
        let root = try await client.getJSON(Root.self, from: request("/"), tls: instance.tlsPolicy)
        let sessions = try? await client.getJSON(Root.self, from: request("status/sessions"),
                                                 tls: instance.tlsPolicy)
        let streams = sessions?.MediaContainer.size ?? 0
        return ServiceStatus(
            health: .ok,
            summary: streams == 0 ? "Idle" : "\(streams) streaming now",
            stats: [
                Stat(id: "streams", label: "Active streams", value: "\(streams)",
                     raw: Double(streams), emphasis: .highlighted),
            ],
            details: [DetailRow(id: "server", label: "Server",
                                value: root.MediaContainer.friendlyName ?? "-")],
            version: root.MediaContainer.version
        )
    }
}
