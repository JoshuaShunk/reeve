import Foundation

/// An entry from `GET /cluster/status` (a node, or the cluster itself).
public struct ClusterStatusEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let type: String          // "node" | "cluster"
    public let online: Int?
    public let nodeid: Int?
    public let ip: String?
    public let level: String?
    public let quorate: Int?         // only on type == "cluster"
    public let local: Int?

    public var isOnline: Bool { online == 1 }
    public var isLocal: Bool { local == 1 }
}

/// A High Availability resource from `GET /cluster/ha/resources`.
public struct HAResource: Decodable, Sendable, Identifiable, Hashable {
    public let sid: String
    public let type: String?
    public let state: String?
    public let group: String?
    public let comment: String?
    public var id: String { sid }
}

/// A user from `GET /access/users`.
public struct PVEUser: Decodable, Sendable, Identifiable, Hashable {
    public let userid: String
    public let enable: Int?
    public let email: String?
    public let comment: String?
    public let realmType: String?
    public var id: String { userid }
    public var isEnabled: Bool { enable != 0 }

    private enum CodingKeys: String, CodingKey {
        case userid, enable, email, comment
        case realmType = "realm-type"
    }
}

/// An API token from `GET /access/users/{userid}/token`.
public struct PVEToken: Decodable, Sendable, Identifiable, Hashable {
    public let tokenid: String
    public let comment: String?
    public let expire: Int?
    public let privsep: Int?
    public var id: String { tokenid }
}

/// A scheduled backup job from `GET /cluster/backup`.
public struct BackupJob: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let schedule: String?
    public let storage: String?
    public let mode: String?
    public let enabled: Int?
    public let all: Int?
    public let vmid: String?
    public let comment: String?
    public let nextRun: Int?

    public var isEnabled: Bool { enabled != 0 }
    public var selection: String { all == 1 ? "All guests" : (vmid ?? "-") }

    private enum CodingKeys: String, CodingKey {
        case id, schedule, storage, mode, enabled, all, vmid, comment
        case nextRun = "next-run"
    }
}

/// A firewall rule from `…/firewall/rules`.
public struct FirewallRule: Decodable, Sendable, Identifiable, Hashable {
    public let pos: Int
    public let type: String?        // "in" | "out" | "group"
    public let action: String?      // "ACCEPT" | "DROP" | "REJECT" | macro/group name
    public let enable: Int?
    public let proto: String?
    public let dport: String?
    public let sport: String?
    public let source: String?
    public let dest: String?
    public let iface: String?
    public let macro: String?
    public let comment: String?

    public var id: Int { pos }
    public var isEnabled: Bool { enable != 0 }
}
