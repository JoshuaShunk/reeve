import AppIntents
import Charts
import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI

/// Per-guest detail: live status, power controls, and Swift Charts time-series.
struct GuestDetailView: View {
    @Environment(AppModel.self) private var app
    let guest: ClusterResource
    let profile: ServerProfile

    @Environment(\.dismiss) private var dismiss
    @State private var model: GuestDetailModel?
    @State private var pendingAction: PowerAction?
    @State private var actionError: String?
    @State private var manageSheet: GuestManageSheet?
    @State private var confirmDelete = false
    @State private var confirmTemplate = false
    @State private var purgeOnDelete = true
    @State private var feedback = ActionFeedbackState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let model, let status = model.status {
                    detailsCard(status, model: model)
                }
                if let config = model?.config {
                    configCard(config)
                }
                if let notes = model?.config?.notes {
                    HTMLNotesView(html: notes)
                        .padding(.vertical, 8)
                        .cardStyle("Notes")
                }
                VStack(spacing: 0) {
                    NavigationLink {
                        SnapshotsView(guest: guest, profile: profile)
                    } label: { linkRow("Snapshots", "camera.viewfinder") }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    Divider().padding(.leading, 48)
                    NavigationLink {
                        GuestConsoleView(guest: guest, profile: profile)
                    } label: { linkRow("Console", "terminal") }
                    .buttonStyle(.plain)
                    if guest.type.guestKind == .qemu {
                        Divider().padding(.leading, 48)
                        NavigationLink {
                            VNCConsoleView(guest: guest, profile: profile)
                        } label: { linkRow("Graphical Console", "display") }
                        .buttonStyle(.plain)
                    }
                    #endif
                    if let node = guest.node, let vmid = guest.vmid,
                       let kind = guest.type.guestKind {
                        Divider().padding(.leading, 48)
                        NavigationLink {
                            FirewallView(title: "Firewall",
                                         basePath: "nodes/\(node)/\(kind.pathSegment)/\(vmid)/firewall",
                                         profile: profile)
                        } label: { linkRow("Firewall", "shield.lefthalf.filled") }
                        .buttonStyle(.plain)
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                #if os(iOS)
                SiriTipView(intent: StartGuestIntent())
                #endif
                if let model {
                    timeframePicker(model)
                    CPUChart(points: model.history)
                    MemoryChart(points: model.history)
                    DiskIOChart(points: model.history)
                    NetworkChart(points: model.history)
                }
                if let model, !model.recentTasks.isEmpty {
                    recentActivity(model.recentTasks)
                }
            }
            .padding()
        }
        .navigationTitle(guest.displayName)
        .toolbar { powerMenu; manageMenu }
        .task {
            let model = app.makeGuestDetail(for: guest, profile: profile)
            self.model = model
            await model?.load()
        }
        .alert("Action failed", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
        .confirmationDialog(
            pendingAction?.label ?? "",
            isPresented: .constant(pendingAction != nil),
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                Button(action.label, role: action == .start ? nil : .destructive) {
                    Task { await run(action) }
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text("\(pendingAction?.label ?? "") “\(guest.displayName)”?")
        }
        .sheet(item: $manageSheet) { sheet in
            switch sheet {
            case .clone:
                CloneGuestSheet(guest: guest, profile: profile) { Task { await model?.load() } }
            case .editResources:
                EditResourcesSheet(guest: guest, profile: profile, config: model?.config) {
                    Task { await model?.load() }
                }
            case .resizeDisk:
                ResizeDiskSheet(guest: guest, profile: profile, config: model?.config) {
                    Task { await model?.load() }
                }
            case .migrate:
                MigrateGuestSheet(guest: guest, profile: profile) { Task { await model?.load() } }
            case .backup:
                BackupNowSheet(guest: guest, profile: profile) { Task { await model?.load() } }
            case .tagsNotes:
                TagsNotesSheet(guest: guest, profile: profile, config: model?.config) {
                    Task { await model?.load() }
                }
            case .cloudInit:
                CloudInitSheet(guest: guest, profile: profile, config: model?.config) {
                    Task { await model?.load() }
                }
            }
        }
        .confirmationDialog("Convert to Template",
                            isPresented: $confirmTemplate, titleVisibility: .visible) {
            Button("Convert to Template", role: .destructive) { convertToTemplate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(guest.displayName)” will become a template and can no longer be started directly. This can't be undone.")
        }
        .confirmationDialog("Delete \(guest.displayName)",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { deleteGuest() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This destroys the \(guest.type.guestKind?.label ?? "guest") and all its disks. This can't be undone.")
        }
        .actionFeedback(feedback)
    }

    private func linkRow(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding()
    }

    @ToolbarContentBuilder private var manageMenu: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("Clone…", systemImage: "doc.on.doc") { manageSheet = .clone }
                Button("Edit Resources…", systemImage: "cpu") { manageSheet = .editResources }
                Button("Resize Disk…", systemImage: "internaldrive") { manageSheet = .resizeDisk }
                Button("Migrate…", systemImage: "arrow.left.arrow.right") { manageSheet = .migrate }
                Button("Back Up Now…", systemImage: "archivebox") { manageSheet = .backup }
                Button("Tags & Notes…", systemImage: "tag") { manageSheet = .tagsNotes }
                if guest.type.guestKind == .qemu {
                    Button("Cloud-Init…", systemImage: "cloud") { manageSheet = .cloudInit }
                }
                Divider()
                Button("Convert to Template…", systemImage: "doc.badge.gearshape") {
                    confirmTemplate = true
                }
                Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Label("Manage", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func convertToTemplate() {
        guard let connection = app.profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid,
              let kind = guest.type.guestKind else { return }
        Task {
            do {
                _ = try await app.api.convertToTemplate(connection, node: node, kind: kind, vmid: vmid)
                await model?.load()
                feedback.signal(.success)
            } catch {
                actionError = error.localizedDescription
                feedback.signal(.failure)
            }
        }
    }

    private func deleteGuest() {
        guard let connection = app.profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid,
              let kind = guest.type.guestKind else { return }
        Task {
            do {
                _ = try await app.api.deleteGuest(
                    connection, node: node, kind: kind, vmid: vmid, purge: purgeOnDelete
                )
                feedback.signal(.success)
                dismiss()
            } catch {
                actionError = error.localizedDescription
                feedback.signal(.failure)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    guest.type.guestKind?.label ?? "Guest",
                    systemImage: guest.type == .qemu ? "desktopcomputer" : "shippingbox"
                )
                .foregroundStyle(.secondary)
                Spacer()
                StatusPill(isUp: guest.status?.isUp == true)
            }
            if let s = model?.status {
                MetricBar(label: "CPU", fraction: s.cpu, detail: Format.percentValue(s.cpuPercent))
                MetricBar(
                    label: "RAM", fraction: s.memoryFraction,
                    detail: "\(Format.bytes(s.mem)) / \(Format.bytes(s.maxmem))"
                )
                if let disk = s.disk, let maxdisk = s.maxdisk, disk > 0, maxdisk > 0 {
                    MetricBar(
                        label: "Disk", fraction: Double(disk) / Double(maxdisk),
                        detail: "\(Format.bytes(disk)) / \(Format.bytes(maxdisk))"
                    )
                }
                HStack(spacing: 16) {
                    Stat("Uptime", Format.uptime(s.uptime))
                    Stat("vCPU", s.cpus.map(String.init) ?? "-")
                    Stat("VMID", guest.vmid.map(String.init) ?? "-")
                    Stat("Node", guest.node ?? "-")
                }
                if let ips = model?.ipAddresses, !ips.isEmpty {
                    Stat("IP", ips.joined(separator: ", "))
                }
            }
        }
    }

    private func detailsCard(_ status: GuestStatus, model: GuestDetailModel) -> some View {
        VStack(spacing: 0) {
            detailRow("Network in", Format.bytes(status.netin))
            detailRow("Network out", Format.bytes(status.netout))
            detailRow("Disk read", Format.bytes(status.diskread))
            detailRow("Disk write", Format.bytes(status.diskwrite))
            if let pid = status.pid, pid > 0 {
                detailRow("Process ID", String(pid))
            }
        }
        .cardStyle("Live")
    }

    @ViewBuilder private func configCard(_ config: GuestConfig) -> some View {
        VStack(spacing: 0) {
            if let cores = config.cores {
                detailRow("Cores", cores + (config.sockets.map { " × \($0) sockets" } ?? ""))
            }
            if let memory = config.memoryMB {
                // Int64 so the MB->bytes multiply can't overflow 32-bit Int on watchOS.
                detailRow("Memory", Format.bytes(Int64(memory) * 1_048_576))
            }
            if let os = config.osType { detailRow("OS type", os) }
            if let boot = config.bootOrder { detailRow("Boot order", boot) }
            ForEach(config.disks, id: \.id) { disk in
                detailRow(verbatim: disk.id, disk.value)
            }
            ForEach(config.networks, id: \.id) { net in
                detailRow(verbatim: net.id, net.value)
            }
        }
        .cardStyle("Configuration")
    }

    private func recentActivity(_ tasks: [ProxmoxTaskInfo]) -> some View {
        VStack(spacing: 0) {
            ForEach(tasks.prefix(8)) { task in
                HStack {
                    Text(task.type).font(.callout)
                    Spacer()
                    Text(task.displayStatus)
                        .font(.caption)
                        .foregroundStyle(task.isRunning ? Color.secondary : (task.succeeded ? Color.green : Color.red))
                }
                .padding(.vertical, 8)
            }
        }
        .cardStyle("Recent activity")
    }

    /// Static, translatable label.
    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        detailRow(label: Text(label), value: value)
    }

    /// Dynamic label that is data, not UI text (e.g. a disk/NIC config key).
    private func detailRow(verbatim label: String, _ value: String) -> some View {
        detailRow(label: Text(verbatim: label), value: value)
    }

    private func detailRow(label: Text, value: String) -> some View {
        HStack(alignment: .top) {
            label.foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func timeframePicker(_ model: GuestDetailModel) -> some View {
        Picker("Timeframe", selection: Binding(
            get: { model.timeframe },
            set: { model.timeframe = $0 }
        )) {
            ForEach(RRDTimeframe.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// Most up-to-date run state: live status if loaded, else the cluster row.
    private var isRunning: Bool {
        model?.status?.status.isUp ?? (guest.status?.isUp == true)
    }

    /// Only offer actions that make sense for the current state.
    private var availableActions: [PowerAction] {
        isRunning ? [.shutdown, .reboot, .stop] : [.start]
    }

    @ToolbarContentBuilder private var powerMenu: some ToolbarContent {
        ToolbarItem {
            Menu {
                ForEach(availableActions) { action in
                    Button(action.label, systemImage: action.symbol) { pendingAction = action }
                }
            } label: {
                Label("Power", systemImage: "power")
            }
        }
    }

    private func run(_ action: PowerAction) async {
        pendingAction = nil
        guard let connection = app.profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid,
              let kind = guest.type.guestKind else { return }
        do {
            _ = try await app.api.power(
                connection, node: node, kind: kind, vmid: vmid, action: action
            )
            try? await Task.sleep(for: .seconds(1))
            await model?.loadStatus()
            feedback.signal(.success)
        } catch {
            actionError = error.localizedDescription
            feedback.signal(.failure)
        }
    }
}

extension View {
    /// Wraps content in a titled, rounded card.
    fileprivate func cardStyle(_ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            self
                .padding(.horizontal, 14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusPill: View {
    let isUp: Bool
    var body: some View {
        Text(isUp ? "Running" : "Stopped")
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isUp ? Color.green.opacity(0.2) : Color.gray.opacity(0.2), in: Capsule())
            .foregroundStyle(isUp ? .green : .secondary)
    }
}

private struct Stat: View {
    let title: LocalizedStringKey
    let value: String
    init(_ title: LocalizedStringKey, _ value: String) { self.title = title; self.value = value }
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(verbatim: value).font(.callout.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}
