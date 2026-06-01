import Foundation
import ReeveModels
import Observation

/// Observable store of configured `ServiceInstance`s. Instances persist as JSON in
/// `UserDefaults`; secrets live in the Keychain (namespaced apart from Proxmox
/// tokens). Also caches the last `ServiceStatus` per instance for fast launch and
/// (later) widget sharing.
@MainActor
@Observable
public final class ServiceInstanceStore {
    public private(set) var instances: [ServiceInstance] = []

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let listKey = "homelab.serviceInstances"

    public init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(service: "com.reeveapp.services")
    ) {
        self.defaults = defaults
        self.keychain = keychain
        load()
    }

    // MARK: - CRUD

    public func save(_ instance: ServiceInstance, secret: String?) throws {
        if let secret, !secret.isEmpty {
            try keychain.setSecret(secret, for: instance.id)
        }
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
        persist()
    }

    public func delete(_ instance: ServiceInstance) {
        instances.removeAll { $0.id == instance.id }
        try? keychain.deleteSecret(for: instance.id)
        defaults.removeObject(forKey: statusKey(instance.id))
        persist()
    }

    public func secret(for instance: ServiceInstance) -> String? {
        keychain.secret(for: instance.id)
    }

    // MARK: - Status cache (Codable, ready for App Group / widgets)

    public func cache(_ status: ServiceStatus, for id: UUID) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: statusKey(id))
    }

    public func cachedStatus(for id: UUID) -> ServiceStatus? {
        guard let data = defaults.data(forKey: statusKey(id)) else { return nil }
        return try? JSONDecoder().decode(ServiceStatus.self, from: data)
    }

    private func statusKey(_ id: UUID) -> String { "homelab.serviceStatus.\(id.uuidString)" }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: listKey),
              let decoded = try? JSONDecoder().decode([ServiceInstance].self, from: data)
        else { return }
        instances = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: listKey)
    }
}
