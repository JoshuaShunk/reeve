import Foundation
import ReeveModels
import ReevePersistence
import WidgetKit

/// Bridges the watch app's live data into the shared App Group so the watch
/// complications can render it with no network. App Groups are shared between the
/// watch app and its own widget extension (same device), which is exactly the
/// channel `WidgetDataStore` provides. Every write nudges WidgetKit to reload.
enum WatchWidgetSync {
    private static let store = WidgetDataStore()

    /// Rebuild the complication's pickable-server directory. Cheap, network-free.
    static func refreshDirectory(_ profiles: [ServerProfile]) {
        let targets = profiles
            .map { WidgetTarget(id: $0.id.uuidString, name: $0.name, kind: .server, symbolName: "server.rack") }
        store.saveDirectory(targets)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Cache one server's summary for its complication.
    static func write(
        profile: ServerProfile,
        cpuFraction: Double?,
        memoryFraction: Double?,
        guestsUp: Int,
        guestsTotal: Int,
        health: Health
    ) {
        let snapshot = WidgetItemSnapshot(
            target: WidgetTarget(id: profile.id.uuidString, name: profile.name,
                                 kind: .server, symbolName: "server.rack"),
            health: health,
            caption: "\(guestsUp)/\(guestsTotal) guests up",
            metrics: [
                WidgetMetric(label: "CPU", value: percent(cpuFraction), fraction: cpuFraction),
                WidgetMetric(label: "RAM", value: percent(memoryFraction), fraction: memoryFraction),
            ]
        )
        store.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "--" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}
