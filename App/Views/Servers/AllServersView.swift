import ReeveModels
import ReevePersistence
import SwiftUI

/// Every configured server's nodes and guests in one searchable list.
struct AllServersView: View {
    @Environment(AppModel.self) private var app

    struct Row: Identifiable, Hashable {
        let profile: ServerProfile
        let resource: ClusterResource
        var id: String { "\(profile.id)-\(resource.id)" }
    }

    @State private var rows: [Row] = []
    @State private var query = ""
    @State private var loaded = false

    private var filtered: [Row] {
        guard !query.isEmpty else { return rows }
        let q = query.lowercased()
        return rows.filter {
            $0.resource.displayName.lowercased().contains(q)
                || $0.profile.name.lowercased().contains(q)
                || ($0.resource.vmid.map { String($0) }?.contains(q) ?? false)
        }
    }

    private var grouped: [(server: String, rows: [Row])] {
        Dictionary(grouping: filtered, by: { $0.profile.name })
            .map { (server: $0.key, rows: $0.value) }
            .sorted { $0.server < $1.server }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.server) { group in
                Section(group.server) {
                    ForEach(sorted(group.rows)) { row in
                        rowLink(row)
                    }
                }
            }
        }
        .navigationTitle("All Servers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $query, prompt: "Search guests, nodes, servers")
        .overlay {
            if loaded && rows.isEmpty {
                ContentUnavailableView("Nothing to show", systemImage: "magnifyingglass",
                                       description: Text("Add a server to see its guests here."))
            } else if !loaded {
                ProgressView()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func rowLink(_ row: Row) -> some View {
        let r = row.resource
        if r.type == .node {
            NavigationLink {
                NodeDetailView(nodeName: r.node ?? r.displayName, profile: row.profile)
            } label: { rowLabel(row) }
        } else {
            NavigationLink {
                GuestDetailView(guest: r, profile: row.profile)
            } label: { rowLabel(row) }
        }
    }

    private func rowLabel(_ row: Row) -> some View {
        let r = row.resource
        return HStack(spacing: 10) {
            Image(systemName: icon(r))
                .foregroundStyle(r.status?.isUp == true ? .green : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.displayName).font(.callout.weight(.medium))
                Text(subtitle(r)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let vmid = r.vmid { Text("#\(vmid)").font(.caption2.monospaced()).foregroundStyle(.tertiary) }
        }
    }

    private func icon(_ r: ClusterResource) -> String {
        switch r.type {
        case .node: "server.rack"
        case .qemu: "desktopcomputer"
        case .lxc: "shippingbox"
        default: "circle"
        }
    }

    private func subtitle(_ r: ClusterResource) -> String {
        switch r.type {
        case .node: "Node"
        case .qemu: "VM · \(r.node ?? "")"
        case .lxc: "Container · \(r.node ?? "")"
        default: r.type.rawValue
        }
    }

    private func sorted(_ rows: [Row]) -> [Row] {
        rows.sorted {
            if ($0.resource.type == .node) != ($1.resource.type == .node) {
                return $0.resource.type == .node
            }
            return ($0.resource.vmid ?? 0) < ($1.resource.vmid ?? 0)
        }
    }

    private func load() async {
        var collected: [Row] = []
        for profile in app.profiles.profiles {
            guard let conn = app.profiles.connection(for: profile),
                  let resources = try? await app.api.clusterResources(conn) else { continue }
            for resource in resources where resource.type == .node
                || ((resource.type == .qemu || resource.type == .lxc) && !resource.isTemplate) {
                collected.append(Row(profile: profile, resource: resource))
            }
        }
        rows = collected
        loaded = true
    }
}
