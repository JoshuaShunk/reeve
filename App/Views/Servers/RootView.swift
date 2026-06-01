import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI
import WidgetKit

/// Picks the active server and hands off to a `ServerScene` that owns its
/// dashboard. The `.id(profile.id)` ensures we build a fresh scene (and a fresh
/// `DashboardModel`) only when the selected server actually changes.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let profile = app.profiles.selectedProfile {
            ServerScene(profile: profile)
                .id(profile.id)
        } else {
            EmptyServerView()
        }
    }
}

/// Owns a single server's `DashboardModel` for its lifetime. Created once in
/// `@State` so re-renders (e.g. changing the selected guest) don't discard the
/// fetched data.
struct ServerScene: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile

    @State private var dashboard: DashboardModel?
    @State private var selectedGuestID: ClusterResource.ID?
    @State private var route: DashboardRoute?
    @State private var showingServers = false
    @State private var showingSettings = false
    @State private var showingCreate = false
    @AppStorage(PreferenceKey.refreshInterval) private var refreshInterval = 5.0
    @AppStorage(PreferenceKey.alertsEnabled) private var alertsEnabled = false
    @AppStorage(PreferenceKey.liveActivitiesEnabled) private var liveActivitiesEnabled = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var connectionMissing: Bool { app.profiles.connection(for: profile) == nil }

    private func writeWidgetSnapshot(_ dashboard: DashboardModel) {
        guard let node = dashboard.nodes.first else { return }
        let snapshot = WidgetSnapshot(
            serverName: profile.name,
            cpuPercent: node.cpuPercent ?? 0,
            memoryPercent: (node.memoryFraction ?? 0) * 100,
            guestsUp: dashboard.runningGuestCount,
            guestsTotal: dashboard.guests.count
        )
        WidgetSnapshotStore().save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        WidgetSync.writeServer(
            profile: profile,
            cpuPercent: node.cpuPercent ?? 0,
            memoryPercent: (node.memoryFraction ?? 0) * 100,
            guestsUp: dashboard.runningGuestCount,
            guestsTotal: dashboard.guests.count
        )
    }

    private var nodeName: String { dashboard?.nodes.first?.node ?? "" }
    private var backupStorages: [String] {
        (dashboard?.storages ?? [])
            .filter { ($0.content ?? "").contains("backup") }
            .compactMap { $0.storage }
    }

    var body: some View {
        layout
        .task(id: refreshInterval) {
            if dashboard == nil {
                dashboard = app.makeDashboard(for: profile)
            }
            if alertsEnabled { await AlertCenter.shared.requestAuthorizationIfNeeded() }
            await dashboard?.autoRefresh(every: refreshInterval)
        }
        .onChange(of: dashboard?.lastUpdated) {
            guard let dashboard else { return }
            if alertsEnabled {
                AlertCenter.shared.evaluate(dashboard.resources)
                AlertCenter.shared.evaluateTasks(dashboard.recentTasks)
            }
            // Refresh node temperatures over SSH (throttled in the store) and alert on heat.
            if let node = dashboard.nodes.first?.node {
                Task {
                    await app.sensors.refresh(profile: profile, node: node)
                    if alertsEnabled, let sensors = app.sensors.sensors(forNode: node) {
                        AlertCenter.shared.evaluateTemperature(sensors, nodeName: node)
                    }
                }
            }
            #if os(iOS)
            LiveActivityController.shared.sync(
                tasks: dashboard.recentTasks, enabled: liveActivitiesEnabled
            )
            #endif
            writeWidgetSnapshot(dashboard)
        }
        .sheet(isPresented: $showingServers) {
            NavigationStack { ServerListView() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCreate) {
            CreateGuestView(profile: profile, node: nodeName) {
                Task { await dashboard?.refresh() }
            }
        }
    }

    // Split view on iPad / Mac (regular width); a stack on iPhone (compact).
    @ViewBuilder private var layout: some View {
        #if os(iOS)
        if sizeClass == .regular { splitLayout } else { stackLayout }
        #else
        splitLayout
        #endif
    }

    private var stackLayout: some View {
        NavigationStack {
            DashboardSidebar(
                dashboard: dashboard, profile: profile, connectionMissing: connectionMissing
            )
            .navigationTitle(profile.name)
            .toolbar { dashboardToolbar }
            .navigationDestination(for: ClusterResource.self) { guest in
                GuestDetailView(guest: guest, profile: profile)
            }
            .navigationDestination(item: $route, destination: routeDestination)
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            DashboardSidebar(
                dashboard: dashboard, profile: profile, connectionMissing: connectionMissing,
                selection: $selectedGuestID
            )
            .navigationTitle(profile.name)
            .toolbar { dashboardToolbar }
            .navigationDestination(item: $route, destination: routeDestination)
        } detail: {
            if let id = selectedGuestID,
               let guest = dashboard?.guests.first(where: { $0.id == id }) {
                NavigationStack {
                    GuestDetailView(guest: guest, profile: profile).id(guest.id)
                }
            } else {
                ContentUnavailableView(
                    "Select a VM or container", systemImage: "cube",
                    description: Text("Pick a guest to see live metrics and history.")
                )
            }
        }
    }

    /// A single visible primary action (create) plus an overflow menu keeps the
    /// nav bar uncluttered instead of crowding seven equal-weight icons, and the
    /// menu groups server-scoped views apart from app-level actions.
    @ToolbarContentBuilder private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: {
                Label("Create Guest", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section("This Server") {
                    Button { route = .activity } label: {
                        Label("Activity", systemImage: "list.bullet.rectangle")
                    }
                    Button { route = .backups } label: {
                        Label("Backups", systemImage: "archivebox")
                    }
                    Button { route = .datacenter } label: {
                        Label("Datacenter", systemImage: "building.2")
                    }
                }
                Section {
                    Button { route = .allServers } label: {
                        Label("Search All Servers", systemImage: "magnifyingglass")
                    }
                    Button { showingServers = true } label: {
                        Label("Switch Server", systemImage: "server.rack")
                    }
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder private func routeDestination(_ route: DashboardRoute) -> some View {
        switch route {
        case .activity:
            TasksView(profile: profile, node: nodeName)
        case .backups:
            BackupsView(profile: profile, node: nodeName, storages: backupStorages)
        case .datacenter:
            DatacenterView(profile: profile)
        case .allServers:
            AllServersView()
        }
    }
}

/// Push destinations reachable from the dashboard's overflow menu.
enum DashboardRoute: Hashable {
    case activity, backups, datacenter, allServers
}

/// Shown when no server is configured yet.
struct EmptyServerView: View {
    @State private var showingAdd = false

    var body: some View {
        ContentUnavailableView {
            Label("No Servers Yet", systemImage: "server.rack")
        } description: {
            Text("Add your Proxmox server with a read-only API token to get started.")
        } actions: {
            Button("Add Server") { showingAdd = true }
                .glassProminentButton()
        }
        .sheet(isPresented: $showingAdd) {
            AddServerView()
        }
    }
}
