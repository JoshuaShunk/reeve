import Foundation
import ReeveModels

/// AdGuard Home, `GET /control/stats`, HTTP Basic auth when protected.
/// https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml
public struct AdGuardHomeIntegration: ServiceIntegration {
    public static let typeID = "adguard-home"

    public let displayName = "AdGuard Home"
    public let category: ServiceCategory = .dns
    public let iconAsset: ServiceIcon = .symbol("shield.lefthalf.filled")
    public let authMethod: AuthMethod = .basic(usernameField: "username")
    public var configFields: [ConfigField] {
        [ConfigField(key: "username", label: "Username", kind: .text, isRequired: false)]
    }

    public init() {}

    private struct Stats: Decodable {
        let num_dns_queries: Int
        let num_blocked_filtering: Int
        let avg_processing_time: Double
    }

    public func fetchStatus(
        for instance: ServiceInstance, secret: String?, client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        var request = HTTPRequest(url: base.appendingPathComponent("control/stats"))
        request.applyAuth(authMethod, secret: secret, config: instance.config)

        let stats = try await client.getJSON(Stats.self, from: request, tls: instance.tlsPolicy)
        let blockPct = stats.num_dns_queries > 0
            ? Double(stats.num_blocked_filtering) / Double(stats.num_dns_queries) * 100
            : 0

        return ServiceStatus(
            health: .ok,
            summary: "\(stats.num_blocked_filtering) blocked today",
            stats: [
                Stat(id: "blocked", label: "Blocked", value: "\(stats.num_blocked_filtering)",
                     raw: Double(stats.num_blocked_filtering), emphasis: .highlighted),
                Stat(id: "block_pct", label: "Block rate",
                     value: String(format: "%.1f", blockPct), unit: "%",
                     raw: blockPct, emphasis: .highlighted),
                Stat(id: "queries", label: "Queries", value: "\(stats.num_dns_queries)",
                     raw: Double(stats.num_dns_queries)),
                Stat(id: "latency", label: "Avg latency",
                     value: String(format: "%.0f", stats.avg_processing_time * 1000), unit: "ms",
                     raw: stats.avg_processing_time * 1000),
            ]
        )
    }
}
