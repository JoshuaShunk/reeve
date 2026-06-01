import Foundation
import ReeveModels

/// Immich (self-hosted photo & video backup). API key via the `x-api-key` header.
/// Reads `/api/server/statistics` (needs the `server.statistics` key permission),
/// `/api/server/storage`, and `/api/server/about`.
/// https://immich.app/docs/api/
public struct ImmichIntegration: ServiceIntegration {
    public static let typeID = "immich"
    public let displayName = "Immich"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("photo.stack")
    public let authMethod: AuthMethod = .header(name: "x-api-key")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Statistics: Decodable { let photos: Int?; let videos: Int?; let usage: Int? }
    private struct Storage: Decodable {
        let diskUse: String?; let diskSize: String?; let diskUsagePercentage: Double?
    }
    private struct About: Decodable { let version: String? }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.applyAuth(authMethod, secret: secret, config: instance.config)
            return req
        }

        // `about` is the cheapest authenticated call and confirms reachability.
        let about = try await client.getJSON(About.self, from: request("api/server/about"),
                                              tls: instance.tlsPolicy)
        let stats = try? await client.getJSON(Statistics.self, from: request("api/server/statistics"),
                                               tls: instance.tlsPolicy)
        let storage = try? await client.getJSON(Storage.self, from: request("api/server/storage"),
                                                 tls: instance.tlsPolicy)

        let photos = stats?.photos ?? 0
        let videos = stats?.videos ?? 0
        var rows: [Stat] = [
            Stat(id: "photos", label: "Photos", value: "\(photos)", raw: Double(photos), emphasis: .highlighted),
            Stat(id: "videos", label: "Videos", value: "\(videos)", raw: Double(videos), emphasis: .highlighted),
        ]
        if let usage = stats?.usage {
            rows.append(Stat(id: "usage", label: "Library size",
                             value: ByteCountFormatter.string(fromByteCount: Int64(usage), countStyle: .binary),
                             raw: Double(usage)))
        }
        if let pct = storage?.diskUsagePercentage {
            rows.append(Stat(id: "disk", label: "Disk used",
                             value: String(format: "%.0f", pct), unit: "%", raw: pct))
        }

        var details: [DetailRow] = []
        if let use = storage?.diskUse, let size = storage?.diskSize {
            details.append(DetailRow(id: "disk", label: "Disk", value: "\(use) of \(size)"))
        }

        return ServiceStatus(
            health: .ok,
            summary: "\(photos) photos, \(videos) videos",
            stats: rows,
            details: details,
            version: about.version
        )
    }
}
