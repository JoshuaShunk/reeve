import ReeveModels
import ReevePersistence
import SwiftUI

private func bytesString(_ value: Int64?) -> String {
    guard let value else { return "-" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
}

// MARK: - Services

struct NodeServicesView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var services: [NodeService] = []
    @State private var error: String?
    @State private var busy: String?

    var body: some View {
        List {
            ForEach(services) { service in
                HStack(spacing: 12) {
                    Circle().fill(service.isRunning ? .green : .secondary)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name).font(.callout.weight(.medium))
                        if let desc = service.desc {
                            Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if busy == service.name {
                        ProgressView().controlSize(.small)
                    } else {
                        Menu {
                            Button("Start", systemImage: "play") { act(service, "start") }
                                .disabled(service.isRunning)
                            Button("Restart", systemImage: "arrow.clockwise") { act(service, "restart") }
                            Button("Stop", systemImage: "stop", role: .destructive) { act(service, "stop") }
                                .disabled(!service.isRunning)
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Services")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if services.isEmpty { ProgressView() } }
        .alert("Failed", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let conn = app.profiles.connection(for: profile) else { return }
        do { services = try await app.api.nodeServices(conn, node: node).sorted { $0.name < $1.name } }
        catch { self.error = error.localizedDescription }
    }

    private func act(_ service: NodeService, _ action: String) {
        guard let conn = app.profiles.connection(for: profile) else { return }
        busy = service.name
        Task {
            do {
                _ = try await app.api.serviceAction(conn, node: node, service: service.name, action: action)
                try? await Task.sleep(for: .seconds(1))
                await load()
            } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }
}

// MARK: - Disks & health

struct NodeDisksView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var disks: [PhysicalDisk] = []
    @State private var pools: [ZFSPool] = []
    @State private var loaded = false

    var body: some View {
        List {
            if !pools.isEmpty {
                Section("ZFS Pools") {
                    ForEach(pools) { pool in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(pool.name).font(.callout.weight(.medium))
                                healthBadge(pool.health, ok: pool.healthy)
                                Spacer()
                                Text("\(bytesString(pool.alloc)) / \(bytesString(pool.size))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let f = pool.usedFraction {
                                ProgressView(value: f).tint(f < 0.85 ? .green : .red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("Physical Disks") {
                ForEach(disks) { disk in diskRow(disk) }
            }
        }
        .navigationTitle("Disks & Health")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let conn = app.profiles.connection(for: profile) else { return }
            async let d = app.api.physicalDisks(conn, node: node)
            async let z = app.api.zfsPools(conn, node: node)
            disks = (try? await d) ?? []
            pools = (try? await z) ?? []
            loaded = true
        }
    }

    private func diskRow(_ disk: PhysicalDisk) -> some View {
        let isSolid = disk.type == "nvme" || disk.type == "ssd"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: isSolid ? "memorychip" : "internaldrive")
                    .foregroundStyle(.secondary)
                Text(disk.model ?? disk.devpath).font(.callout.weight(.medium)).lineLimit(1)
                healthBadge(disk.health, ok: disk.healthy)
                Spacer()
                Text(bytesString(disk.size)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(disk.devpath).font(.caption2).foregroundStyle(.secondary)
                if let used = disk.used {
                    Text("· \(used)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let wear = disk.wearout, isSolid {
                    Text("\(wear)% life").font(.caption2)
                        .foregroundStyle(wear > 20 ? Color.secondary : Color.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func healthBadge(_ text: String?, ok: Bool) -> some View {
        if let text {
            Text(text)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background((ok ? Color.green : Color.red).opacity(0.18), in: Capsule())
                .foregroundStyle(ok ? .green : .red)
        }
    }
}

// MARK: - Updates

struct NodeUpdatesView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var updates: [AptUpdate] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && updates.isEmpty {
                ContentUnavailableView("Up to date", systemImage: "checkmark.seal",
                                       description: Text("No package updates available."))
            }
            ForEach(updates) { update in
                VStack(alignment: .leading, spacing: 2) {
                    Text(update.package).font(.callout.weight(.medium))
                    if let title = update.title {
                        Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(update.oldVersion ?? "-").foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2)
                        Text(update.version ?? "-").foregroundStyle(.green)
                    }
                    .font(.caption2.monospaced())
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle(updates.isEmpty ? "Updates" : "Updates (\(updates.count))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let conn = app.profiles.connection(for: profile) else { return }
            updates = ((try? await app.api.aptUpdates(conn, node: node)) ?? [])
                .sorted { $0.package < $1.package }
            loaded = true
        }
    }
}
