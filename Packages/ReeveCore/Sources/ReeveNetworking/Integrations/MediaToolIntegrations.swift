import Foundation
import ReeveModels

// MARK: - Bazarr (subtitles; X-API-KEY header)

/// Bazarr. `GET /api/system/status` (wrapped in `data`) for the version and
/// `GET /api/badges` (not wrapped) for wanted-subtitle counts and health.
/// https://github.com/morpheus65535/bazarr
public struct BazarrIntegration: ServiceIntegration {
    public static let typeID = "bazarr"
    public let displayName = "Bazarr"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("captions.bubble")
    public let authMethod: AuthMethod = .header(name: "X-API-KEY")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct StatusResponse: Decodable {
        struct Data: Decodable { let bazarr_version: String? }
        let data: Data
    }
    private struct Badges: Decodable {
        let episodes: Int?       // wanted episode subtitles
        let movies: Int?         // wanted movie subtitles
        let providers: Int?      // throttled/problem providers
        let status: Int?         // health-issue count
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.applyAuth(authMethod, secret: secret, config: instance.config)
            return req
        }

        let badges = try await client.getJSON(Badges.self, from: request("api/badges"),
                                               tls: instance.tlsPolicy)
        let status = try? await client.getJSON(StatusResponse.self, from: request("api/system/status"),
                                                tls: instance.tlsPolicy)

        let wantedEpisodes = badges.episodes ?? 0
        let wantedMovies = badges.movies ?? 0
        let wanted = wantedEpisodes + wantedMovies
        let issues = badges.status ?? 0
        let throttled = badges.providers ?? 0

        return ServiceStatus(
            health: issues > 0 ? .warn : .ok,
            summary: wanted == 0 ? "No missing subtitles" : "\(wanted) wanted subtitle(s)",
            stats: [
                Stat(id: "episodes", label: "Episodes wanted", value: "\(wantedEpisodes)",
                     raw: Double(wantedEpisodes), emphasis: .highlighted),
                Stat(id: "movies", label: "Movies wanted", value: "\(wantedMovies)",
                     raw: Double(wantedMovies), emphasis: .highlighted),
                Stat(id: "providers", label: "Throttled providers", value: "\(throttled)",
                     raw: Double(throttled), emphasis: throttled > 0 ? .highlighted : .normal),
                Stat(id: "issues", label: "Health issues", value: "\(issues)", raw: Double(issues)),
            ],
            version: status?.data.bazarr_version
        )
    }
}

// MARK: - Tautulli (Plex monitoring; ?apikey=&cmd= — some fields stringified)

/// Tautulli. `?apikey=&cmd=get_activity` for live streams (and `get_server_info`
/// for the PMS name/version). Responses wrap data in `response.data`.
/// https://github.com/Tautulli/Tautulli/blob/master/API.md
public struct TautulliIntegration: ServiceIntegration {
    public static let typeID = "tautulli"
    public let displayName = "Tautulli"
    public let category: ServiceCategory = .monitoring
    public let iconAsset: ServiceIcon = .symbol("chart.bar.xaxis")
    public let authMethod: AuthMethod = .queryItem(name: "apikey")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Wrapper<T: Decodable>: Decodable {
        struct Response: Decodable { let result: String?; let data: T? }
        let response: Response
    }
    private struct Activity: Decodable {
        let stream_count: LossyString?
        let stream_count_transcode: Int?
        let total_bandwidth: Int?
    }
    private struct ServerInfo: Decodable { let pms_name: String?; let pms_version: String? }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        func request(_ cmd: String) throws -> HTTPRequest {
            guard var comp = URLComponents(url: base.appendingPathComponent("api/v2"),
                                           resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
            comp.queryItems = [URLQueryItem(name: "cmd", value: cmd)]
            guard let url = comp.url else { throw APIError.invalidURL }
            var req = HTTPRequest(url: url)
            req.applyAuth(authMethod, secret: secret, config: instance.config)
            return req
        }

        let activity = try await client.getJSON(Wrapper<Activity>.self, from: request("get_activity"),
                                                 tls: instance.tlsPolicy).response.data
        let server = try? await client.getJSON(Wrapper<ServerInfo>.self, from: request("get_server_info"),
                                               tls: instance.tlsPolicy).response.data

        let streams = activity?.stream_count?.int ?? 0
        let transcodes = activity?.stream_count_transcode ?? 0
        let bandwidthKbps = activity?.total_bandwidth ?? 0       // Tautulli reports kbps
        let mbps = Double(bandwidthKbps) / 1000

        var details: [DetailRow] = []
        if let name = server?.pms_name { details.append(DetailRow(id: "server", label: "Server", value: name)) }

        return ServiceStatus(
            health: .ok,
            summary: streams == 0 ? "No active streams" : "\(streams) stream(s) playing",
            stats: [
                Stat(id: "streams", label: "Streams", value: "\(streams)", raw: Double(streams),
                     emphasis: .highlighted),
                Stat(id: "transcodes", label: "Transcodes", value: "\(transcodes)", raw: Double(transcodes),
                     emphasis: transcodes > 0 ? .highlighted : .normal),
                Stat(id: "bandwidth", label: "Bandwidth",
                     value: String(format: "%.1f", mbps), unit: " Mbps", raw: mbps),
            ],
            details: details,
            version: server?.pms_version
        )
    }
}
