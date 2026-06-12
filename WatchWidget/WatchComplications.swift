import AppIntents
import ReeveModels
import ReevePersistence
import SwiftUI
import WidgetKit

// MARK: - Configuration intent (server picker)

/// One pickable server in the complication's configuration sheet. Options come
/// from the App Group directory the watch app writes after each sync/refresh.
struct WatchServerEntity: AppEntity {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ target: WidgetTarget) {
        id = target.id
        name = target.name
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Server" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "server.rack"))
    }
    static let defaultQuery = WatchServerQuery()
}

struct WatchServerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WatchServerEntity] {
        servers().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WatchServerEntity] {
        servers()
    }

    func defaultResult() async -> WatchServerEntity? {
        servers().first
    }

    private func servers() -> [WatchServerEntity] {
        WidgetDataStore().loadDirectory()
            .filter { $0.kind == .server }
            .map(WatchServerEntity.init)
    }
}

struct SelectWatchServerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Server" }
    static var description: IntentDescription {
        IntentDescription("Choose which Proxmox server this complication shows.")
    }

    @Parameter(title: "Server")
    var server: WatchServerEntity?
}

// MARK: - Timeline

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetItemSnapshot?
    /// Configured server name with no cached data yet (open the app to load).
    let missingName: String?
}

struct WatchComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: Date(), snapshot: .sample, missingName: nil)
    }

    func snapshot(for configuration: SelectWatchServerIntent, in context: Context) async -> WatchComplicationEntry {
        entry(for: configuration)
    }

    /// Pre-configured complications offered in the watch face gallery: one per
    /// synced server, so the user can add a specific server's status directly.
    func recommendations() -> [AppIntentRecommendation<SelectWatchServerIntent>] {
        let servers = WidgetDataStore().loadDirectory().filter { $0.kind == .server }
        guard !servers.isEmpty else {
            return [AppIntentRecommendation(intent: SelectWatchServerIntent(), description: Text("Server Status"))]
        }
        return servers.map { target in
            let intent = SelectWatchServerIntent()
            intent.server = WatchServerEntity(target)
            return AppIntentRecommendation(intent: intent, description: Text(target.name))
        }
    }

    func timeline(for configuration: SelectWatchServerIntent, in context: Context) async -> Timeline<WatchComplicationEntry> {
        // The app reloads timelines on every refresh / background fetch; this is a
        // fallback cadence so the date keeps moving even if the app never runs.
        Timeline(entries: [entry(for: configuration)],
                 policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: SelectWatchServerIntent) -> WatchComplicationEntry {
        let store = WidgetDataStore()
        if let id = configuration.server?.id {
            if let snap = store.load(id: id) {
                return WatchComplicationEntry(date: Date(), snapshot: snap, missingName: nil)
            }
            return WatchComplicationEntry(date: Date(), snapshot: nil, missingName: configuration.server?.name)
        }
        // Not configured yet: fall back to the first server we have data for.
        if let first = store.loadAll().first {
            return WatchComplicationEntry(date: Date(), snapshot: first, missingName: nil)
        }
        return WatchComplicationEntry(date: Date(), snapshot: nil, missingName: nil)
    }
}

extension WidgetItemSnapshot {
    static let sample = WidgetItemSnapshot(
        target: WidgetTarget(id: "sample", name: "Reeve", kind: .server, symbolName: "server.rack"),
        health: .ok, caption: "14/15 up",
        metrics: [
            WidgetMetric(label: "CPU", value: "4%", fraction: 0.04),
            WidgetMetric(label: "RAM", value: "68%", fraction: 0.68),
        ]
    )
}

// MARK: - Views

private func healthColor(_ health: Health) -> Color {
    switch health {
    case .ok: .green
    case .warn: .yellow
    case .down: .red
    case .unknown: .gray
    }
}

private func gaugeColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.75: .green
    case ..<0.9: .yellow
    default: .red
    }
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchComplicationEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            unconfigured
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetItemSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            circular(snapshot)
        case .accessoryCorner:
            corner(snapshot)
        case .accessoryInline:
            Text(inlineText(snapshot))
        case .accessoryRectangular:
            rectangular(snapshot)
        default:
            circular(snapshot)
        }
    }

    private var cpuFraction: Double {
        entry.snapshot?.metrics.first(where: { $0.label == "CPU" })?.fraction ?? 0
    }

    // accessoryCircular: a CPU gauge tinted by load, server name on the bezel.
    private func circular(_ snapshot: WidgetItemSnapshot) -> some View {
        Gauge(value: cpuFraction) {
            Text("CPU")
        } currentValueLabel: {
            Text("\(Int((cpuFraction * 100).rounded()))")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeColor(cpuFraction))
        .widgetLabel(snapshot.target.name)
    }

    // accessoryCorner: gauge in the watch-face corner with a curved label.
    private func corner(_ snapshot: WidgetItemSnapshot) -> some View {
        Image(systemName: "server.rack")
            .font(.title2)
            .foregroundStyle(healthColor(snapshot.health))
            .widgetLabel {
                Gauge(value: cpuFraction) { Text("CPU") }
                    .tint(gaugeColor(cpuFraction))
            }
    }

    private func inlineText(_ snapshot: WidgetItemSnapshot) -> String {
        let cpu = "\(Int((cpuFraction * 100).rounded()))%"
        return "\(snapshot.target.name) \(cpu) · \(snapshot.caption ?? "")"
    }

    // accessoryRectangular: the Smart Stack size, name + metrics + guests.
    private func rectangular(_ snapshot: WidgetItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(healthColor(snapshot.health)).frame(width: 7, height: 7)
                Text(snapshot.target.name).font(.headline).lineLimit(1)
            }
            Text(snapshot.metrics.map { "\($0.label) \($0.value)" }.joined(separator: "  "))
                .font(.caption2)
            if let caption = snapshot.caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .widgetAccentable()
    }

    private var unconfigured: some View {
        switch family {
        case .accessoryInline:
            return AnyView(Text(entry.missingName.map { "Open Reeve: \($0)" } ?? "Open Reeve"))
        case .accessoryCircular, .accessoryCorner:
            return AnyView(
                Image(systemName: "server.rack").foregroundStyle(.secondary)
            )
        default:
            return AnyView(
                VStack(spacing: 2) {
                    Image(systemName: "server.rack").foregroundStyle(.secondary)
                    Text(entry.missingName.map { "Open Reeve to load \($0)" } ?? "Open Reeve on iPhone to sync")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            )
        }
    }
}

// MARK: - Widget + bundle

struct ReeveWatchComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ReeveWatchComplication",
            intent: SelectWatchServerIntent.self,
            provider: WatchComplicationProvider()
        ) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Server Status")
        .description("CPU, memory, and guests for a Proxmox server.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

@main
struct ReeveWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReeveWatchComplication()
    }
}
