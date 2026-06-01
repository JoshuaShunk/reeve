import Foundation
import ReeveFeatures
import ReeveModels
import ReeveNetworking
import ReevePersistence
import Observation

/// App-wide dependencies, injected into the SwiftUI environment.
@MainActor
@Observable
final class AppModel {
    let profiles: ProfileStore
    let api: ProxmoxAPI
    let serviceStore: ServiceInstanceStore
    let httpClient: HTTPClient
    /// Node temperatures/fan speeds fetched over SSH, shared across screens.
    let sensors = SensorsStore()

    init(
        profiles: ProfileStore,
        api: ProxmoxAPI,
        serviceStore: ServiceInstanceStore,
        httpClient: HTTPClient
    ) {
        self.profiles = profiles
        self.api = api
        self.serviceStore = serviceStore
        self.httpClient = httpClient
    }

    convenience init() {
        self.init(
            profiles: ProfileStore(),
            api: LiveProxmoxAPI(),
            serviceStore: ServiceInstanceStore(),
            httpClient: LiveHTTPClient()
        )
    }

    func makeServicesModel() -> ServicesModel {
        ServicesModel(store: serviceStore, client: httpClient)
    }

    /// Build a dashboard model for the currently selected profile, if it has a
    /// stored secret.
    func makeDashboard(for profile: ServerProfile) -> DashboardModel? {
        guard let connection = profiles.connection(for: profile) else { return nil }
        return DashboardModel(api: api, connection: connection)
    }

    func makeSnapshots(
        for guest: ClusterResource, profile: ServerProfile
    ) -> SnapshotsModel? {
        guard let connection = profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid,
              let kind = guest.type.guestKind
        else { return nil }
        return SnapshotsModel(
            api: api, connection: connection, node: node, kind: kind, vmid: vmid
        )
    }

    func makeBackups(
        profile: ServerProfile, node: String, storages: [String]
    ) -> BackupsModel? {
        guard let connection = profiles.connection(for: profile) else { return nil }
        return BackupsModel(api: api, connection: connection, node: node, storages: storages)
    }

    func makeTasks(profile: ServerProfile, node: String) -> TasksModel? {
        guard let connection = profiles.connection(for: profile) else { return nil }
        return TasksModel(api: api, connection: connection, node: node)
    }

    func makeNodeDetail(profile: ServerProfile, node: String) -> NodeDetailModel? {
        guard let connection = profiles.connection(for: profile) else { return nil }
        return NodeDetailModel(api: api, connection: connection, node: node)
    }

    func makeGuestDetail(
        for guest: ClusterResource, profile: ServerProfile
    ) -> GuestDetailModel? {
        guard let connection = profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid,
              let kind = guest.type.guestKind
        else { return nil }
        return GuestDetailModel(
            api: api, connection: connection, node: node, kind: kind, vmid: vmid
        )
    }
}
