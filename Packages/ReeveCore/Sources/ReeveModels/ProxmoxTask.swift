import Foundation

/// Parsed Proxmox task id: `UPID:node:pid:pstart:starttime:type:id:user:`.
public struct UPID: Sendable, Hashable {
    public let raw: String
    public let node: String

    public init?(_ raw: String) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "UPID", !parts[1].isEmpty else { return nil }
        self.raw = raw
        self.node = String(parts[1])
    }
}

/// One row from `GET /nodes/{node}/tasks`.
public struct ProxmoxTaskInfo: Decodable, Sendable, Identifiable, Hashable {
    public let upid: String
    public let type: String
    public let workerID: String?
    public let user: String?
    public let status: String?
    public let starttime: Int64?
    public let endtime: Int64?
    public let exitstatus: String?

    public var id: String { upid }
    public var startDate: Date? { starttime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    // The tasks list reports the outcome in `status` ("OK"/error/"running"); the
    // per-task /status endpoint reports it in `exitstatus`. Prefer whichever is set.
    private var outcome: String { exitstatus ?? status ?? "" }
    public var isRunning: Bool { (status ?? "") == "running" }
    public var succeeded: Bool { !isRunning && outcome.hasPrefix("OK") }
    public var displayStatus: String {
        if isRunning { return "Running" }
        return outcome.hasPrefix("OK") ? "OK" : (outcome.isEmpty ? "-" : outcome)
    }

    private enum CodingKeys: String, CodingKey {
        case upid, type, user, status, starttime, endtime, exitstatus
        case workerID = "id"
    }
}

/// One line from `…/tasks/{upid}/log` (`n` = line number, `t` = text).
public struct TaskLogLine: Decodable, Sendable, Identifiable, Hashable {
    public let n: Int
    public let t: String
    public var id: Int { n }
}

/// Status of a worker task from `…/tasks/{upid}/status`.
public struct ProxmoxTaskStatus: Decodable, Sendable {
    public let upid: String?
    public let status: String          // "running" | "stopped"
    public let exitstatus: String?
    public let type: String?

    public var isRunning: Bool { status == "running" }
    /// Proxmox signals success with an exit status beginning "OK".
    public var succeeded: Bool { (exitstatus ?? "").hasPrefix("OK") }
    public var failureMessage: String? {
        guard !isRunning, !succeeded else { return nil }
        return exitstatus ?? "Task failed"
    }
}
