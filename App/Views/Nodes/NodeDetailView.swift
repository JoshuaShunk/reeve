import Charts
import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI

struct NodeDetailView: View {
    @Environment(AppModel.self) private var app
    let nodeName: String
    let profile: ServerProfile

    @State private var model: NodeDetailModel?
    @State private var pendingCommand: String?
    @State private var actionError: String?
    @State private var feedback = ActionFeedbackState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let status = model?.status {
                    metricsCard(status)
                    sensorsCard
                    detailsCard(status)
                    VStack(spacing: 0) {
                        opsLink("Terminal", "terminal") { SSHConsoleView(profile: profile) }
                        Divider().padding(.leading, 48)
                        opsLink("Services", "gearshape.2") {
                            NodeServicesView(profile: profile, node: nodeName)
                        }
                        Divider().padding(.leading, 48)
                        opsLink("Disks & Health", "internaldrive") {
                            NodeDisksView(profile: profile, node: nodeName)
                        }
                        Divider().padding(.leading, 48)
                        opsLink("Updates", "arrow.down.circle") {
                            NodeUpdatesView(profile: profile, node: nodeName)
                        }
                        Divider().padding(.leading, 48)
                        opsLink("Storage", "externaldrive.connected.to.line.below") {
                            StorageBrowserView(profile: profile, node: nodeName)
                        }
                        Divider().padding(.leading, 48)
                        opsLink("Network", "network") {
                            NodeNetworkView(profile: profile, node: nodeName)
                        }
                        Divider().padding(.leading, 48)
                        opsLink("Firewall", "shield.lefthalf.filled") {
                            FirewallView(title: "Firewall",
                                         basePath: "nodes/\(nodeName)/firewall", profile: profile)
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    if let model {
                        Picker("Range", selection: Binding(
                            get: { model.timeframe }, set: { model.timeframe = $0 }
                        )) {
                            ForEach(RRDTimeframe.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        CPUChart(points: model.history)
                        MemoryChart(points: model.history)
                        NetworkChart(points: model.history)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle(nodeName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Reboot", systemImage: "arrow.clockwise") { pendingCommand = "reboot" }
                    Button("Shut Down", systemImage: "power", role: .destructive) {
                        pendingCommand = "shutdown"
                    }
                    Divider()
                    Button("Wake on LAN", systemImage: "powersleep") { wakeOnLAN() }
                } label: { Label("Power", systemImage: "power") }
            }
        }
        .task {
            let created = app.makeNodeDetail(profile: profile, node: nodeName)
            model = created
            await created?.load()
        }
        .task { await app.sensors.refresh(profile: profile, node: nodeName, force: true) }
        .refreshable {
            await model?.loadStatus()
            await app.sensors.refresh(profile: profile, node: nodeName, force: true)
        }
        .confirmationDialog(
            pendingCommand == "reboot" ? "Reboot node" : "Shut down node",
            isPresented: .constant(pendingCommand != nil), titleVisibility: .visible
        ) {
            if let command = pendingCommand {
                Button(command == "reboot" ? "Reboot" : "Shut Down", role: .destructive) {
                    runNodeCommand(command)
                }
            }
            Button("Cancel", role: .cancel) { pendingCommand = nil }
        } message: {
            Text("\(pendingCommand == "reboot" ? "Reboot" : "Shut down") “\(nodeName)”? This affects every guest on the node.")
        }
        .alert("Action failed", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
        .actionFeedback(feedback)
    }

    @ViewBuilder private func opsLink<Destination: View>(
        _ title: LocalizedStringKey, _ symbol: String, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }

    private func runNodeCommand(_ command: String) {
        pendingCommand = nil
        guard let connection = app.profiles.connection(for: profile) else { return }
        Task {
            do {
                _ = try await app.api.nodeCommand(connection, node: nodeName, command: command)
                feedback.signal(.success)
            } catch {
                actionError = error.localizedDescription
                feedback.signal(.failure)
            }
        }
    }

    private func wakeOnLAN() {
        guard let connection = app.profiles.connection(for: profile) else { return }
        Task {
            do {
                _ = try await app.api.wakeOnLAN(connection, node: nodeName)
                feedback.signal(.success)
            } catch {
                actionError = error.localizedDescription
                feedback.signal(.failure)
            }
        }
    }

    private func metricsCard(_ status: NodeStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Online", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.green)
                Spacer()
                Text("up \(Format.uptime(status.uptime))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MetricBar(label: "CPU", fraction: status.cpu,
                      detail: Format.percentValue(status.cpuPercent))
            MetricBar(label: "Memory", fraction: status.memoryFraction,
                      detail: "\(Format.bytes(status.memory.used)) / \(Format.bytes(status.memory.total))")
            if let swap = status.swap, swap.total > 0 {
                MetricBar(label: "Swap", fraction: status.fraction(swap),
                          detail: "\(Format.bytes(swap.used)) / \(Format.bytes(swap.total))")
            }
            if let rootfs = status.rootfs, rootfs.total > 0 {
                MetricBar(label: "Root FS", fraction: status.fraction(rootfs),
                          detail: "\(Format.bytes(rootfs.used)) / \(Format.bytes(rootfs.total))")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var sensorsCard: some View {
        switch app.sensors.state(forNode: nodeName) {
        case .loaded(let sensors):
            VStack(alignment: .leading, spacing: 12) {
                Label("Temperature", systemImage: "thermometer.medium")
                    .font(.headline)
                ForEach(orderedTemperatures(sensors)) { reading in
                    tempRow(reading)
                }
                if !sensors.fans.isEmpty {
                    Divider()
                    ForEach(sensors.fans) { fan in
                        HStack {
                            Label(fan.label, systemImage: "fanblades")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(fan.rpm)) RPM").monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        case .failed, .unavailable, .empty, .unknown:
            EmptyView()   // No sensors / SSH not set up, stay quiet rather than nag.
        }
    }

    /// CPU first (package/Tctl ahead of cores), then drives, then anything else.
    private func orderedTemperatures(_ sensors: NodeSensors) -> [TemperatureReading] {
        sensors.cpuTemperatures + sensors.driveTemperatures + sensors.otherTemperatures
    }

    private func tempRow(_ reading: TemperatureReading) -> some View {
        HStack {
            Image(systemName: symbol(for: reading.category))
                .foregroundStyle(.secondary).frame(width: 20)
            Text(reading.label)
            Spacer()
            Text(Format.temperature(reading.celsius))
                .monospacedDigit().fontWeight(.medium)
                .foregroundStyle(tempColor(reading))
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func symbol(for category: TemperatureReading.Category) -> String {
        switch category {
        case .cpu: "cpu"
        case .drive: "internaldrive"
        case .other: "thermometer.medium"
        }
    }

    private func detailsCard(_ status: NodeStatus) -> some View {
        VStack(spacing: 0) {
            if !status.loadAverages.isEmpty {
                row("Load average", status.loadavg.prefix(3).joined(separator: "  "))
            }
            if let cpus = status.cpuinfo?.cpus {
                row("CPU", "\(cpus) vCPU" + (status.cpuinfo?.cores.map { " · \($0) cores" } ?? ""))
            }
            if let model = status.cpuinfo?.model { row("Model", model) }
            if let pve = status.pveversion { row("Proxmox VE", pve) }
            if let kernel = status.kversion { row("Kernel", kernel) }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
