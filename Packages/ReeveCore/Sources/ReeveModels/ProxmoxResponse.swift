import Foundation

/// Every Proxmox VE API response wraps its payload in a top-level `data` key:
/// `{ "data": ... }`. Decode into this generic envelope.
public struct ProxmoxResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: T
}
