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

/// Surfaces the intent in the Shortcuts app, Spotlight, and Siri.
struct ReeveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReeveStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "Check \(.applicationName)",
                "How is my homelab in \(.applicationName)",
            ],
            shortTitle: "Reeve Status",
            systemImageName: "server.rack"
        )
    }
}
