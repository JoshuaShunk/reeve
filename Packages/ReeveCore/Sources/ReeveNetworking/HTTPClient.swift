import Foundation
import ReeveModels

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A minimal request value passed to `HTTPClient`. Integrations build these.
public struct HTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(
        method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil
    ) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }

    /// Apply a data-declared `AuthMethod` using the instance's secret/config, so
    /// most integrations need no auth code.
    public mutating func applyAuth(
        _ method: AuthMethod, secret: String?, config: [String: String]
    ) {
        switch method {
        case .none, .sessionToken, .custom:
            return
        case .bearer:
            if let secret { headers["Authorization"] = "Bearer \(secret)" }
        case .basic(let usernameField):
            let user = config[usernameField] ?? ""
            let pass = secret ?? ""
            if let token = "\(user):\(pass)".data(using: .utf8)?.base64EncodedString() {
                headers["Authorization"] = "Basic \(token)"
            }
        case .header(let name):
            if let secret { headers[name] = secret }
        case .queryItem(let name):
            if let secret,
               var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                comp.queryItems = (comp.queryItems ?? []) + [URLQueryItem(name: name, value: secret)]
                if let updated = comp.url { url = updated }
            }
        }
    }
}

/// Injected into every integration. Live impl wraps `URLSession` and reuses the
/// per-host TLS trust handling so self-signed homelab services work; tests inject
/// a stub (or the existing `MockURLProtocol`).
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest, tls: TLSPolicy) async throws -> (Data, HTTPURLResponse)
}

extension HTTPClient {
    /// Send + status check + JSON decode in one call.
    public func getJSON<T: Decodable>(
        _ type: T.Type, from request: HTTPRequest, tls: TLSPolicy
    ) async throws -> T {
        let (data, response) = try await send(request, tls: tls)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.badStatus(response.statusCode, body: String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

/// `URLSession`-backed client reusing `ProxmoxTrustDelegate` for self-signed certs.
public final class LiveHTTPClient: HTTPClient {
    private let session: URLSession
    private let trustDelegate: ProxmoxTrustDelegate

    public init() {
        let delegate = ProxmoxTrustDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.trustDelegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func send(
        _ request: HTTPRequest, tls: TLSPolicy
    ) async throws -> (Data, HTTPURLResponse) {
        if let host = request.url.host { trustDelegate.setPolicy(tls, forHost: host) }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("Non-HTTP response")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorServerCertificateUntrusted
                || nsError.code == NSURLErrorCancelled {
                throw APIError.untrustedCertificate(host: request.url.host ?? "")
            }
            throw APIError.transport(error.localizedDescription)
        }
    }
}
