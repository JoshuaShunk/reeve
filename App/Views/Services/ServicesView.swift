import ReeveFeatures
import ReeveModels
import ReeveNetworking
import ReevePersistence
import SwiftUI

// MARK: - Services list (generic, renders any integration)

struct ServicesRootView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ServicesModel?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if app.activeServiceStore.instances.isEmpty {
                    ContentUnavailableView {
                        Label("No Services", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Add a self-hosted service to see its health and stats here.")
                    } actions: {
                        Button("Add Service") { showingAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(app.activeServiceStore.instances) { instance in
                            NavigationLink(value: instance) {
                                ServiceRow(
                                    instance: instance,
                                    state: model?.state(for: instance.id) ?? .loading
                                )
                            }
                        }
                        .onDelete(perform: deleteInstances)
                    }
                    .refreshable { await model?.refreshAll(); syncServiceWidgets() }
                }
            }
            .navigationTitle("Services")
            .toolbar {
                ToolbarItem { Button("Add", systemImage: "plus") { showingAdd = true } }
            }
            .navigationDestination(for: ServiceInstance.self) { instance in
                if let model {
                    ServiceDetailView(instance: instance, model: model)
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddServiceView()
            }
            .task {
                if model == nil { model = app.makeServicesModel() }
                await model?.refreshAll()
                syncServiceWidgets()
            }
            .onChange(of: app.activeServiceStore.instances.count) {
                WidgetSync.refreshDirectory(profiles: app.profiles, services: app.serviceStore)
                Task { await model?.refreshAll(); syncServiceWidgets() }
            }
        }
    }

    /// Mirror each service's latest status into the App Group for the widget.
    private func syncServiceWidgets() {
        guard let model else { return }
        for instance in app.serviceStore.instances {
            WidgetSync.writeService(instance: instance, state: model.state(for: instance.id))
        }
    }

    private func deleteInstances(_ offsets: IndexSet) {
        for index in offsets { app.activeServiceStore.delete(app.activeServiceStore.instances[index]) }
    }
}

struct ServiceRow: View {
    let instance: ServiceInstance
    let state: ServiceState

    var body: some View {
        HStack(spacing: 13) {
            ServiceLogo(typeID: instance.typeID, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name).font(.body.weight(.medium))
                summaryLine
            }
            Spacer()
            if case .loaded(let status) = state, let stat = status.highlightedStats.first {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(stat.displayValue).font(.callout.weight(.semibold).monospacedDigit())
                    Text(stat.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            HealthDot(state: state)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var summaryLine: some View {
        switch state {
        case .loading:
            Text("Loading…").font(.caption).foregroundStyle(.secondary)
        case .failed(let message, _):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
        case .loaded(let status):
            if let summary = status.summary {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if let first = status.highlightedStats.first {
                Text("\(first.label): \(first.displayValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Health shown by shape + color + a spoken label, never color alone, so it
/// satisfies Differentiate Without Color and reads correctly under VoiceOver.
struct HealthDot: View {
    let state: ServiceState

    var body: some View {
        switch state {
        case .loading:
            ProgressView().controlSize(.small)
                .accessibilityLabel("Checking status")
        case .failed:
            StatusGlyph(level: .down, label: "Unreachable", size: 10)
        case .loaded(let status):
            StatusGlyph(level: level(status.health), label: label(status.health), size: 10)
        }
    }

    private func level(_ health: Health) -> StatusGlyph.Level {
        switch health {
        case .ok: .ok
        case .warn: .warn
        case .down: .down
        case .unknown: .neutral
        }
    }

    private func label(_ health: Health) -> String {
        switch health {
        case .ok: "Healthy"
        case .warn: "Warning"
        case .down: "Down"
        case .unknown: "Status unknown"
        }
    }
}

// MARK: - Service detail (generic)

struct ServiceDetailView: View {
    let instance: ServiceInstance
    let model: ServicesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                switch model.state(for: instance.id) {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                case .failed(let message, let date):
                    ContentUnavailableView {
                        Label("Can't reach service", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message + "\n\nLast tried \(date.formatted(.relative(presentation: .named)))")
                    }
                case .loaded(let status):
                    if hasUptimeKumaStatusPage {
                        UptimeKumaStatusView(model: model, instance: instance)
                    }
                    if !status.highlightedStats.isEmpty {
                        heroStats(status.highlightedStats)
                    }
                    let others = status.stats.filter { $0.emphasis == .normal }
                    if !others.isEmpty { statsCard("Stats", rows: others.map { ($0.label, $0.displayValue) }) }
                    if !status.details.isEmpty {
                        statsCard("Details", rows: status.details.map { ($0.label, $0.value) })
                    }
                    statsCard("Info", rows: infoRows(status))
                }
            }
            .padding()
        }
        .navigationTitle(instance.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let url = instance.baseURL {
                ToolbarItem { Link(destination: url) { Label("Open", systemImage: "safari") } }
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh(instance) }
                }
            }
        }
        .task { await model.refresh(instance) }
    }

    private var hasUptimeKumaStatusPage: Bool {
        instance.typeID == UptimeKumaIntegration.typeID
            && !(instance.config["statusPageSlug"] ?? "").isEmpty
    }

    private var header: some View {
        HStack(spacing: 14) {
            ServiceLogo(typeID: instance.typeID, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name).font(.title3.weight(.semibold))
                Text(ServiceCatalogLookup.displayName(for: instance.typeID))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HealthDot(state: model.state(for: instance.id))
        }
    }

    private func heroStats(_ stats: [Stat]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: min(stats.count, 2))
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.displayValue).font(.title2.weight(.semibold).monospacedDigit())
                    Text(stat.label).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func statsCard(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRows(_ status: ServiceStatus) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let version = status.version { rows.append(("Version", version)) }
        if let host = instance.baseURL?.host { rows.append(("Host", host)) }
        rows.append(("Updated", status.fetchedAt.formatted(.relative(presentation: .named))))
        return rows
    }
}

/// View-side lookup of integration metadata by typeID.
enum ServiceCatalogLookup {
    static func symbol(for typeID: String) -> String {
        ServiceCatalog.builtIn.integration(for: typeID)?.iconAsset.systemName
            ?? "square.grid.2x2"
    }
    static func displayName(for typeID: String) -> String {
        ServiceCatalog.builtIn.integration(for: typeID)?.displayName ?? typeID
    }
    static func slug(for typeID: String) -> String {
        ServiceCatalog.builtIn.integration(for: typeID)?.iconSlug ?? typeID
    }
}
