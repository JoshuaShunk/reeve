import SwiftUI
import ReeveModels

/// Root screen: a glanceable list of synced servers with health + key metrics.
struct ServersListView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.servers.isEmpty {
                    EmptyServersView()
                } else {
                    List {
                        ForEach(model.servers) { server in
                            NavigationLink(value: server.id) {
                                ServerRow(server: server)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reeve")
            .navigationDestination(for: UUID.self) { id in
                if let server = model.server(withID: id) {
                    ServerDetailView(server: server)
                }
            }
        }
        .task { await refreshAll() }
    }

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for server in model.servers {
                group.addTask { await server.refresh() }
            }
        }
    }
}

/// One row per server: status dot, name, and a one-line metric summary.
struct ServerRow: View {
    let server: WatchServer

    var body: some View {
        HStack(spacing: 10) {
            HealthDot(health: server.health)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.profile.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        switch server.state {
        case .loading where server.resources.isEmpty:
            return "Loading…"
        case .failed:
            return "Unreachable"
        default:
            let cpu = server.cpuFraction.map { "\(Int(($0 * 100).rounded()))% CPU" } ?? "--"
            return "\(cpu) · \(server.guestsUp)/\(server.guestsTotal) up"
        }
    }
}

/// Shown when no servers have synced from the iPhone yet.
struct EmptyServersView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No Servers")
                    .font(.headline)
                Text("Open Reeve on your iPhone to sync your Proxmox servers to the watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Sync Now") { model.requestSync() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()
        }
    }
}
