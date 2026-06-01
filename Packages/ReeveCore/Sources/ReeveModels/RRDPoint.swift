import Foundation

/// Time-series window for RRD queries.
public enum RRDTimeframe: String, Sendable, CaseIterable, Identifiable {
    case hour, day, week, month, year
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// One sample from an `…/rrddata` endpoint. Every metric is optional because the
/// most recent buckets are often not yet consolidated and contain only `time`.
///
/// Units here differ from instantaneous status: `netin`/`netout`/`diskread`/
/// `diskwrite` are **per-second rates**, not cumulative totals.
public struct RRDPoint: Decodable, Sendable, Identifiable {
    public let time: Int
    public let cpu: Double?
    public let maxcpu: Double?
    public let mem: Double?
    public let maxmem: Double?
    public let disk: Double?
    public let maxdisk: Double?
    public let netin: Double?
    public let netout: Double?
    public let diskread: Double?
    public let diskwrite: Double?
    // Node-level RRD uses different keys than guest RRD for memory.
    public let memused: Double?
    public let memtotal: Double?

    public var id: Int { time }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }
    public var cpuPercent: Double? { cpu.map { $0 * 100 } }
    /// Used memory in bytes, whichever key this RRD source uses.
    public var memoryUsedBytes: Double? { mem ?? memused }
    public var memoryTotalBytes: Double? { maxmem ?? memtotal }
}
