import SwiftUI
import ReeveModels

/// Per-server screen: node gauges up top, then the guest list.
struct ServerDetailView: View {
    let server: WatchServer

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    MetricGauge(title: "CPU", fraction: server.cpuFraction)
                    MetricGauge(title: "MEM", fraction: server.memoryFraction)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            if case .failed(let message) = server.state {
                Section {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Nodes") {
                ForEach(server.nodes) { node in
                    HStack {
                        HealthDot(health: node.status?.isUp == true ? .ok : .down)
                        Text(node.displayName).font(.caption)
                        Spacer()
                        Text(formatUptime(node.uptime))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Guests (\(server.guestsUp)/\(server.guestsTotal))") {
                if server.guests.isEmpty {
                    Text("No guests")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(server.guests) { guest in
                        NavigationLink {
                            GuestDetailView(server: server, guestID: guest.id)
                        } label: {
                            GuestRow(guest: guest)
                        }
                    }
                }
            }
        }
        .navigationTitle(server.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await server.refresh() }
        .refreshable { await server.refresh() }
    }
}

struct GuestRow: View {
    let guest: ClusterResource

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: guest.type == .lxc ? "shippingbox" : "desktopcomputer")
                .font(.caption)
                .foregroundStyle(isUp ? Color.green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(guest.displayName)
                    .font(.caption)
                    .lineLimit(1)
                Text(isUp ? cpuText : "Stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isUp: Bool { guest.status?.isUp == true }

    private var cpuText: String {
        guard let cpu = guest.cpu else { return "Running" }
        return "\(Int((cpu * 100).rounded()))% CPU"
    }
}
