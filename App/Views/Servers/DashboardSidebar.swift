import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI

/// The server dashboard: an at-a-glance KPI overview on top, then the node card,
/// guests, and storage. The `List` is always the root content (loading / error /
/// missing states are overlays) so it stays the NavigationStack's scroll view and
/// flows under the iOS 26 floating tab bar, a conditional wrapper here makes the
/// bar reserve a solid inset.
struct DashboardSidebar: View {
    @Environment(AppModel.self) private var app
    let dashboard: DashboardModel?
    var profile: ServerProfile?
    var connectionMissing = false
    /// When provided (split layout), guests are selectable rows driving the detail
    /// column; when nil (stack layout), they're value-based navigation links.
    var selection: Binding<ClusterResource.ID?>?

    var body: some View {
        Group {
            if let selection {
                List(selection: selection) { sections(selectable: true) }
            } else {
                List { sections(selectable: false) }
            }
        }
        .overlay { stateOverlay }
        .refreshable { await dashboard?.refresh() }
    }

    @ViewBuilder private func sections(selectable: Bool) -> some View {
        if let dashboard {
            if let node = dashboard.nodes.first {
                overviewSection(dashboard: dashboard, node: node)
                nodeSection(node: node)
            }
            guestsSection(dashboard: dashboard, selectable: selectable)
            storageSection(dashboard: dashboard)
        }
    }

    // MARK: - Overview KPIs

    @ViewBuilder
    private func overviewSection(dashboard: DashboardModel, node: ClusterResource) -> some View {
        let storage = Self.storageUsage(dashboard.storages)
        let guestFraction = dashboard.guests.isEmpty
            ? nil
            : Double(dashboard.runningGuestCount) / Double(dashboard.guests.count)

        Section {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                ],
                spacing: Theme.Spacing.md
            ) {
                StatTile(
                    title: "CPU", value: Format.percent(node.cpu),
                    systemImage: "cpu", tint: loadColor(node.cpu), fraction: node.cpu
                )
                StatTile(
                    title: "Memory", value: Format.percent(node.memoryFraction),
                    systemImage: "memorychip", tint: loadColor(node.memoryFraction),
                    fraction: node.memoryFraction
                )
                StatTile(
                    title: "Guests",
                    value: "\(dashboard.runningGuestCount)/\(dashboard.guests.count)",
                    systemImage: "square.stack.3d.up", tint: .accentColor,
                    fraction: guestFraction, caption: "running"
                )
                StatTile(
                    title: "Storage", value: Format.percent(storage.fraction),
                    systemImage: "internaldrive", tint: loadColor(storage.fraction),
                    fraction: storage.fraction
                )
                if let cpuTemp = app.sensors.sensors(forNode: node.node ?? node.displayName)?.primaryCPU {
                    StatTile(
                        title: "Temp", value: Format.temperature(cpuTemp.celsius),
                        systemImage: "thermometer.medium", tint: tempColor(cpuTemp),
                        fraction: min(cpuTemp.celsius / 100, 1), caption: "CPU"
                    )
                }
            }
            .listRowInsets(EdgeInsets(
                top: Theme.Spacing.sm, leading: Theme.Spacing.lg,
                bottom: Theme.Spacing.xs, trailing: Theme.Spacing.lg
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } footer: {
            if let updated = dashboard.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Node

    @ViewBuilder
    private func nodeSection(node: ClusterResource) -> some View {
        Section("Node") {
            if let profile {
                NavigationLink {
                    NodeDetailView(nodeName: node.node ?? node.displayName, profile: profile)
                } label: {
                    NodeSummaryCard(node: node)
                }
            } else {
                NodeSummaryCard(node: node)
            }
        }
    }

    // MARK: - Guests

    @ViewBuilder
    private func guestsSection(dashboard: DashboardModel, selectable: Bool) -> some View {
        Section {
            ForEach(dashboard.guests) { guest in
                if selectable {
                    GuestRow(guest: guest).tag(guest.id)
                } else {
                    NavigationLink(value: guest) { GuestRow(guest: guest) }
                }
            }
        } header: {
            HStack {
                Text("Guests")
                Spacer()
                Text("\(dashboard.runningGuestCount) of \(dashboard.guests.count) running")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Storage

    @ViewBuilder
    private func storageSection(dashboard: DashboardModel) -> some View {
        if !dashboard.storages.isEmpty {
            Section("Storage") {
                ForEach(dashboard.storages) { storage in
                    StorageRow(storage: storage)
                }
            }
        }
    }

    /// Aggregate used/total across all storages that report a capacity.
    static func storageUsage(_ storages: [ClusterResource]) -> (fraction: Double?, detail: String) {
        let sized = storages.filter { ($0.maxdisk ?? 0) > 0 }
        let used = sized.reduce(0) { $0 + ($1.disk ?? 0) }
        let total = sized.reduce(0) { $0 + ($1.maxdisk ?? 0) }
        guard total > 0 else { return (nil, "-") }
        return (Double(used) / Double(total), "\(Format.bytes(used)) / \(Format.bytes(total))")
    }

    @ViewBuilder private var stateOverlay: some View {
        if connectionMissing {
            ContentUnavailableView(
                "Missing credentials", systemImage: "key.slash",
                description: Text("This server has no saved token secret. Edit it under Servers.")
            )
        } else if let dashboard {
            if case .failed(let message) = dashboard.state {
                ContentUnavailableView(
                    "Can't reach server", systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
            }
        } else {
            ProgressView("Connecting…")
        }
    }
}

// MARK: - Components

/// A compact KPI tile for the overview grid: label, large value, and an optional
/// utilisation bar, the standard enterprise-dashboard summary card.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var tint: Color = .secondary
    var fraction: Double?
    var caption: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            UtilizationBar(fraction: fraction, tint: tint)
                .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// A bare rounded utilisation bar (0–1) with no labels, used inside tiles and rows.
struct UtilizationBar: View {
    let fraction: Double?
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction ?? 0, 0), 1)))
            }
        }
    }
}

/// A small status pill: green "Running" / muted "Stopped".
struct RunStatePill: View {
    let isUp: Bool

    var body: some View {
        Text(isUp ? "Running" : "Stopped")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isUp ? Color.green : Color.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(
                (isUp ? Color.green : Color.secondary).opacity(0.14),
                in: Capsule()
            )
    }
}

struct NodeSummaryCard: View {
    let node: ClusterResource

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(node.displayName).font(.headline)
                RunStatePill(isUp: node.status?.isUp == true)
                Spacer()
                Label(Format.uptime(node.uptime), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            MetricBar(label: "CPU", fraction: node.cpu, detail: Format.percentValue(node.cpuPercent))
            MetricBar(
                label: "RAM", fraction: node.memoryFraction,
                detail: "\(Format.bytes(node.mem)) / \(Format.bytes(node.maxmem))"
            )
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

struct GuestRow: View {
    let guest: ClusterResource

    private var isUp: Bool { guest.status?.isUp == true }
    private var typeLabel: String { guest.type == .qemu ? "VM" : "LXC" }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: guest.type == .qemu ? "desktopcomputer" : "shippingbox")
                .font(.callout)
                .foregroundStyle(isUp ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.control))

            VStack(alignment: .leading, spacing: 3) {
                Text(guest.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(guest.vmid.map { "#\($0)" } ?? "")
                        .monospacedDigit()
                    Text(typeLabel)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 3) {
                RunStatePill(isUp: isUp)
                if isUp {
                    Text(Format.percentValue(guest.cpuPercent))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(loadColor(guest.cpu))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StorageRow: View {
    let storage: ClusterResource

    private var usedFraction: Double? {
        guard let disk = storage.disk, let max = storage.maxdisk, max > 0 else { return nil }
        return Double(disk) / Double(max)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(storage.storage ?? storage.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(Format.percent(usedFraction))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(loadColor(usedFraction))
            }
            UtilizationBar(fraction: usedFraction, tint: loadColor(usedFraction))
                .frame(height: 5)
            Text("\(Format.bytes(storage.disk)) / \(Format.bytes(storage.maxdisk))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
