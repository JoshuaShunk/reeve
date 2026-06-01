import Foundation
import ReeveModels

/// Shared App Group identifier. App-group strings are team-scoped, so this same
/// generic value works for any developer/team that builds the app.
public enum AppGroup {
    public static let identifier = "group.com.reeveapp.app"
}

/// Reads/writes the `WidgetSnapshot` in the shared App Group container so the app
/// (writer) and the widget extension (reader) exchange data.
public struct WidgetSnapshotStore: Sendable {
    private let appGroup: String
    private let key = "widget.snapshot"

    public init(appGroup: String = AppGroup.identifier) {
        self.appGroup = appGroup
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    public func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// Backs the *configurable* widget: a directory of selectable targets (for the
/// picker) plus a per-target cached snapshot (for rendering). Both live in the
/// shared App Group so the widget extension can read them with no network.
public struct WidgetDataStore: Sendable {
    private let appGroup: String
    private let directoryKey = "widget.targets"
    private let itemsKey = "widget.items"

    public init(appGroup: String = AppGroup.identifier) {
        self.appGroup = appGroup
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // MARK: Directory of selectable targets

    public func saveDirectory(_ targets: [WidgetTarget]) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults?.set(data, forKey: directoryKey)
    }

    public func loadDirectory() -> [WidgetTarget] {
        guard let data = defaults?.data(forKey: directoryKey),
              let targets = try? JSONDecoder().decode([WidgetTarget].self, from: data)
        else { return [] }
        return targets
    }

    // MARK: Per-target snapshots (stored together, keyed by target id)

    public func save(_ snapshot: WidgetItemSnapshot) {
        var all = loadAllMap()
        all[snapshot.target.id] = snapshot
        persist(all)
    }

    public func load(id: String) -> WidgetItemSnapshot? {
        loadAllMap()[id]
    }

    public func loadAll() -> [WidgetItemSnapshot] {
        Array(loadAllMap().values)
    }

    private func loadAllMap() -> [String: WidgetItemSnapshot] {
        guard let data = defaults?.data(forKey: itemsKey),
              let map = try? JSONDecoder().decode([String: WidgetItemSnapshot].self, from: data)
        else { return [:] }
        return map
    }

    private func persist(_ map: [String: WidgetItemSnapshot]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults?.set(data, forKey: itemsKey)
    }
}
