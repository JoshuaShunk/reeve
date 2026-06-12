import Foundation
import WatchConnectivity
import ReevePersistence

/// Watch side of the credential sync. Receives the `WatchSyncPayload` the iPhone
/// pushes via `updateApplicationContext`, writes it into this device's
/// `ProfileStore` (UserDefaults metadata + Keychain secrets), and notifies the
/// model so the UI rebuilds.
@MainActor
final class WatchConnectivityManager: NSObject {
    private let profiles: ProfileStore

    /// Called on the main actor after a fresh payload is ingested.
    var onUpdate: (() -> Void)?

    init(profiles: ProfileStore) {
        self.profiles = profiles
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Ask the phone to send the latest profiles (used by a manual "Sync" action).
    func requestSync() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "sync"], replyHandler: nil, errorHandler: nil)
    }

    private func ingest(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) else { return }
        profiles.replaceAll(with: payload)
        onUpdate?()
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Pull whatever context the phone last delivered (covers first launch).
        let data = session.receivedApplicationContext["payload"] as? Data
        Task { @MainActor in if let data { self.ingest(data) } }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let data = applicationContext["payload"] as? Data
        Task { @MainActor in if let data { self.ingest(data) } }
    }
}
