import Foundation
import ReeveModels

/// Shared status fetch for Servarr apps (Sonarr/Radarr/Prowlarr), `X-Api-Key`,
/// `system/status` + `health` (+ optional `queue`).
enum ServarrStatus {
    private struct SystemStatus: Decodable { let version: String? }
    private struct HealthItem: Decodable { let type: String? }
    private struct Queue: Decodable { let totalRecords: Int? }

    static func fetch(
        apiPath: String, withQueue: Bool, instance: ServiceInstance, secret: String?,
        client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent("\(apiPath)/\(path)"))
            req.applyAuth(.header(name: "X-Api-Key"), secret: secret, config: instance.config)
            return req
        }

        let status = try await client.getJSON(SystemStatus.self, from: request("system/status"),
                                               tls: instance.tlsPolicy)
        let health = (try? await client.getJSON([HealthItem].self, from: request("health"),
                                                 tls: instance.tlsPolicy)) ?? []
        let errors = health.filter { $0.type == "error" }.count
        let warnings = health.filter { $0.type == "warning" || $0.type == "notice" }.count

        var stats: [Stat] = []
        if withQueue, let queue = try? await client.getJSON(
            Queue.self, from: request("queue"), tls: instance.tlsPolicy
        ) {
            stats.append(Stat(id: "queue", label: "Queue", value: "\(queue.totalRecords ?? 0)",
                              raw: Double(queue.totalRecords ?? 0), emphasis: .highlighted))
        }
        stats.append(Stat(id: "issues", label: "Health issues", value: "\(errors + warnings)",
                          raw: Double(errors + warnings),
                          emphasis: (errors + warnings) > 0 ? .highlighted : .normal))

        return ServiceStatus(
            health: errors > 0 ? .down : (warnings > 0 ? .warn : .ok),
            summary: (errors + warnings) == 0 ? "Healthy" : "\(errors + warnings) health issue(s)",
            stats: stats,
            version: status.version
        )
    }
}

public struct SonarrIntegration: ServiceIntegration {
    public static let typeID = "sonarr"
    public let displayName = "Sonarr"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("tv")
    public let authMethod: AuthMethod = .header(name: "X-Api-Key")
    public var configFields: [ConfigField] { [] }
    public init() {}
    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        try await ServarrStatus.fetch(apiPath: "api/v3", withQueue: true, instance: instance, secret: secret, client: client)
    }
}

public struct RadarrIntegration: ServiceIntegration {
    public static let typeID = "radarr"
    public let displayName = "Radarr"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("film")
    public let authMethod: AuthMethod = .header(name: "X-Api-Key")
    public var configFields: [ConfigField] { [] }
    public init() {}
    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        try await ServarrStatus.fetch(apiPath: "api/v3", withQueue: true, instance: instance, secret: secret, client: client)
    }
}

public struct ProwlarrIntegration: ServiceIntegration {
    public static let typeID = "prowlarr"
    public let displayName = "Prowlarr"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("magnifyingglass")
    public let authMethod: AuthMethod = .header(name: "X-Api-Key")
    public var configFields: [ConfigField] { [] }
    public init() {}
    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        try await ServarrStatus.fetch(apiPath: "api/v1", withQueue: false, instance: instance, secret: secret, client: client)
    }
}
