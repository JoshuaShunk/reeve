import Foundation
import ReeveModels

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Small shared helpers used by integrations that talk to APIs which (a) stringify
// numbers, (b) need a cookie/session login, or (c) require a same-origin Referer.

/// Decodes a JSON value that may arrive as a `String` OR a number/bool. SABnzbd and
/// Tautulli routinely return numerics as strings (e.g. `"kbpersec": "1234.5"`,
/// `"stream_count": "2"`), so a plain `Int`/`Double` decode would throw.
struct LossyString: Decodable, Sendable, Hashable {
    let string: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { string = s }
        else if let i = try? c.decode(Int.self) { string = String(i) }
        else if let d = try? c.decode(Double.self) { string = String(d) }
        else if let b = try? c.decode(Bool.self) { string = b ? "true" : "false" }
        else { string = "" }
    }

    var double: Double? { Double(string.trimmingCharacters(in: .whitespaces)) }
    var int: Int? { int(from: string) }

    private func int(from s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return Int(t) ?? Double(t).map(Int.init)
    }
}

extension URL {
    /// `scheme://host[:port]` for a request — used as the `Referer`/`Origin` header
    /// that qBittorrent's CSRF check requires (a mismatch is a hard 403).
    var requestOrigin: String? {
        guard let scheme, let host else { return nil }
        return port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }
}

extension HTTPURLResponse {
    /// Reads a single cookie value out of the `Set-Cookie` header (cookie-based
    /// session logins like qBittorrent's `SID`).
    func cookieValue(named name: String) -> String? {
        guard let raw = value(forHTTPHeaderField: "Set-Cookie") else { return nil }
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == name {
                return kv[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

extension HTTPClient {
    /// Send a request, check the status, and return the body as UTF-8 text. For
    /// endpoints that answer in plain text rather than JSON (e.g. qBittorrent's
    /// `/app/version`).
    func getText(from request: HTTPRequest, tls: TLSPolicy) async throws -> String {
        let (data, response) = try await send(request, tls: tls)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.badStatus(response.statusCode, body: String(data: data, encoding: .utf8))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// `application/x-www-form-urlencoded` body builder (qBittorrent login).
func formURLEncode(_ fields: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let pairs = fields.map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(k)=\(v)"
    }
    return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
}
