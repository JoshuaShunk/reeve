import Foundation
import ReeveModels

/// TrueNAS SCALE, `GET /api/v2.0/system/info` + `GET /api/v2.0/pool`, Bearer API
/// key. https://www.truenas.com/docs/scale/api/
public struct TrueNASIntegration: ServiceIntegration {
    public static let typeID = "truenas"

    public let displayName = "TrueNAS"
    public let category: ServiceCategory = .storage
    public let iconAsset: ServiceIcon = .symbol("externaldrive.fill")
    public let authMethod: AuthMethod = .bearer
    public var configFields: [ConfigField] { [] }

    public init() {}

    private struct SystemInfo: Decodable {
        let version: String?
        let uptime_seconds: Double?
    }
    private struct Pool: Decodable {
        let name: String
        let healthy: Bool?
        let status: String?
    }

    public func fetchStatus(
        for instance: ServiceInstance, secret: String?, client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }

        var poolRequest = HTTPRequest(url: base.appendingPathComponent("api/v2.0/pool"))
        poolRequest.applyAuth(authMethod, secret: secret, config: instance.config)
        let pools = try await client.getJSON([Pool].self, from: poolRequest, tls: instance.tlsPolicy)

        var infoRequest = HTTPRequest(url: base.appendingPathComponent("api/v2.0/system/info"))
        infoRequest.applyAuth(authMethod, secret: secret, config: instance.config)
        let info = try? await client.getJSON(SystemInfo.self, from: infoRequest, tls: instance.tlsPolicy)

        let unhealthy = pools.filter { ($0.healthy ?? true) == false }.count
        let health: Health = pools.isEmpty ? .unknown : (unhealthy == 0 ? .ok : .down)

        var details = pools.map {
            DetailRow(id: "pool-\($0.name)", label: $0.name, value: $0.status ?? "-")
        }
        if let uptime = info?.uptime_seconds {
            details.append(DetailRow(id: "uptime", label: "Uptime",
                                     value: Self.uptime(Int(uptime))))
        }

        return ServiceStatus(
            health: health,
            summary: pools.isEmpty ? "No pools" : "\(pools.count - unhealthy)/\(pools.count) pools healthy",
            stats: [
                Stat(id: "pools", label: "Pools", value: "\(pools.count)",
                     raw: Double(pools.count), emphasis: .highlighted),
                Stat(id: "unhealthy", label: "Degraded", value: "\(unhealthy)",
                     raw: Double(unhealthy), emphasis: unhealthy > 0 ? .highlighted : .normal),
            ],
            details: details,
            version: info?.version
        )
    }

    private static func uptime(_ seconds: Int) -> String {
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}
