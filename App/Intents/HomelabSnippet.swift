import SwiftUI

/// The card Siri/Spotlight shows alongside the spoken "Homelab status" answer.
/// Static (no buttons) so it works back to iOS 17; an interactive iOS-26 snippet
/// with inline Start/Stop is a future enhancement.
struct HomelabSnippetView: View {
    struct Server: Identifiable {
        let name: String
        let up: Int
        let total: Int
        var id: String { name }
        var tint: Color { up == total ? .green : (up == 0 ? .red : .yellow) }
    }

    let running: Int
    let total: Int
    let servers: [Server]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack").foregroundStyle(.tint)
                Text("Homelab").font(.headline)
                Spacer()
                if total > 0 {
                    Text("\(running)/\(total) running")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if servers.isEmpty {
                Text("No servers synced yet. Open Reeve to add one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(servers) { server in
                    HStack(spacing: 8) {
                        Circle().fill(server.tint).frame(width: 8, height: 8)
                        Text(server.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("\(server.up)/\(server.total)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}
