import AppIntents
import ReeveModels
import ReevePersistence

/// "Reeve Status", reads the snapshot the app last wrote to the shared App
/// Group, so it answers instantly via Siri/Spotlight without credentials or network.
struct ReeveStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Reeve Status"
    static let description = IntentDescription(
        "Check your homelab node's CPU, memory, and how many guests are up."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = WidgetSnapshotStore().load() else {
            return .result(dialog: "Open Reeve once to load your server, then try again.")
        }
        let dialog =
            "\(snapshot.serverName): CPU \(Int(snapshot.cpuPercent)) percent, "
            + "memory \(Int(snapshot.memoryPercent)) percent, "
            + "\(snapshot.guestsUp) of \(snapshot.guestsTotal) guests up."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// The single App Shortcuts provider: every voice phrase Siri/Spotlight exposes.
/// Each phrase MUST contain `\(.applicationName)`; Siri does not auto-synonym
/// verbs, so we list the variants people actually say. Capped well under 10.
struct ReeveShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // Quick, cached, network-free status.
        AppShortcut(
            intent: ReeveStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "Check \(.applicationName)",
            ],
            shortTitle: "Reeve Status",
            systemImageName: "server.rack"
        )
        // Live summary across all servers.
        AppShortcut(
            intent: HomelabStatusIntent(),
            phrases: [
                "Homelab status in \(.applicationName)",
                "How is my homelab in \(.applicationName)",
                "Are my servers up in \(.applicationName)",
            ],
            shortTitle: "Homelab Status",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: StartGuestIntent(),
            phrases: [
                "Start \(\.$guest) in \(.applicationName)",
                "Boot \(\.$guest) in \(.applicationName)",
                "Power on \(\.$guest) in \(.applicationName)",
                "Start a guest in \(.applicationName)",
            ],
            shortTitle: "Start Guest",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopGuestIntent(),
            phrases: [
                "Stop \(\.$guest) in \(.applicationName)",
                "Power off \(\.$guest) in \(.applicationName)",
                "Stop a guest in \(.applicationName)",
            ],
            shortTitle: "Stop Guest",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: RebootGuestIntent(),
            phrases: [
                "Restart \(\.$guest) in \(.applicationName)",
                "Reboot \(\.$guest) in \(.applicationName)",
                "Reboot a guest in \(.applicationName)",
            ],
            shortTitle: "Reboot Guest",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: ShutdownGuestIntent(),
            phrases: [
                "Shut down \(\.$guest) in \(.applicationName)",
                "Shut down a guest in \(.applicationName)",
            ],
            shortTitle: "Shut Down Guest",
            systemImageName: "moon.fill"
        )
        AppShortcut(
            intent: GuestStatusIntent(),
            phrases: [
                "Status of \(\.$guest) in \(.applicationName)",
                "How is \(\.$guest) in \(.applicationName)",
            ],
            shortTitle: "Guest Status",
            systemImageName: "info.circle"
        )
    }
}
