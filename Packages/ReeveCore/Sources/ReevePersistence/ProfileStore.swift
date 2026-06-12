import Foundation
import ReeveModels
import Observation

/// Observable store of saved `ServerProfile`s. Profile metadata is persisted as
/// JSON in `UserDefaults`; secrets are kept in the Keychain via `KeychainStore`.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [ServerProfile] = []
    public var selectedID: UUID?

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let storageKey = "homelab.serverProfiles"

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        load()
    }

    public var selectedProfile: ServerProfile? {
        guard let selectedID else { return profiles.first }
        return profiles.first { $0.id == selectedID } ?? profiles.first
    }

    // MARK: - CRUD

    /// Insert or update a profile, storing its secret in the Keychain.
    public func save(_ profile: ServerProfile, secret: String?) throws {
        if let secret, !secret.isEmpty {
            try keychain.setSecret(secret, for: profile.id)
        }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    public func delete(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        try? keychain.deleteSecret(for: profile.id)
        if selectedID == profile.id { selectedID = profiles.first?.id }
        persist()
    }

    public func secret(for profile: ServerProfile) -> String? {
        keychain.secret(for: profile.id)
    }

    // MARK: - Watch sync

    /// Replace the entire profile list with the set synced from another device
    /// (iPhone -> Apple Watch), writing each secret into this device's Keychain.
    /// Used by the watch app when it receives a `WatchSyncPayload`.
    public func replaceAll(with payload: WatchSyncPayload) {
        for profile in payload.profiles {
            if let secret = payload.secrets[profile.id.uuidString], !secret.isEmpty {
                try? keychain.setSecret(secret, for: profile.id)
            }
        }
        // Drop Keychain secrets for profiles that no longer exist.
        let keptIDs = Set(payload.profiles.map(\.id))
        for stale in profiles where !keptIDs.contains(stale.id) {
            try? keychain.deleteSecret(for: stale.id)
        }
        profiles = payload.profiles
        selectedID = payload.selectedID ?? payload.profiles.first?.id
        persist()
    }

    /// Build a payload of the real (non-demo) profiles plus their secrets, for
    /// sending to the paired Apple Watch. Only profiles whose secret is present are
    /// included: the watch can't connect without one, so syncing a secret-less
    /// profile would make it silently vanish there (and leave a stale Keychain
    /// entry). Excluding it also lets the watch prune any secret it no longer needs.
    public func watchSyncPayload() -> WatchSyncPayload {
        var included: [ServerProfile] = []
        var secrets: [String: String] = [:]
        for profile in profiles where !profile.isDemo {
            guard let secret = keychain.secret(for: profile.id) else { continue }
            included.append(profile)
            secrets[profile.id.uuidString] = secret
        }
        let selected = included.contains { $0.id == selectedID } ? selectedID : included.first?.id
        return WatchSyncPayload(profiles: included, secrets: secrets, selectedID: selected)
    }

    /// Build a ready-to-use connection for a profile, pulling its secret.
    /// Demo profiles need no stored secret (the demo API ignores it).
    public func connection(for profile: ServerProfile) -> ServerConnection? {
        if profile.isDemo { return profile.connection(secret: "demo") }
        guard let secret = keychain.secret(for: profile.id) else { return nil }
        return profile.connection(secret: secret)
    }

    /// Add an in-memory demo profile (not persisted) and select it. Used by the
    /// first-run demo and by screenshot automation (`REEVE_DEMO=1`).
    public func seedDemoProfile() {
        if let existing = profiles.first(where: { $0.isDemo }) {
            selectedID = existing.id
            return
        }
        let demo = ServerProfile(name: "Demo Datacenter", host: DemoMode.host, tokenID: "demo@pam!demo")
        profiles.insert(demo, at: 0)
        selectedID = demo.id
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data)
        else { return }
        profiles = decoded
        selectedID = decoded.first?.id
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
