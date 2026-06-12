import Foundation

/// The bundle of server profiles (and their secrets) the iPhone pushes to the
/// paired Apple Watch over WatchConnectivity. The watch stores the metadata in
/// its own `UserDefaults` and the secrets in its own Keychain; App Groups and the
/// Keychain do not cross between the two devices, so this is the only channel.
///
/// `secrets` is keyed by `ServerProfile.id.uuidString`. Demo profiles are excluded
/// by the sender (the demo dataset needs no real credentials).
public struct WatchSyncPayload: Codable, Sendable, Equatable {
    public var profiles: [ServerProfile]
    public var secrets: [String: String]
    public var selectedID: UUID?
    public var updatedAt: Date

    public init(
        profiles: [ServerProfile],
        secrets: [String: String],
        selectedID: UUID?,
        updatedAt: Date = Date()
    ) {
        self.profiles = profiles
        self.secrets = secrets
        self.selectedID = selectedID
        self.updatedAt = updatedAt
    }
}
