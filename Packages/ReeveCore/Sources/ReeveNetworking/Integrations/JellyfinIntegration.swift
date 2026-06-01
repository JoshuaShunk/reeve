import Foundation
import ReeveModels

/// Jellyfin, `GET /System/Info` + `GET /Sessions`, API key via `X-Emby-Token`.
/// https://jmshrv.com/posts/jellyfin-api/
public struct JellyfinIntegration: ServiceIntegration {
    public static let typeID = "jellyfin"

    public let displayName = "Jellyfin"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("play.rectangle.on.rectangle")
    public let authMethod: AuthMethod = .header(name: "X-Emby-Token")
    public var configFields: [ConfigField] { [] }

    public init() {}

    private struct SystemInfo: Decodable {
        let Version: String?
        let ServerName: String?
    }
    private struct Session: Decodable {
        let NowPlayingItem: NowPlaying?
        struct NowPlaying: Decodable { let Name: String? }
    }

    public func fetchStatus(
        for instance: ServiceInstance, secret: String?, client: HTTPClient
    ) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }

        var infoRequest = HTTPRequest(url: base.appendingPathComponent("System/Info"))
        infoRequest.applyAuth(authMethod, secret: secret, config: instance.config)
        let info = try await client.getJSON(SystemInfo.self, from: infoRequest, tls: instance.tlsPolicy)

        var sessionsRequest = HTTPRequest(url: base.appendingPathComponent("Sessions"))
        sessionsRequest.applyAuth(authMethod, secret: secret, config: instance.config)
        let sessions = (try? await client.getJSON(
            [Session].self, from: sessionsRequest, tls: instance.tlsPolicy
        )) ?? []
        let streaming = sessions.filter { $0.NowPlayingItem != nil }.count

        return ServiceStatus(
            health: .ok,
            summary: streaming == 0 ? "Idle" : "\(streaming) streaming now",
            stats: [
                Stat(id: "streams", label: "Active streams", value: "\(streaming)",
                     raw: Double(streaming), emphasis: .highlighted),
                Stat(id: "sessions", label: "Sessions", value: "\(sessions.count)",
                     raw: Double(sessions.count)),
            ],
            details: [
                DetailRow(id: "server", label: "Server", value: info.ServerName ?? "-"),
            ],
            version: info.Version
        )
    }
}
