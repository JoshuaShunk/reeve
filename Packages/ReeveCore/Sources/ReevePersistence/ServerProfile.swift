import Foundation
import ReeveModels

/// A saved server the user can monitor. Stored as JSON (UserDefaults / App Group);
/// the token *secret* is never stored here, it lives in the Keychain keyed by `id`.
public struct ServerProfile: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var useHTTPS: Bool
    /// Full Proxmox token id, e.g. `root@pam!homelabapp`.
    public var tokenID: String
    public var tlsPolicy: TLSPolicy

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 8006,
        useHTTPS: Bool = true,
        tokenID: String,
        tlsPolicy: TLSPolicy = .allowInsecure
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useHTTPS = useHTTPS
        self.tokenID = tokenID
        self.tlsPolicy = tlsPolicy
    }

    public var baseURL: URL? {
        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"
        components.host = host
        components.port = port
        return components.url
    }

    /// True when this profile points at the built-in demo dataset.
    public var isDemo: Bool { DemoMode.isDemo(host: host) }

    /// Combine this profile with a secret to produce a usable connection.
    public func connection(secret: String) -> ServerConnection? {
        guard let baseURL else { return nil }
        return ServerConnection(
            baseURL: baseURL,
            tokenID: tokenID,
            tokenSecret: secret,
            tlsPolicy: tlsPolicy
        )
    }
}
