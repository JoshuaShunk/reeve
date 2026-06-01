import AppIntents
import ReeveModels
import ReevePersistence
import SwiftUI
import WidgetKit

// MARK: - Configuration intent (the picker)

/// One pickable item in the widget's configuration sheet, a server or service
/// the user has added. The options come from the App Group directory the app writes.
struct WidgetTargetEntity: AppEntity {
    let id: String
    let name: String
    let kindRaw: String
    let symbolName: String

    init(_ target: WidgetTarget) {
        id = target.id; name = target.name
        kindRaw = target.kind.rawValue; symbolName = target.symbolName
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Reeve Item" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: kindRaw == WidgetTargetKind.server.rawValue ? "Server" : "Service",
            image: .init(systemName: symbolName)
        )
    }
    static let defaultQuery = WidgetTargetQuery()
}

struct WidgetTargetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetTargetEntity] {
        WidgetDataStore().loadDirectory()
            .filter { identifiers.contains($0.id) }
            .map(WidgetTargetEntity.init)
    }

    func suggestedEntities() async throws -> [WidgetTargetEntity] {
        WidgetDataStore().loadDirectory().map(WidgetTargetEntity.init)
    }

    func defaultResult() async -> WidgetTargetEntity? {
        try? await suggestedEntities().first
    }
}

struct SelectItemIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Item" }
    static var description: IntentDescription {
        IntentDescription("Choose which server or service to display.")
    }

    @Parameter(title: "Item")
    var target: WidgetTargetEntity?
}

// MARK: - Timeline

struct ItemEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetItemSnapshot?
    let missingName: String?   // configured but no cached data yet
}

struct ItemProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ItemEntry {
        ItemEntry(date: Date(), snapshot: ItemProvider.sample, missingName: nil)
    }

    func snapshot(for configuration: SelectItemIntent, in context: Context) async -> ItemEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectItemIntent, in context: Context) async -> Timeline<ItemEntry> {
        // The app reloads timelines on every refresh; this is a fallback cadence.
        Timeline(entries: [entry(for: configuration)],
                 policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: SelectItemIntent) -> ItemEntry {
        let store = WidgetDataStore()
        if let id = configuration.target?.id {
            if let snap = store.load(id: id) {
                return ItemEntry(date: Date(), snapshot: snap, missingName: nil)
            }
            return ItemEntry(date: Date(), snapshot: nil, missingName: configuration.target?.name)
        }
        // Not configured yet: show the first item we have data for.
        if let first = store.loadAll().first {
            return ItemEntry(date: Date(), snapshot: first, missingName: nil)
        }
        return ItemEntry(date: Date(), snapshot: nil, missingName: nil)
    }

    static let sample = WidgetItemSnapshot(
        target: WidgetTarget(id: "sample", name: "Reeve", kind: .server, symbolName: "server.rack"),
        health: .ok, caption: "14/15 guests up",
        metrics: [
            WidgetMetric(label: "CPU", value: "4%", fraction: 0.04),
            WidgetMetric(label: "RAM", value: "68%", fraction: 0.68),
        ]
    )
}

// MARK: - View

struct ItemWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ItemEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                Text(entry.missingName.map { "Open the app to load \($0)" }
                     ?? "Add a server or service in the app")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    @ViewBuilder private func content(_ snapshot: WidgetItemSnapshot) -> some View {
        #if os(iOS)
        switch family {
        case .accessoryInline:
            Text(inlineText(snapshot))
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(snapshot.target.name).font(.headline).lineLimit(1)
                if !snapshot.metrics.isEmpty {
                    Text(snapshot.metrics.map { "\($0.label) \($0.value)" }.joined(separator: "  "))
                        .font(.caption)
                }
                if let caption = snapshot.caption { Text(caption).font(.caption2).lineLimit(1) }
            }
        default:
            fullView(snapshot)
        }
        #else
        fullView(snapshot)
        #endif
    }

    private func inlineText(_ s: WidgetItemSnapshot) -> String {
        if let m = s.metrics.first { return "\(s.target.name): \(m.label) \(m.value)" }
        return "\(s.target.name): \(s.caption ?? "-")"
    }

    private func fullView(_ snapshot: WidgetItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.target.symbolName).foregroundStyle(.tint)
                Text(snapshot.target.name).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(color(snapshot.health)).frame(width: 8, height: 8)
            }
            ForEach(snapshot.metrics) { metric in
                metricRow(metric)
            }
            Spacer(minLength: 0)
            if let caption = snapshot.caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func metricRow(_ metric: WidgetMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(metric.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(metric.value).font(.caption2.monospacedDigit())
            }
            if let fraction = metric.fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .tint(fraction < 0.6 ? .green : (fraction < 0.85 ? .yellow : .red))
            }
        }
    }

    private func color(_ health: Health) -> Color {
        switch health {
        case .ok: .green
        case .warn: .yellow
        case .down: .red
        case .unknown: .gray
        }
    }
}

// MARK: - Widget

struct ReeveItemWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ReeveItemWidget", intent: SelectItemIntent.self, provider: ItemProvider()
        ) { entry in
            ItemWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Reeve Item")
        .description("Pick any server or service you've added.")
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    private static let families: [WidgetFamily] =
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
    #else
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    #endif
}
