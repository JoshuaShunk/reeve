import Foundation
import ReeveModels

// MARK: - Traefik (reverse proxy; API has no built-in auth)

/// Traefik. `GET /api/overview` for router/service counts and `GET /api/version`.
/// The Traefik API has no authentication of its own (it's secured by network or a
/// middleware), so no secret is collected.
/// https://doc.traefik.io/traefik/operations/api/
public struct TraefikIntegration: ServiceIntegration {
    public static let typeID = "traefik"
    public let displayName = "Traefik"
    public let category: ServiceCategory = .network
    public let iconAsset: ServiceIcon = .symbol("arrow.triangle.branch")
    public let authMethod: AuthMethod = .none
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Overview: Decodable {
        struct Section: Decodable { let total: Int?; let warnings: Int?; let errors: Int? }
        struct Scheme: Decodable { let routers: Section?; let services: Section? }
        let http: Scheme?
    }
    private struct Version: Decodable { let Version: String? }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        let overview = try await client.getJSON(Overview.self,
                                                from: HTTPRequest(url: base.appendingPathComponent("api/overview")),
                                                tls: instance.tlsPolicy)
        let version = try? await client.getJSON(Version.self,
                                                from: HTTPRequest(url: base.appendingPathComponent("api/version")),
                                                tls: instance.tlsPolicy)

        let routers = overview.http?.routers
        let services = overview.http?.services
        let errors = (routers?.errors ?? 0) + (services?.errors ?? 0)
        let warnings = (routers?.warnings ?? 0) + (services?.warnings ?? 0)

        return ServiceStatus(
            health: errors > 0 ? .down : (warnings > 0 ? .warn : .ok),
            summary: "\(routers?.total ?? 0) routers · \(services?.total ?? 0) services",
            stats: [
                Stat(id: "routers", label: "Routers", value: "\(routers?.total ?? 0)",
                     raw: Double(routers?.total ?? 0), emphasis: .highlighted),
                Stat(id: "services", label: "Services", value: "\(services?.total ?? 0)",
                     raw: Double(services?.total ?? 0), emphasis: .highlighted),
                Stat(id: "warnings", label: "Warnings", value: "\(warnings)", raw: Double(warnings),
                     emphasis: warnings > 0 ? .highlighted : .normal),
                Stat(id: "errors", label: "Errors", value: "\(errors)", raw: Double(errors),
                     emphasis: errors > 0 ? .highlighted : .normal),
            ],
            version: version?.Version
        )
    }
}

// MARK: - Speedtest Tracker (Bearer; download/upload are BYTES/sec)

/// Speedtest Tracker. `GET /api/v1/results/latest` (Bearer token). Note: `download`
/// and `upload` are **bytes per second** — multiply by 8 for bits, then by 1e-6 for
/// Mbps. https://docs.speedtest-tracker.dev/
public struct SpeedtestTrackerIntegration: ServiceIntegration {
    public static let typeID = "speedtest-tracker"
    public let displayName = "Speedtest Tracker"
    public let category: ServiceCategory = .network
    public let iconAsset: ServiceIcon = .symbol("speedometer")
    public let authMethod: AuthMethod = .bearer
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Response: Decodable { let data: Result }
    private struct Result: Decodable {
        let ping: Double?
        let download: Double?     // bytes/sec
        let upload: Double?       // bytes/sec
        let healthy: Bool?
        let status: String?
        let created_at: String?
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        var req = HTTPRequest(url: base.appendingPathComponent("api/v1/results/latest"))
        req.applyAuth(authMethod, secret: secret, config: instance.config)
        let result = try await client.getJSON(Response.self, from: req, tls: instance.tlsPolicy).data

        let downMbps = (result.download ?? 0) * 8 / 1_000_000
        let upMbps = (result.upload ?? 0) * 8 / 1_000_000
        let ping = result.ping ?? 0
        let healthy = result.healthy ?? true

        var details: [DetailRow] = []
        if let when = result.created_at { details.append(DetailRow(id: "when", label: "Last test", value: when)) }
        if let status = result.status { details.append(DetailRow(id: "status", label: "Result", value: status)) }

        return ServiceStatus(
            health: healthy ? .ok : .warn,
            summary: String(format: "↓ %.0f · ↑ %.0f Mbps · %.0f ms", downMbps, upMbps, ping),
            stats: [
                Stat(id: "download", label: "Download", value: String(format: "%.1f", downMbps),
                     unit: " Mbps", raw: downMbps, emphasis: .highlighted),
                Stat(id: "upload", label: "Upload", value: String(format: "%.1f", upMbps),
                     unit: " Mbps", raw: upMbps, emphasis: .highlighted),
                Stat(id: "ping", label: "Ping", value: String(format: "%.0f", ping), unit: " ms", raw: ping),
            ],
            details: details
        )
    }
}
