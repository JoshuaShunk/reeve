import Foundation

/// How the app should evaluate the TLS certificate of a Proxmox host.
/// Homelab Proxmox installs almost always use a self-signed certificate.
public enum TLSPolicy: Sendable, Equatable, Hashable, Codable {
    /// Standard system trust evaluation (use when you have a real/CA-signed cert).
    case system
    /// Accept any certificate. No MITM protection, explicit opt-in only.
    case allowInsecure
    /// Trust-on-first-use: pin the leaf certificate's SHA-256 fingerprint
    /// (lowercase hex, no separators) captured when the user first connected.
    case pinnedSHA256(String)
}

/// An immutable, `Sendable` description of how to reach one Proxmox endpoint,
/// including the resolved API-token secret. Built by the persistence layer from a
/// stored `ServerProfile` plus the secret read from the Keychain, never persisted
/// directly, so secrets don't live in plist/JSON.
public struct ServerConnection: Sendable, Equatable {
    public var baseURL: URL
    /// e.g. `root@pam!homelabapp`
    public var tokenID: String
    /// The token secret (UUID), read from the Keychain at use time.
    public var tokenSecret: String
    public var tlsPolicy: TLSPolicy

    public init(baseURL: URL, tokenID: String, tokenSecret: String, tlsPolicy: TLSPolicy) {
        self.baseURL = baseURL
        self.tokenID = tokenID
        self.tokenSecret = tokenSecret
        self.tlsPolicy = tlsPolicy
    }

    /// The exact `Authorization` header value Proxmox expects.
    /// Note: no `Bearer` prefix, and token auth needs no CSRF token.
    public var authorizationHeader: String {
        "PVEAPIToken=\(tokenID)=\(tokenSecret)"
    }

    public var host: String { baseURL.host ?? "" }
}
