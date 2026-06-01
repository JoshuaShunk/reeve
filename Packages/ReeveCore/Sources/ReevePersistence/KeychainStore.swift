import Foundation

#if canImport(Security)
import Security
#endif

/// Minimal Keychain wrapper for per-server token secrets. Each secret is a
/// `kSecClassGenericPassword` item keyed by (`service`, profile UUID as account).
///
/// Pass an `accessGroup` (and matching App Group / Keychain Sharing entitlement)
/// so the widget and macOS menu-bar extension can read the same secrets.
public struct KeychainStore: Sendable {
    public enum KeychainError: Error, Sendable {
        case unexpectedStatus(OSStatus)
        case encodingFailed
    }

    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.reeveapp.proxmox", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func setSecret(_ secret: String, for id: UUID) throws {
        guard let data = secret.data(using: .utf8) else { throw KeychainError.encodingFailed }
        let account = id.uuidString
        let query = baseQuery(account: account)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func secret(for id: UUID) -> String? {
        var query = baseQuery(account: id.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func deleteSecret(for id: UUID) throws {
        let status = SecItemDelete(baseQuery(account: id.uuidString) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
