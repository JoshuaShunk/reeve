import Foundation

/// A node network interface from `GET /nodes/{node}/network`.
public struct NetworkInterface: Decodable, Sendable, Identifiable, Hashable {
    public let iface: String
    public let type: String?
    public let active: Int?
    public let autostart: Int?
    public let method: String?
    public let address: String?
    public let cidr: String?
    public let gateway: String?
    public let bridgePorts: String?

    public var id: String { iface }
    public var isActive: Bool { active == 1 }

    private enum CodingKeys: String, CodingKey {
        case iface, type, active, autostart, method, address, cidr, gateway
        case bridgePorts = "bridge_ports"
    }
}

/// A volume from `GET /nodes/{node}/storage/{storage}/content`.
public struct StorageVolume: Decodable, Sendable, Identifiable, Hashable {
    public let volid: String
    public let content: String?
    public let format: String?
    public let size: Int?
    public let ctime: Int?
    public let vmid: Int?

    public var id: String { volid }
    public var date: Date? { ctime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    public var filename: String {
        if let slash = volid.lastIndex(of: "/") { return String(volid[volid.index(after: slash)...]) }
        return volid
    }
}

/// An SDN zone from `GET /cluster/sdn/zones`.
public struct SDNZone: Decodable, Sendable, Identifiable, Hashable {
    public let zone: String
    public let type: String?
    public let mtu: Int?
    public var id: String { zone }
}

/// An SDN VNet from `GET /cluster/sdn/vnets`.
public struct SDNVNet: Decodable, Sendable, Identifiable, Hashable {
    public let vnet: String
    public let zone: String?
    public let alias: String?
    public let tag: Int?
    public var id: String { vnet }
}

/// A replication job from `GET /cluster/replication`.
public struct ReplicationJob: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let type: String?
    public let target: String?
    public let schedule: String?
    public let comment: String?
    public let disable: Int?
    public var isEnabled: Bool { disable != 1 }
}
