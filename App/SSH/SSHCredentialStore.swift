import Foundation
import ReevePersistence

/// Non-secret SSH connection details for a server (the password lives in the
/// Keychain alongside, keyed by the same profile id).
struct SSHCredential: Codable, Equatable {
    var host: String
    var port: Int
    var username: String
}

/// Persists per-server SSH settings: host/port/user in UserDefaults, password in
/// the Keychain (separate service from the Proxmox API token).
struct SSHCredentialStore {
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.reeveapp.ssh")

    func credential(for profileID: UUID) -> SSHCredential? {
        guard let data = defaults.data(forKey: key(profileID)),
              let cred = try? JSONDecoder().decode(SSHCredential.self, from: data)
        else { return nil }
        return cred
    }

    func password(for profileID: UUID) -> String? { keychain.secret(for: profileID) }

    func save(_ credential: SSHCredential, password: String, for profileID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        defaults.set(data, forKey: key(profileID))
        try keychain.setSecret(password, for: profileID)
    }

    func delete(for profileID: UUID) {
        defaults.removeObject(forKey: key(profileID))
        try? keychain.deleteSecret(for: profileID)
    }

    private func key(_ id: UUID) -> String { "ssh.cred.\(id.uuidString)" }
}
