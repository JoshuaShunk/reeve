import AppIntents

/// "Get Guest Status" — speaks a guest's state and returns the (refreshed) entity
/// so it can chain into other Shortcuts actions.
struct GuestStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Guest Status"
    static let description = IntentDescription("Check a guest's status and CPU usage.")

    @Parameter(title: "Guest") var guest: GuestEntity
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ReturnsValue<GuestEntity> & ProvidesDialog {
        let fresh = (await provider.allGuests()).first { $0.id == guest.id } ?? guest
        // `full` is read aloud on voice-only devices (HomePod/AirPods/CarPlay);
        // `supporting` is the shorter line shown next to on-screen UI.
        let dialog = IntentDialog(
            full: "\(fresh.name) is \(fresh.status.label), \(Int(fresh.cpuPercent)) percent CPU.",
            supporting: "\(fresh.status.label) · \(Int(fresh.cpuPercent))% CPU"
        )
        return .result(value: fresh, dialog: dialog)
    }
}

/// "Homelab Status" — a quick spoken summary across every configured server.
struct HomelabStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Homelab Status"
    static let description = IntentDescription("Summarize how many guests are running across your servers.")

    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let guests = await provider.allGuests()
        let up = guests.filter { $0.status == .running }.count
        let n = provider.serverCount
        let servers = Dictionary(grouping: guests, by: \.serverName)
            .map { HomelabSnippetView.Server(
                name: $0.key,
                up: $0.value.filter { $0.status == .running }.count,
                total: $0.value.count) }
            .sorted { $0.name < $1.name }
        let dialog: IntentDialog = guests.isEmpty
            ? IntentDialog(full: "No servers synced yet. Open Reeve to add one.", supporting: "No servers")
            : IntentDialog(
                full: "\(up) of \(guests.count) guests running across \(n) server\(n == 1 ? "" : "s").",
                supporting: "\(up)/\(guests.count) running")
        return .result(dialog: dialog) {
            HomelabSnippetView(running: up, total: guests.count, servers: servers)
        }
    }
}

/// "Find Guests" — returns a list (optionally filtered) that chains into actions,
/// e.g. Find guests (Stopped) -> Repeat -> Start Guest.
struct FindGuestsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Guests"
    static let description = IntentDescription("Find guests, optionally filtered by status or CPU usage.")

    @Parameter(title: "Status") var status: GuestRunState?
    @Parameter(title: "Minimum CPU Percent") var minCPU: Double?
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ReturnsValue<[GuestEntity]> {
        var guests = await provider.allGuests()
        if let status { guests = guests.filter { $0.status == status } }
        if let minCPU { guests = guests.filter { $0.cpuPercent >= minCPU } }
        return .result(value: guests)
    }
}
