import AppIntents
import ReeveModels

/// User-facing error when a guest can't be addressed (server not synced, secret
/// missing, offline).
enum ReeveIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable

    var localizedStringResource: LocalizedStringResource {
        "That guest isn't reachable right now. Open Reeve, make sure the server is added, and try again."
    }
}

private enum GuestPower {
    static func run(
        _ action: PowerAction, guest: GuestEntity, provider: ProxmoxIntentProvider
    ) async throws {
        guard let t = provider.target(for: guest) else { throw ReeveIntentError.unavailable }
        _ = try await provider.api.power(t.conn, node: t.node, kind: t.kind, vmid: t.vmid, action: action)
    }
}

struct StartGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Guest"
    static let description = IntentDescription("Start a VM or container in your homelab.")

    @Parameter(title: "Guest") var guest: GuestEntity
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await GuestPower.run(.start, guest: guest, provider: provider)
        return .result(dialog: "Starting \(guest.name).")
    }
}

struct RebootGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Reboot Guest"
    static let description = IntentDescription("Reboot a VM or container.")
    // Force a fresh Face ID / Touch ID / passcode check before the reboot runs.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Guest") var guest: GuestEntity
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(result: .result(dialog: "Reboot \(guest.name)?"))
        try await GuestPower.run(.reboot, guest: guest, provider: provider)
        return .result(dialog: "Rebooting \(guest.name).")
    }
}

struct ShutdownGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Shut Down Guest"
    static let description = IntentDescription("Gracefully shut down a VM or container.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Guest") var guest: GuestEntity
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(result: .result(dialog: "Shut down \(guest.name)?"))
        try await GuestPower.run(.shutdown, guest: guest, provider: provider)
        return .result(dialog: "Shutting down \(guest.name).")
    }
}

struct StopGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Guest"
    static let description = IntentDescription("Force-stop (power off) a VM or container.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Guest") var guest: GuestEntity
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(result: .result(dialog: "Stop \(guest.name)? This powers it off immediately."))
        try await GuestPower.run(.stop, guest: guest, provider: provider)
        return .result(dialog: "\(guest.name) stopped.")
    }
}
