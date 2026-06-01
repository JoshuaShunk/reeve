import Foundation

/// A tiny, Codable summary the app writes to the shared App Group container for
/// the widget to read. Keeps the widget network-free (it just renders cached data).
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public var serverName: String
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var guestsUp: Int
    public var guestsTotal: Int
    public var date: Date

    public init(
        serverName: String, cpuPercent: Double, memoryPercent: Double,
        guestsUp: Int, guestsTotal: Int, date: Date = Date()
    ) {
        self.serverName = serverName
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.guestsUp = guestsUp
        self.guestsTotal = guestsTotal
        self.date = date
    }
}
