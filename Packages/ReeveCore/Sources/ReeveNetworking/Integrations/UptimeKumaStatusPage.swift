import Foundation
import ReeveModels

// MARK: - Uptime Kuma status page (public, no auth)

/// A decoded Uptime Kuma *status page*, the public dashboard a user builds at
/// `/status/<slug>`. Combines the page layout (`/api/status-page/<slug>`) with
/// live heartbeats and uptime (`/api/status-page/heartbeat/<slug>`).
public struct UptimeKumaStatusPage: Sendable {
    public struct Beat: Identifiable, Sendable, Hashable {
        public let id: Int
        public let status: Int      // 0 down, 1 up, 2 pending, 3 maintenance
        public let time: String?
        public let ping: Int?
        public let msg: String?
    }

    public struct Monitor: Identifiable, Sendable, Hashable {
        public let id: Int
        public let name: String
        public let type: String?            // "http", "group", "dns", "port", ...
        public let beats: [Beat]            // oldest → newest
        public let uptime24h: Double?       // 0...1

        public var isGroup: Bool { type == "group" }
        public var latestStatus: Int? { beats.last?.status }
        public var latestBeat: Beat? { beats.last }
        public var latestPing: Int? { beats.last(where: { $0.ping != nil })?.ping }
    }

    public struct Group: Identifiable, Sendable, Hashable {
        public let id: Int
        public let name: String
        public let monitors: [Monitor]
    }

    public let title: String?
    public let descriptionText: String?
    public let groups: [Group]

    /// Worst status across all monitors, for an overall banner.
    public var overall: Int? {
        let statuses = groups.flatMap(\.monitors).compactMap(\.latestStatus)
        if statuses.isEmpty { return nil }
        if statuses.contains(0) { return 0 }
        if statuses.contains(2) { return 2 }
        if statuses.contains(3) { return 3 }
        return 1
    }
}

extension HTTPClient {
    /// Fetch and assemble an Uptime Kuma status page by slug. Both endpoints are
    /// public, so no secret is needed.
    public func uptimeKumaStatusPage(
        slug: String, baseURL: URL, tls: TLSPolicy
    ) async throws -> UptimeKumaStatusPage {
        func makeURL(_ path: String) throws -> URL {
            let root = baseURL.absoluteString.hasSuffix("/")
                ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
            guard let url = URL(string: root + path) else { throw APIError.invalidURL }
            return url
        }

        async let pageTask = getJSON(
            UptimeKumaPageResponse.self,
            from: HTTPRequest(url: try makeURL("/api/status-page/\(slug)")), tls: tls
        )
        async let beatTask = getJSON(
            UptimeKumaHeartbeatResponse.self,
            from: HTTPRequest(url: try makeURL("/api/status-page/heartbeat/\(slug)")), tls: tls
        )
        let page = try await pageTask
        let hb = try await beatTask

        let groups = (page.publicGroupList ?? []).map { group in
            UptimeKumaStatusPage.Group(
                id: group.id ?? group.name.hashValue,
                name: group.name,
                monitors: (group.monitorList ?? []).map { monitor in
                    let key = String(monitor.id)
                    let beats = (hb.heartbeatList?[key] ?? []).enumerated().map { index, beat in
                        UptimeKumaStatusPage.Beat(
                            id: index, status: beat.status ?? -1,
                            time: beat.time, ping: beat.ping, msg: beat.msg
                        )
                    }
                    return UptimeKumaStatusPage.Monitor(
                        id: monitor.id, name: monitor.name, type: monitor.type, beats: beats,
                        uptime24h: hb.uptimeList?["\(monitor.id)_24"]
                    )
                }
            )
        }
        return UptimeKumaStatusPage(
            title: page.config?.title, descriptionText: page.config?.description, groups: groups
        )
    }
}

// MARK: - Wire formats (top-level: types can't nest in a protocol extension)

private struct UptimeKumaPageResponse: Decodable {
    struct Config: Decodable { let title: String?; let description: String? }
    struct Group: Decodable {
        let id: Int?; let name: String; let monitorList: [Monitor]?
    }
    struct Monitor: Decodable { let id: Int; let name: String; let type: String? }
    let config: Config?
    let publicGroupList: [Group]?
}

private struct UptimeKumaHeartbeatResponse: Decodable {
    struct Beat: Decodable {
        let status: Int?; let time: String?; let ping: Int?; let msg: String?
    }
    let heartbeatList: [String: [Beat]]?
    let uptimeList: [String: Double]?
}
