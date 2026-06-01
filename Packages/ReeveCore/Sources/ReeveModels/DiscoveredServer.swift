import Foundation

/// A host found on the local network that looks like a Proxmox server
/// (something is listening on its API port). Used to prefill the Add Server form.
public struct DiscoveredServer: Identifiable, Sendable, Hashable {
    public let ipAddress: String
    public let port: Int
    public let hostname: String?

    public var id: String { "\(ipAddress):\(port)" }

    public init(ipAddress: String, port: Int, hostname: String? = nil) {
        self.ipAddress = ipAddress
        self.port = port
        self.hostname = hostname
    }

    /// A friendly suggested name: the reverse-DNS hostname (sans domain) if we
    /// have one, otherwise the IP.
    public var suggestedName: String {
        guard let hostname, !hostname.isEmpty else { return ipAddress }
        return hostname.split(separator: ".").first.map(String.init) ?? hostname
    }
}
