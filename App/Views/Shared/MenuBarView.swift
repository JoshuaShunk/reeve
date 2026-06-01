#if os(macOS)
import ReeveFeatures
import ReeveModels
import SwiftUI

/// Compact always-on status panel for the macOS menu bar.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @State private var dashboard: DashboardModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let profile = app.profiles.selectedProfile, let dashboard {
                Text(profile.name).font(.headline)
                if let node = dashboard.nodes.first {
                    MetricBar(label: "CPU", fraction: node.cpu, detail: Format.percentValue(node.cpuPercent))
                    MetricBar(label: "RAM", fraction: node.memoryFraction, detail: Format.percent(node.memoryFraction))
                }
                Divider()
                Text("\(dashboard.runningGuestCount)/\(dashboard.guests.count) guests up")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(dashboard.guests.prefix(8)) { guest in
                    HStack {
                        Circle().fill(guest.status?.isUp == true ? .green : .gray)
                            .frame(width: 6, height: 6)
                        Text(guest.displayName).font(.callout)
                        Spacer()
                        Text(Format.percentValue(guest.cpuPercent))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No server configured").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
        .task {
            if let profile = app.profiles.selectedProfile {
                let model = app.makeDashboard(for: profile)
                dashboard = model
                await model?.autoRefresh(every: 10)
            }
        }
    }
}
#endif
