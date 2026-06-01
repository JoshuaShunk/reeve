import Foundation

/// A systemd/pve service from `GET /nodes/{node}/services`.
public struct NodeService: Decodable, Sendable, Identifiable, Hashable {
    public let name: String
    public let desc: String?
    public let state: String?         // "running" | "dead" | …
    public let activeState: String?   // "active" | "inactive"
    public let unitState: String?     // "enabled" | "disabled"

    public var id: String { name }
    public var isRunning: Bool { state == "running" || activeState == "active" }

    private enum CodingKeys: String, CodingKey {
        case name, desc, state
        case activeState = "active-state"
        case unitState = "unit-state"
    }
}

/// A physical disk from `GET /nodes/{node}/disks/list`.
public struct PhysicalDisk: Decodable, Sendable, Identifiable, Hashable {
    public let devpath: String
    public let model: String?
    public let serial: String?
    public let size: Int?
    public let type: String?        // "nvme" | "ssd" | "hdd"
    public let health: String?      // "PASSED" | "FAILED" | "UNKNOWN"
    public let wearout: Int?        // % life remaining (SSD/NVMe)
    public let used: String?        // role, e.g. "LVM", "BIOS boot"
    public let vendor: String?

    public var id: String { devpath }
    public var healthy: Bool { (health ?? "").uppercased() == "PASSED" }
}

/// A ZFS pool from `GET /nodes/{node}/disks/zfs`.
public struct ZFSPool: Decodable, Sendable, Identifiable, Hashable {
    public let name: String
    public let health: String?
    public let size: Int?
    public let alloc: Int?
    public let free: Int?
    public let frag: Int?
    public let dedup: Double?

    public var id: String { name }
    public var healthy: Bool { (health ?? "").uppercased() == "ONLINE" }
    public var usedFraction: Double? {
        guard let size, size > 0, let alloc else { return nil }
        return Double(alloc) / Double(size)
    }
}

/// A storage from `GET /nodes/{node}/storage`.
public struct StorageSummary: Decodable, Sendable, Identifiable, Hashable {
    public let storage: String
    public let type: String?
    public let content: String?
    public let total: Int?
    public let used: Int?
    public let avail: Int?
    public let active: Int?

    public var id: String { storage }
    public var supportsBackups: Bool { (content ?? "").contains("backup") }
    public var usedFraction: Double? {
        guard let total, total > 0, let used else { return nil }
        return Double(used) / Double(total)
    }
}

/// An available package update from `GET /nodes/{node}/apt/update`.
public struct AptUpdate: Decodable, Sendable, Identifiable, Hashable {
    public let package: String
    public let title: String?
    public let version: String?
    public let oldVersion: String?
    public let priority: String?

    public var id: String { package }

    private enum CodingKeys: String, CodingKey {
        case package = "Package"
        case title = "Title"
        case version = "Version"
        case oldVersion = "OldVersion"
        case priority = "Priority"
    }
}
