import Foundation
import ReeveModels
import ReeveNetworking
import ReevePersistence
import WidgetKit

/// Bridges live app data into the App Group so the configurable widget can list
/// the user's servers & services (the picker) and render the chosen one (cached,
/// network-free). All writes also nudge WidgetKit to reload timelines.
enum WidgetSync {
    private static let store = WidgetDataStore()

    /// Rebuild the picker directory from configured servers + services. Cheap and
    /// network-free, safe to call on launch and whenever the lists change.
    @MainActor static func refreshDirectory(
        profiles: ProfileStore, services: ServiceInstanceStore
    ) {
        var targets: [WidgetTarget] = profiles.profiles.map {
            WidgetTarget(id: $0.id.uuidString, name: $0.name, kind: .server,
                         symbolName: "server.rack")
        }
        targets += services.instances.map {
            WidgetTarget(id: $0.id.uuidString, name: $0.name, kind: .service,
                         symbolName: ServiceCatalogLookup.symbol(for: $0.typeID))
        }
        store.saveDirectory(targets)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func writeServer(
        profile: ServerProfile, cpuPercent: Double, memoryPercent: Double,
        guestsUp: Int, guestsTotal: Int
    ) {
        let health: Health = (cpuPercent >= 90 || memoryPercent >= 90) ? .warn : .ok
        let snapshot = WidgetItemSnapshot(
            target: WidgetTarget(id: profile.id.uuidString, name: profile.name,
                                 kind: .server, symbolName: "server.rack"),
            health: health,
            caption: "\(guestsUp)/\(guestsTotal) guests up",
            metrics: [
                WidgetMetric(label: "CPU", value: "\(Int(cpuPercent.rounded()))%",
                             fraction: cpuPercent / 100),
                WidgetMetric(label: "RAM", value: "\(Int(memoryPercent.rounded()))%",
                             fraction: memoryPercent / 100),
            ]
        )
        store.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func writeService(instance: ServiceInstance, state: ServiceState) {
        let target = WidgetTarget(
            id: instance.id.uuidString, name: instance.name, kind: .service,
            symbolName: ServiceCatalogLookup.symbol(for: instance.typeID)
        )
        let snapshot: WidgetItemSnapshot
        switch state {
        case .loading:
            return // nothing useful yet
        case .failed(let message, let date):
            snapshot = WidgetItemSnapshot(
                target: target, date: date, health: .down, caption: message
            )
        case .loaded(let status):
            let stats = (status.highlightedStats.isEmpty ? status.stats : status.highlightedStats)
            snapshot = WidgetItemSnapshot(
                target: target, date: status.fetchedAt, health: status.health,
                caption: status.summary ?? healthCaption(status.health),
                metrics: stats.prefix(2).map {
                    WidgetMetric(label: $0.label, value: $0.displayValue)
                }
            )
        }
        store.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func healthCaption(_ health: Health) -> String {
        switch health {
        case .ok: "Online"
        case .warn: "Degraded"
        case .down: "Offline"
        case .unknown: "Unknown"
        }
    }
}
