import Foundation
import ReeveModels

// MARK: - qBittorrent (cookie session; CSRF requires a same-origin Referer)

/// qBittorrent WebUI API v2. Logs in with `POST /api/v2/auth/login` (form body) to
/// obtain the `SID` cookie, then reads `/api/v2/transfer/info` and
/// `/api/v2/torrents/info`. Every request carries a `Referer` matching the host —
/// without it qBittorrent's CSRF guard returns 403.
/// https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)
public struct QBittorrentIntegration: ServiceIntegration {
    public static let typeID = "qbittorrent"
    public let displayName = "qBittorrent"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("arrow.down.circle")
    public let authMethod: AuthMethod = .sessionToken
    public var configFields: [ConfigField] {
        [ConfigField(key: "username", label: "Username", kind: .text,
                     placeholder: "admin", defaultValue: "admin", isRequired: true)]
    }
    public init() {}

    private struct Transfer: Decodable {
        let dl_info_speed: Int?; let up_info_speed: Int?
        let dl_info_data: Int?; let up_info_data: Int?
        let connection_status: String?
    }
    private struct Torrent: Decodable { let state: String? }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL else { throw APIError.invalidURL }
        let origin = base.requestOrigin

        // 1. Log in for the SID cookie.
        var login = HTTPRequest(method: "POST", url: base.appendingPathComponent("api/v2/auth/login"))
        login.headers["Content-Type"] = "application/x-www-form-urlencoded"
        if let origin { login.headers["Referer"] = origin }
        login.body = formURLEncode([
            "username": instance.config["username"] ?? "admin",
            "password": secret ?? "",
        ])
        let (body, response) = try await client.send(login, tls: instance.tlsPolicy)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.badStatus(response.statusCode, body: String(data: body, encoding: .utf8))
        }
        guard let sid = response.cookieValue(named: "SID") else {
            // 200 with "Fails." means bad credentials; otherwise no cookie was set.
            throw APIError.badStatus(403, body: "qBittorrent login failed (check credentials / Referer)")
        }

        func authed(_ path: String) -> HTTPRequest {
            var req = HTTPRequest(url: base.appendingPathComponent(path))
            req.headers["Cookie"] = "SID=\(sid)"
            if let origin { req.headers["Referer"] = origin }
            return req
        }

        // 2. Read transfer + torrent state.
        let transfer = try await client.getJSON(Transfer.self, from: authed("api/v2/transfer/info"),
                                                 tls: instance.tlsPolicy)
        let torrents = (try? await client.getJSON([Torrent].self, from: authed("api/v2/torrents/info"),
                                                   tls: instance.tlsPolicy)) ?? []
        let version = try? await client.getText(from: authed("api/v2/app/version"), tls: instance.tlsPolicy)

        let states = torrents.compactMap(\.state)
        let downloading = states.filter {
            ["downloading", "metaDL", "forcedDL", "forcedMetaDL", "queuedDL", "stalledDL", "checkingDL"].contains($0)
        }.count
        let seeding = states.filter {
            ["uploading", "forcedUP", "queuedUP", "stalledUP", "checkingUP"].contains($0)
        }.count
        let errored = states.filter { ["error", "missingFiles"].contains($0) }.count

        let dl = ByteCountFormatter.string(fromByteCount: Int64(transfer.dl_info_speed ?? 0), countStyle: .binary)
        let up = ByteCountFormatter.string(fromByteCount: Int64(transfer.up_info_speed ?? 0), countStyle: .binary)
        let connected = (transfer.connection_status ?? "") == "connected"

        return ServiceStatus(
            health: errored > 0 ? .warn : (connected ? .ok : .warn),
            summary: downloading > 0 ? "↓ \(dl)/s · \(downloading) downloading" : "\(torrents.count) torrents",
            stats: [
                Stat(id: "dl", label: "Download", value: "\(dl)/s", raw: Double(transfer.dl_info_speed ?? 0),
                     emphasis: .highlighted),
                Stat(id: "up", label: "Upload", value: "\(up)/s", raw: Double(transfer.up_info_speed ?? 0),
                     emphasis: .highlighted),
                Stat(id: "downloading", label: "Downloading", value: "\(downloading)", raw: Double(downloading)),
                Stat(id: "seeding", label: "Seeding", value: "\(seeding)", raw: Double(seeding)),
                Stat(id: "total", label: "Torrents", value: "\(torrents.count)", raw: Double(torrents.count)),
            ],
            details: [DetailRow(id: "connection", label: "Connection",
                                value: transfer.connection_status ?? "-")]
                + (errored > 0 ? [DetailRow(id: "errored", label: "Errored", value: "\(errored)")] : []),
            version: version?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - SABnzbd (Usenet; ?apikey=&mode=queue&output=json — numerics arrive as strings)

/// SABnzbd. Simple API-key auth via query param; the queue snapshot returns most
/// numbers as strings, hence `LossyString`.
/// https://sabnzbd.org/wiki/configuration/5.0/api
public struct SABnzbdIntegration: ServiceIntegration {
    public static let typeID = "sabnzbd"
    public let displayName = "SABnzbd"
    public let category: ServiceCategory = .media
    public let iconAsset: ServiceIcon = .symbol("arrow.down.doc")
    public let authMethod: AuthMethod = .queryItem(name: "apikey")
    public var configFields: [ConfigField] { [] }
    public init() {}

    private struct Response: Decodable { let queue: Queue }
    private struct Queue: Decodable {
        let status: String?
        let paused: Bool?
        let speed: LossyString?
        let kbpersec: LossyString?
        let mb: LossyString?
        let mbleft: LossyString?
        let sizeleft: String?
        let timeleft: String?
        let noofslots_total: LossyString?
        let diskspace1: LossyString?
        let diskspacetotal1: LossyString?
        let version: String?
    }

    public func fetchStatus(for instance: ServiceInstance, secret: String?, client: HTTPClient) async throws -> ServiceStatus {
        guard let base = instance.baseURL,
              var comp = URLComponents(url: base.appendingPathComponent("api"), resolvingAgainstBaseURL: false)
        else { throw APIError.invalidURL }
        comp.queryItems = [URLQueryItem(name: "mode", value: "queue"),
                           URLQueryItem(name: "output", value: "json")]
        guard let url = comp.url else { throw APIError.invalidURL }
        var req = HTTPRequest(url: url)
        req.applyAuth(authMethod, secret: secret, config: instance.config)

        let queue = try await client.getJSON(Response.self, from: req, tls: instance.tlsPolicy).queue
        let paused = queue.paused ?? (queue.status?.lowercased() == "paused")
        let items = queue.noofslots_total?.int ?? 0
        let speed = queue.kbpersec?.double ?? 0          // KB/s
        let mbLeft = queue.mbleft?.double ?? 0
        let diskFree = queue.diskspace1?.double           // GB
        let diskTotal = queue.diskspacetotal1?.double      // GB

        var stats: [Stat] = [
            Stat(id: "speed", label: "Speed",
                 value: String(format: "%.1f", speed / 1024), unit: " MB/s",
                 raw: speed, emphasis: .highlighted),
            Stat(id: "queue", label: "Queued", value: "\(items)", raw: Double(items), emphasis: .highlighted),
            Stat(id: "remaining", label: "Remaining",
                 value: queue.sizeleft ?? String(format: "%.0f MB", mbLeft), raw: mbLeft),
        ]
        if let free = diskFree {
            stats.append(Stat(id: "disk", label: "Disk free",
                              value: String(format: "%.0f", free), unit: " GB", raw: free))
        }

        let health: Health = paused ? .warn : .ok
        var details: [DetailRow] = [DetailRow(id: "status", label: "Status",
                                              value: queue.status ?? (paused ? "Paused" : "Idle"))]
        if let free = diskFree, let total = diskTotal {
            details.append(DetailRow(id: "diskspace", label: "Disk",
                                     value: String(format: "%.0f of %.0f GB", free, total)))
        }

        return ServiceStatus(
            health: health,
            summary: items == 0 ? "Idle" : "\(items) queued · \(String(format: "%.1f", speed / 1024)) MB/s",
            stats: stats,
            details: details,
            version: queue.version
        )
    }
}
