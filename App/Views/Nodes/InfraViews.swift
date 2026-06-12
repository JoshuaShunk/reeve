import ReeveModels
import ReevePersistence
import SwiftUI

private func sizeString(_ value: Int64?) -> String {
    guard let value else { return "-" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
}

// MARK: - Node network

struct NodeNetworkView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var interfaces: [NetworkInterface] = []
    @State private var loaded = false

    var body: some View {
        List(interfaces) { iface in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Circle().fill(iface.isActive ? .green : .secondary).frame(width: 8, height: 8)
                    Text(iface.iface).font(.callout.weight(.medium))
                    if let type = iface.type {
                        Text(type).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let cidr = iface.cidr ?? iface.address {
                        Text(cidr).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if let ports = iface.bridgePorts, !ports.isEmpty {
                    Text("ports: \(ports)").font(.caption2).foregroundStyle(.secondary)
                }
                if let gw = iface.gateway, !gw.isEmpty {
                    Text("gateway: \(gw)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Network")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let conn = app.profiles.connection(for: profile) else { return }
            interfaces = ((try? await app.api.nodeNetwork(conn, node: node)) ?? [])
                .sorted { $0.iface < $1.iface }
            loaded = true
        }
    }
}

// MARK: - Storage browser

struct StorageBrowserView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var sections: [(storage: String, volumes: [StorageVolume])] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(sections, id: \.storage) { section in
                Section(section.storage) {
                    if section.volumes.isEmpty {
                        Text("Empty").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(section.volumes) { volume in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: icon(volume.content))
                                    .foregroundStyle(.secondary).frame(width: 22)
                                Text(volume.filename).font(.callout).lineLimit(1)
                                Spacer()
                                Text(sizeString(volume.size)).font(.caption).foregroundStyle(.secondary)
                            }
                            if let content = volume.content {
                                Text(content).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 1)
                        .swipeActions {
                            if isDeletable(volume) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(volume, storage: section.storage)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Storage")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .alert("Failed", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let conn = app.profiles.connection(for: profile) else { return }
        let storages = ((try? await app.api.nodeStorages(conn, node: node, content: nil)) ?? [])
            .map(\.storage).sorted()
        var result: [(String, [StorageVolume])] = []
        for storage in storages {
            let volumes = (try? await app.api.storageContent(conn, node: node, storage: storage, content: nil)) ?? []
            result.append((storage, volumes.sorted { ($0.ctime ?? 0) > ($1.ctime ?? 0) }))
        }
        sections = result
        loaded = true
    }

    private func isDeletable(_ volume: StorageVolume) -> Bool {
        let content = volume.content ?? ""
        return content == "iso" || content == "vztmpl" || content == "backup"
    }

    private func delete(_ volume: StorageVolume, storage: String) {
        guard let conn = app.profiles.connection(for: profile) else { return }
        Task {
            do { _ = try await app.api.deleteVolume(conn, node: node, storage: storage, volid: volume.volid); await load() }
            catch { self.error = error.localizedDescription }
        }
    }

    private func icon(_ content: String?) -> String {
        switch content {
        case "iso": "opticaldisc"
        case "vztmpl": "shippingbox"
        case "backup": "archivebox"
        case "images", "rootdir": "internaldrive"
        default: "doc"
        }
    }
}

// MARK: - SDN

struct SDNView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile

    @State private var zones: [SDNZone] = []
    @State private var vnets: [SDNVNet] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && zones.isEmpty && vnets.isEmpty {
                ContentUnavailableView("No SDN", systemImage: "network",
                                       description: Text("No software-defined networks configured."))
            }
            if !zones.isEmpty {
                Section("Zones") {
                    ForEach(zones) { zone in
                        LabeledContent(zone.zone) { Text(zone.type ?? "-").foregroundStyle(.secondary) }
                    }
                }
            }
            if !vnets.isEmpty {
                Section("VNets") {
                    ForEach(vnets) { vnet in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vnet.vnet).font(.callout.weight(.medium))
                            HStack(spacing: 8) {
                                if let zone = vnet.zone { Text("zone: \(zone)") }
                                if let tag = vnet.tag { Text("tag: \(tag)") }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("SDN")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let conn = app.profiles.connection(for: profile) else { return }
            async let z = app.api.sdnZones(conn)
            async let v = app.api.sdnVNets(conn)
            zones = (try? await z) ?? []
            vnets = (try? await v) ?? []
            loaded = true
        }
    }
}

// MARK: - Replication

struct ReplicationView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile

    @State private var jobs: [ReplicationJob] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && jobs.isEmpty {
                ContentUnavailableView("No Replication", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("No replication jobs configured."))
            }
            ForEach(jobs) { job in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Circle().fill(job.isEnabled ? .green : .secondary).frame(width: 8, height: 8)
                        Text(job.id).font(.callout.weight(.medium))
                        Spacer()
                        if let target = job.target { Text("→ \(target)").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let schedule = job.schedule {
                        Text("schedule: \(schedule)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Replication")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let conn = app.profiles.connection(for: profile) else { return }
            jobs = ((try? await app.api.replicationJobs(conn)) ?? []).sorted { $0.id < $1.id }
            loaded = true
        }
    }
}
