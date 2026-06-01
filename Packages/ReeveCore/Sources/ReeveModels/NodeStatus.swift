import Foundation

/// Detailed node status from `GET /nodes/{node}/status`.
public struct NodeStatus: Decodable, Sendable {
    public struct Memory: Decodable, Sendable {
        public let total: Int
        public let used: Int
        public let free: Int
    }

    public struct CPUInfo: Decodable, Sendable {
        public let model: String?
        public let cpus: Int?
        public let cores: Int?
        public let sockets: Int?
        public let mhz: String?
    }

    public let cpu: Double
    public let memory: Memory
    public let swap: Memory?
    public let rootfs: Memory?
    public let cpuinfo: CPUInfo?
    /// Load average over 1/5/15 minutes. Proxmox returns these as strings.
    public let loadavg: [String]
    public let uptime: Int
    public let pveversion: String?
    public let kversion: String?

    public var loadAverages: [Double] { loadavg.compactMap(Double.init) }
    public var memoryFraction: Double {
        memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0
    }
    public var cpuPercent: Double { cpu * 100 }
    public func fraction(_ memory: Memory?) -> Double? {
        guard let memory, memory.total > 0 else { return nil }
        return Double(memory.used) / Double(memory.total)
    }
}
