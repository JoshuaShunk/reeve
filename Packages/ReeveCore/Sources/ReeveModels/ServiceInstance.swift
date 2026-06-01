import Foundation

/// A user's configured deployment of a service type. Stored as Codable JSON;
/// the secret is NOT here, it lives in the Keychain keyed by `id`.
public struct ServiceInstance: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var typeID: String
    public var name: String
    public var baseURLString: String
    public var tlsPolicy: TLSPolicy
    /// Non-secret config values keyed by `ConfigField.key`.
    public var config: [String: String]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        typeID: String,
        name: String,
        baseURLString: String,
        tlsPolicy: TLSPolicy = .allowInsecure,
        config: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id; self.typeID = typeID; self.name = name
        self.baseURLString = baseURLString; self.tlsPolicy = tlsPolicy
        self.config = config; self.isEnabled = isEnabled
    }

    public var baseURL: URL? { URL(string: baseURLString) }
}
