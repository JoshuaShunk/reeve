import AppIntents
import ReeveModels

/// User-facing error when a guest can't be addressed (server not synced, secret
/// missing, offline).
enum ReeveIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable
    case noGuests
    case message(LocalizedStringResource)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable:
            "That guest isn't reachable right now. Open Reeve, make sure the server is added, and try again."
        case .noGuests:
            "No guests are available. Open Reeve and add a server first."
        case .message(let text):
            text
        }
    }
}

nonisolated enum GuestPower {
    static func run(
        _ action: PowerAction, guest: GuestEntity, provider: ProxmoxIntentProvider
    ) async throws {
        guard let t = provider.target(for: guest) else { throw ReeveIntentError.unavailable }
        _ = try await provider.api.power(t.conn, node: t.node, kind: t.kind, vmid: t.vmid, action: action)
    }

    /// Guests to offer for disambiguation when the user didn't name one. We only
    /// return guests the action actually applies to (stopped for Start, running
    /// for Stop/etc.) and deliberately do NOT fall back to all guests: offering a
    /// running guest for "Start" would issue a no-op the success dialog still
    /// reports as done. If nothing is in the right state we throw a clear,
    /// action-specific message instead of an empty or misleading prompt.
    static func pool(
        _ provider: ProxmoxIntentProvider,
        matching keep: (GuestEntity) -> Bool,
        whenNoneMatch message: LocalizedStringResource
    ) async throws -> [GuestEntity] {
        let all = await provider.allGuests()
        guard !all.isEmpty else { throw ReeveIntentError.noGuests }
        let pool = all.filter(keep)
        guard !pool.isEmpty else { throw ReeveIntentError.message(message) }
        return pool
    }
}

struct StartGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Guest"
    static let description = IntentDescription("Start a VM or container in your homelab.")

    @Parameter(title: "Guest") var guest: GuestEntity?
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target: GuestEntity
        if let guest {
            target = guest
        } else {
            let pool = try await GuestPower.pool(
                provider, matching: { $0.status == .stopped },
                whenNoneMatch: "Every guest is already running.")
            target = try await $guest.requestDisambiguation(among: pool, dialog: "Which guest do you want to start?")
        }
        try await GuestPower.run(.start, guest: target, provider: provider)
        return .result(dialog: "Starting \(target.name).")
    }
}

struct RebootGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Reboot Guest"
    static let description = IntentDescription("Reboot a VM or container.")
    // Force a fresh Face ID / Touch ID / passcode check before the reboot runs.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Guest") var guest: GuestEntity?
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target: GuestEntity
        if let guest {
            target = guest
        } else {
            let pool = try await GuestPower.pool(
                provider, matching: { $0.status == .running },
                whenNoneMatch: "No guests are running right now.")
            target = try await $guest.requestDisambiguation(among: pool, dialog: "Which guest do you want to reboot?")
        }
        try await requestConfirmation(result: .result(dialog: "Reboot \(target.name)?"))
        try await GuestPower.run(.reboot, guest: target, provider: provider)
        return .result(dialog: "Rebooting \(target.name).")
    }
}

struct ShutdownGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Shut Down Guest"
    static let description = IntentDescription("Gracefully shut down a VM or container.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Guest") var guest: GuestEntity?
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target: GuestEntity
        if let guest {
            target = guest
        } else {
            let pool = try await GuestPower.pool(
                provider, matching: { $0.status == .running },
                whenNoneMatch: "No guests are running right now.")
            target = try await $guest.requestDisambiguation(among: pool, dialog: "Which guest do you want to shut down?")
        }
        try await requestConfirmation(result: .result(dialog: "Shut down \(target.name)?"))
        try await GuestPower.run(.shutdown, guest: target, provider: provider)
        return .result(dialog: "Shutting down \(target.name).")
    }
}

struct StopGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Guest"
    static let description = IntentDescription("Force-stop (power off) a VM or container.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Guest") var guest: GuestEntity?
    @Dependency var provider: ProxmoxIntentProvider

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target: GuestEntity
        if let guest {
            target = guest
        } else {
            let pool = try await GuestPower.pool(
                provider, matching: { $0.status == .running },
                whenNoneMatch: "No guests are running right now.")
            target = try await $guest.requestDisambiguation(among: pool, dialog: "Which guest do you want to stop?")
        }
        try await requestConfirmation(result: .result(dialog: "Stop \(target.name)? This powers it off immediately."))
        try await GuestPower.run(.stop, guest: target, provider: provider)
        return .result(dialog: "\(target.name) stopped.")
    }
}
