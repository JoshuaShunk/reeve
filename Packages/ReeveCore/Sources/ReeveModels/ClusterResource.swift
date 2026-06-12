import Foundation

/// The kind of object a `/cluster/resources` row (or guest) represents.
public enum ResourceType: String, Sendable, Codable {
    case node, qemu, lxc, storage, pool, sdn
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ResourceType(rawValue: raw) ?? .unknown
    }
}

/// Run state shared by nodes and guests.
public enum RunStatus: String, Sendable, Codable {
    case running, stopped, online, offline, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RunStatus(rawValue: raw) ?? .unknown
    }

    public var isUp: Bool { self == .running || self == .online }
}

/// One row from `GET /cluster/resources`, the single call that backs the
/// dashboard. Covers nodes, QEMU VMs, LXC containers, and storage. Most numeric
/// fields are optional because they're only present for some resource types.
///
/// Units (important): `cpu` is a fraction 0.0–1.0 (multiply by 100 for %).
/// `mem`/`maxmem`/`disk`/`maxdisk`/`netin`/`netout` are **bytes**
/// (netin/netout are cumulative here). `uptime` is **seconds**.
public struct ClusterResource: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let type: ResourceType
    public let status: RunStatus?
    public let node: String?
    public let name: String?
    public let vmid: Int?

    public let cpu: Double?
    public let maxcpu: Double?
    // Byte counts: use Int64 so they don't overflow on 32-bit watchOS (arm64_32),
    // where `Int` is 32-bit and Proxmox's multi-GB values fail to decode.
    public let mem: Int64?
    public let maxmem: Int64?
    public let disk: Int64?
    public let maxdisk: Int64?
    public let netin: Int64?
    public let netout: Int64?
    public let diskread: Int64?
    public let diskwrite: Int64?
    public let uptime: Int?

    public let tags: String?
    public let template: Int?

    // storage-only
    public let storage: String?
    public let plugintype: String?
    public let content: String?
    public let shared: Int?

    /// CPU utilisation as a percentage (0–100), or nil if unknown.
    public var cpuPercent: Double? { cpu.map { $0 * 100 } }

    /// Memory utilisation 0.0–1.0, or nil if either value is missing/zero.
    public var memoryFraction: Double? {
        guard let mem, let maxmem, maxmem > 0 else { return nil }
        return Double(mem) / Double(maxmem)
    }

    public var isTemplate: Bool { (template ?? 0) == 1 }

    /// A user-facing display name, falling back to the id.
    public var displayName: String { name ?? id }

    public var tagList: [String] {
        (tags ?? "").split(whereSeparator: { $0 == ";" || $0 == "," }).map(String.init)
    }
}
