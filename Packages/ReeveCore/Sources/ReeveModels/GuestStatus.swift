import Foundation

/// Whether a guest is a full VM (`qemu`) or a container (`lxc`). Used to build
/// the correct API path segment.
public enum GuestKind: String, Sendable, Codable, CaseIterable {
    case qemu
    case lxc

    public var pathSegment: String { rawValue }
    public var label: String { self == .qemu ? "VM" : "Container" }
}

/// Live per-guest status from `…/{kind}/{vmid}/status/current`.
public struct GuestStatus: Decodable, Sendable {
    public let status: RunStatus
    public let name: String?
    public let vmid: Int?
    public let cpu: Double?
    public let cpus: Int?
    public let mem: Int?
    public let maxmem: Int?
    public let disk: Int?
    public let maxdisk: Int?
    public let netin: Int?
    public let netout: Int?
    public let diskread: Int?
    public let diskwrite: Int?
    public let uptime: Int?
    public let pid: Int?

    public var cpuPercent: Double? { cpu.map { $0 * 100 } }
    public var memoryFraction: Double? {
        guard let mem, let maxmem, maxmem > 0 else { return nil }
        return Double(mem) / Double(maxmem)
    }
}
