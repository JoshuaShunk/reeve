import ReeveFeatures
import ReeveModels
import ReeveNetworking
import SwiftUI

/// Native rendering of an Uptime Kuma status page, the public dashboard the
/// user built at `/status/<slug>`: an overall banner, then each group's monitors
/// with a live status dot, 24h uptime, and the familiar heartbeat bar.
struct UptimeKumaStatusView: View {
    let model: ServicesModel
    let instance: ServiceInstance

    @State private var page: UptimeKumaStatusPage?
    @State private var error: String?
    @State private var loading = false
    @State private var expanded: Set<Int> = []

    var body: some View {
        Group {
            if let page {
                VStack(alignment: .leading, spacing: 20) {
                    overallBanner(page)
                    ForEach(page.groups) { group in
                        if !group.monitors.isEmpty {
                            groupCard(group)
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Status page unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            page = try await model.uptimeKumaStatusPage(for: instance)
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Banner

    @ViewBuilder private func overallBanner(_ page: UptimeKumaStatusPage) -> some View {
        let status = page.overall
        HStack(spacing: 10) {
            Image(systemName: status == 1 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color(for: status))
            Text(bannerText(status))
                .font(.headline)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(for: status).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func bannerText(_ status: Int?) -> String {
        switch status {
        case 1: "All Systems Operational"
        case 0: "Partial Outage"
        case 2: "Degraded. Pending Checks"
        case 3: "Under Maintenance"
        default: "Status Unknown"
        }
    }

    // MARK: Group

    private func groupCard(_ group: UptimeKumaStatusPage.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(group.monitors.enumerated()), id: \.element.id) { index, monitor in
                    if index > 0 { Divider() }
                    monitorRow(monitor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func monitorRow(_ monitor: UptimeKumaStatusPage.Monitor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(color(for: monitor.latestStatus)).frame(width: 9, height: 9)
                Text(monitor.name).font(.callout.weight(.medium)).lineLimit(1)
                if monitor.isGroup {
                    Text("GROUP")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
                Spacer()
                if let uptime = monitor.uptime24h {
                    Text(uptime, format: .percent.precision(.fractionLength(uptime >= 0.9995 ? 0 : 2)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded.contains(monitor.id) ? 90 : 0))
            }
            HeartbeatBar(beats: monitor.beats, color: color)
            if expanded.contains(monitor.id) {
                expandedDetail(monitor)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded.contains(monitor.id) { expanded.remove(monitor.id) }
            else { expanded.insert(monitor.id) }
        }
    }

    @ViewBuilder private func expandedDetail(_ monitor: UptimeKumaStatusPage.Monitor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let beat = monitor.latestBeat {
                detailLine("Last check", beat.time?.replacingOccurrences(of: "T", with: " ") ?? "-")
                if let ping = beat.ping { detailLine("Response", "\(ping) ms") }
                if let msg = beat.msg, !msg.isEmpty { detailLine("Message", msg) }
            }
            if monitor.isGroup {
                Text("This is a group monitor. Uptime Kuma's status page publishes only the group's combined status, add its child monitors to the status page to see them individually.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 2)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption2.monospacedDigit()).multilineTextAlignment(.trailing)
        }
    }

    private func color(for status: Int?) -> Color {
        switch status {
        case 1: .green
        case 0: .red
        case 2: .orange
        case 3: .blue
        default: .gray
        }
    }
}

/// The row of small bars showing recent heartbeats (oldest left → newest right).
private struct HeartbeatBar: View {
    let beats: [UptimeKumaStatusPage.Beat]
    let color: (Int?) -> Color

    private let maxBars = 36

    var body: some View {
        let shown = beats.suffix(maxBars)
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let count = max(shown.count, 1)
            let width = max((geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 2)
            HStack(spacing: spacing) {
                if shown.isEmpty {
                    Text("No data").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { beat in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(beat.status))
                            .frame(width: width)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 22)
    }
}
