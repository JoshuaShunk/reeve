import AppIntents
import ReeveModels
import ReevePersistence

/// VM vs container, as an App Intents enum so it shows nicely in Shortcuts/Siri.
enum GuestKindOption: String, AppEnum {
    case vm
    case container

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Guest Kind" }
    static var caseDisplayRepresentations: [GuestKindOption: DisplayRepresentation] {
        [.vm: "Virtual Machine", .container: "Container"]
    }

    var guestKind: GuestKind { self == .container ? .lxc : .qemu }
}

/// Whether a guest is running, for status display and Find-guests filtering.
enum GuestRunState: String, AppEnum {
    case running
    case stopped
    case unknown

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Status" }
    static var caseDisplayRepresentations: [GuestRunState: DisplayRepresentation] {
        [.running: "Running", .stopped: "Stopped", .unknown: "Unknown"]
    }

    var label: String { rawValue.capitalized }
}

/// A VM or LXC container exposed to Siri / Shortcuts / Spotlight. The `id` encodes
/// everything needed to address it (`profileID|node|kind|vmid`) so an action can
/// run from just the id, even if a live lookup fails.
struct GuestEntity: AppEntity, Identifiable {
    let id: String
    let profileID: String
    let node: String
    let vmid: Int
    let kind: GuestKindOption
    let name: String
    let status: GuestRunState
    let cpuPercent: Double
    let serverName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Guest" }
    static var defaultQuery: GuestQuery { GuestQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(serverName) · \(status.label) · \(Int(cpuPercent))% CPU",
            image: .init(systemName: kind == .container ? "shippingbox" : "desktopcomputer")
        )
    }

    init(
        id: String, profileID: String, node: String, vmid: Int, kind: GuestKindOption,
        name: String, status: GuestRunState, cpuPercent: Double, serverName: String
    ) {
        self.id = id
        self.profileID = profileID
        self.node = node
        self.vmid = vmid
        self.kind = kind
        self.name = name
        self.status = status
        self.cpuPercent = cpuPercent
        self.serverName = serverName
    }

    /// Build from a live cluster-resource row. Returns nil for non-guests/templates.
    init?(resource r: ClusterResource, profile: ServerProfile) {
        guard let node = r.node, let vmid = r.vmid,
              r.type == .qemu || r.type == .lxc, !r.isTemplate else { return nil }
        let kind: GuestKindOption = r.type == .lxc ? .container : .vm
        let status: GuestRunState
        switch r.status {
        case .some(.running), .some(.online): status = .running
        case .some(.stopped), .some(.offline): status = .stopped
        default: status = .unknown   // nil or an indeterminate/transient state
        }
        self.init(
            id: GuestEntity.makeID(profile: profile.id.uuidString, node: node, kind: kind, vmid: vmid),
            profileID: profile.id.uuidString,
            node: node,
            vmid: vmid,
            kind: kind,
            name: r.displayName,
            status: status,
            cpuPercent: (r.cpu ?? 0) * 100,
            serverName: profile.name
        )
    }

    static func makeID(profile: String, node: String, kind: GuestKindOption, vmid: Int) -> String {
        // Encode the Proxmox kind ("qemu"/"lxc") so the id round-trips through
        // `reconstruct(id:)` and stays stable if the UI enum is ever renamed.
        "\(profile)|\(node)|\(kind.guestKind.rawValue)|\(vmid)"
    }
}

/// Resolves guests by id (for saved shortcuts) and by spoken name (so "Restart
/// Plex" finds the Plex guest). Backed by the shared `ProxmoxIntentProvider`.
struct GuestQuery: EntityStringQuery {
    @Dependency var provider: ProxmoxIntentProvider

    func entities(for identifiers: [String]) async throws -> [GuestEntity] {
        let all = await provider.allGuests()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0] ?? provider.reconstruct(id: $0) }
    }

    func suggestedEntities() async throws -> [GuestEntity] {
        await provider.allGuests()
    }

    func entities(matching string: String) async throws -> [GuestEntity] {
        await provider.allGuests().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}
