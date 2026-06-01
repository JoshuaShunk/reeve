import Foundation
import ReeveModels

/// n8n (workflow automation). API key via the `X-N8N-API-KEY` header. Counts total
/// and active workflows from `/api/v1/workflows`, plus recent failed executions
/// from `/api/v1/executions?status=error`.
/// https://docs.n8n.io/api/
public struct N8nIntegration: ServiceIntegration {
    public static let typeID = "n8n"
    public let displayName = "n8n"
    public let category: ServiceCategory = .automation
    public let iconAsset: ServiceIcon = .symbol("point.3.connected.trianglepath.dotted")
    public let authMethod: AuthMethod = .header(name: "X-N8N-API-KEY")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Workflows: Decodable {
        struct Workflow: Decodable { let active: Bool? }
        let data: [Workflow]
    }
    private struct Executions: Decodable {
        struct Execution: Decodable { let id: Double? }
        let data: [Execution]
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String, query: [URLQueryItem] = []) throws -> HTTPRequest {
            guard var comp = URLComponents(url: base.appendingPathComponent(path),
                                           resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
            if !query.isEmpty { comp.queryItems = query }
            guard let url = comp.url else { throw APIError.invalidURL }
            var req = HTTPRequest(url: url)
            req.applyAuth(authMethod, secret: secret, config: instance.config)
            return req
        }

        let workflows = try await client.getJSON(Workflows.self, from: request("api/v1/workflows"),
                                                  tls: instance.tlsPolicy)
        let failed = try? await client.getJSON(
            Executions.self,
            from: request("api/v1/executions", query: [
                URLQueryItem(name: "status", value: "error"),
                URLQueryItem(name: "limit", value: "100"),
            ]),
            tls: instance.tlsPolicy
        )

        let total = workflows.data.count
        let active = workflows.data.filter { $0.active == true }.count
        let errors = failed?.data.count ?? 0

        return ServiceStatus(
            health: errors > 0 ? .warn : .ok,
            summary: "\(active)/\(total) workflows active",
            stats: [
                Stat(id: "active", label: "Active", value: "\(active)", raw: Double(active),
                     emphasis: .highlighted),
                Stat(id: "total", label: "Workflows", value: "\(total)", raw: Double(total),
                     emphasis: .highlighted),
                Stat(id: "errors", label: "Recent failures", value: "\(errors)", raw: Double(errors),
                     emphasis: errors > 0 ? .highlighted : .normal),
            ]
        )
    }
}
