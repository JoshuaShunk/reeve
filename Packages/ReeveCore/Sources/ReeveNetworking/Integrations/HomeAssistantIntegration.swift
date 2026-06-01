import Foundation
import ReeveModels

/// Home Assistant, `GET /api/` (health) + `GET /api/states`, Bearer long-lived
/// access token. https://developers.home-assistant.io/docs/api/rest/
public struct HomeAssistantIntegration: ServiceIntegration {
    public static let typeID = "home-assistant"

    public let displayName = "Home Assistant"
    public let category: ServiceCategory = .automation
    public let iconAsset: ServiceIcon = .symbol("house.fill")
    public let authMethod: AuthMethod = .bearer
    public var configFields: [ConfigField] { [] }

    public init() {}

    private struct EntityState: Decodable {
        let entity_id: String
        let state: String?
    }

    public func fetchStatus(
        for instance: ServiceInstance, secret: String?, client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        var request = HTTPRequest(url: base.appendingPathComponent("api/states"))
        request.applyAuth(authMethod, secret: secret, config: instance.config)

        let states = try await client.getJSON([EntityState].self, from: request, tls: instance.tlsPolicy)
        let unavailable = states.filter { ($0.state ?? "") == "unavailable" }.count

        return ServiceStatus(
            health: unavailable == 0 ? .ok : .warn,
            summary: "\(states.count) entities",
            stats: [
                Stat(id: "entities", label: "Entities", value: "\(states.count)",
                     raw: Double(states.count), emphasis: .highlighted),
                Stat(id: "unavailable", label: "Unavailable", value: "\(unavailable)",
                     raw: Double(unavailable), emphasis: unavailable > 0 ? .highlighted : .normal),
            ]
        )
    }
}
