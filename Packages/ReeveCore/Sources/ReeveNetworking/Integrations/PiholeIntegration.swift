import Foundation
import ReeveModels

/// Pi-hole v6 (the FTL REST API). Authenticates with `POST /api/auth`
/// (web password or a generated app password) to obtain a session id, then reads
/// `GET /api/stats/summary`. The SID is passed via the `X-FTL-SID` header.
/// https://docs.pi-hole.net/api/
public struct PiholeIntegration: ServiceIntegration {
    public static let typeID = "pi-hole"
    public let displayName = "Pi-hole"
    public let category: ServiceCategory = .dns
    public let iconAsset: ServiceIcon = .symbol("shield.lefthalf.filled")
    public let authMethod: AuthMethod = .sessionToken
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct AuthResponse: Decodable {
        struct Session: Decodable { let valid: Bool?; let sid: String? }
        let session: Session
    }
    private struct Summary: Decodable {
        struct Queries: Decodable {
            let total: Int?; let blocked: Int?; let percent_blocked: Double?
        }
        struct Clients: Decodable { let active: Int? }
        struct Gravity: Decodable { let domains_being_blocked: Int? }
        let queries: Queries?; let clients: Clients?; let gravity: Gravity?
    }
    private struct VersionInfo: Decodable {
        struct Component: Decodable {
            struct Local: Decodable { let version: String? }
            let local: Local?
        }
        struct Version: Decodable { let core: Component? }
        let version: Version?
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }

        // 1. Authenticate for a session id.
        var auth = HTTPRequest(method: "POST", url: base.appendingPathComponent("api/auth"))
        auth.headers["Content-Type"] = "application/json"
        auth.body = try JSONSerialization.data(withJSONObject: ["password": secret ?? ""])
        let session = try await client.getJSON(AuthResponse.self, from: auth, tls: instance.tlsPolicy).session
        guard let sid = session.sid, session.valid != false else {
            throw APIError.badStatus(401, body: "Pi-hole authentication failed")
        }
        defer { Task { await logout(base: base, sid: sid, client: client, tls: instance.tlsPolicy) } }

        func authed(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.headers["X-FTL-SID"] = sid
            return req
        }

        // 2. Read stats (+ best-effort version).
        let summary = try await client.getJSON(Summary.self, from: authed("api/stats/summary"),
                                                tls: instance.tlsPolicy)
        let version = try? await client.getJSON(VersionInfo.self, from: authed("api/info/version"),
                                                tls: instance.tlsPolicy)

        let q = summary.queries
        let total = q?.total ?? 0
        let blocked = q?.blocked ?? 0
        let pct = q?.percent_blocked ?? (total > 0 ? Double(blocked) / Double(total) * 100 : 0)
        let gravity = summary.gravity?.domains_being_blocked ?? 0

        return ServiceStatus(
            health: .ok,
            summary: "\(blocked) blocked of \(total) queries",
            stats: [
                Stat(id: "blocked", label: "Blocked", value: "\(blocked)",
                     raw: Double(blocked), emphasis: .highlighted),
                Stat(id: "block_pct", label: "Block rate",
                     value: String(format: "%.1f", pct), unit: "%", raw: pct, emphasis: .highlighted),
                Stat(id: "queries", label: "Queries", value: "\(total)", raw: Double(total)),
                Stat(id: "clients", label: "Active clients", value: "\(summary.clients?.active ?? 0)",
                     raw: Double(summary.clients?.active ?? 0)),
                Stat(id: "gravity", label: "Domains blocked", value: "\(gravity)", raw: Double(gravity)),
            ],
            version: version?.version?.core?.local?.version
        )
    }

    /// Free the session slot (Pi-hole allows a limited number). Best-effort.
    private func logout(base: URL, sid: String, client: HTTPClient, tls: TLSPolicy) async {
        var req = HTTPRequest(method: "DELETE", url: base.appendingPathComponent("api/auth"))
        req.headers["X-FTL-SID"] = sid
        _ = try? await client.send(req, tls: tls)
    }
}
