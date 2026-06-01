import ReeveModels
import ReevePersistence
import SwiftUI
import WidgetKit

struct ReeveEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ReeveProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReeveEntry {
        ReeveEntry(date: Date(), snapshot: WidgetSnapshot(
            serverName: "Reeve", cpuPercent: 4, memoryPercent: 68, guestsUp: 14, guestsTotal: 15
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ReeveEntry) -> Void) {
        completion(ReeveEntry(date: Date(), snapshot: WidgetSnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReeveEntry>) -> Void) {
        let entry = ReeveEntry(date: Date(), snapshot: WidgetSnapshotStore().load())
        // The app reloads timelines on refresh; this is just a fallback cadence.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct ReeveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReeveEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "server.rack").foregroundStyle(.secondary)
                Text("Open Reeve").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private func content(_ snapshot: WidgetSnapshot) -> some View {
        #if os(iOS)
        switch family {
        case .accessoryInline:
            Text("CPU \(Int(snapshot.cpuPercent))% · \(snapshot.guestsUp)/\(snapshot.guestsTotal)")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(snapshot.serverName).font(.headline)
                Text("CPU \(Int(snapshot.cpuPercent))%  RAM \(Int(snapshot.memoryPercent))%")
                Text("\(snapshot.guestsUp)/\(snapshot.guestsTotal) guests up")
            }
        default:
            fullView(snapshot)
        }
        #else
        fullView(snapshot)
        #endif
    }

    private func fullView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack").foregroundStyle(.tint)
                Text(snapshot.serverName).font(.headline).lineLimit(1)
            }
            metric("CPU", percent: snapshot.cpuPercent)
            metric("RAM", percent: snapshot.memoryPercent)
            Spacer(minLength: 0)
            Text("\(snapshot.guestsUp)/\(snapshot.guestsTotal) guests up")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metric(_ label: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percent))%").font(.caption2.monospacedDigit())
            }
            ProgressView(value: min(max(percent / 100, 0), 1))
                .tint(percent < 60 ? .green : (percent < 85 ? .yellow : .red))
        }
    }
}

struct ReeveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReeveWidget", provider: ReeveProvider()) { entry in
            ReeveWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Reeve")
        .description("Node CPU/RAM and how many guests are up.")
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    private static let families: [WidgetFamily] =
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
    #else
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    #endif
}

@main
struct ReeveWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReeveWidget()
        ReeveItemWidget()
        #if os(iOS)
        TaskLiveActivity()
        AgentLiveActivity()
        if #available(iOS 18.0, *) {
            OpenReeveControl()
        }
        #endif
    }
}
