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
        let dialog: IntentDialog = "\(fresh.name) is \(fresh.status.label), \(Int(fresh.cpuPercent)) percent CPU."
        return .result(value: fresh, dialog: dialog)
    }
}

/// "Homelab Status" — a quick spoken summary across every configured server.
struct HomelabStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Homelab Status"
    static let description = IntentDescription("Summarize how many guests are running across your servers.")

    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let guests = await provider.allGuests()
        guard !guests.isEmpty else {
            return .result(dialog: "No servers synced yet. Open Reeve to add one.")
        }
        let up = guests.filter { $0.status == .running }.count
        let n = provider.serverCount
        let dialog: IntentDialog = "\(up) of \(guests.count) guests running across \(n) server\(n == 1 ? "" : "s")."
        return .result(dialog: dialog)
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
