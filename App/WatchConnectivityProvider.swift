#if os(iOS)
import Foundation
import WatchConnectivity
import ReevePersistence

/// iPhone side of the Apple Watch sync. Pushes the server profile list and their
/// secrets to the paired watch via `updateApplicationContext`, which is the right
/// WatchConnectivity primitive for "latest state wins" config: it is delivered in
/// the background, needs no live reachability, and coalesces to only the newest
/// value. Secrets ride the encrypted WatchConnectivity channel; the watch stores
/// them in its own Keychain (App Groups / Keychain do not cross devices).
@MainActor
final class WatchConnectivityProvider: NSObject {
    static let shared = WatchConnectivityProvider()

    private var pending: WatchSyncPayload?

    /// Activate the session once, early in app launch.
    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Queue the latest profiles for delivery and try to flush immediately.
    func sync(_ payload: WatchSyncPayload) {
        pending = payload
        flush()
    }

    /// Convenience: build the payload from a `ProfileStore` and send it.
    func sync(from store: ProfileStore) {
        sync(store.watchSyncPayload())
    }

    private func flush() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let payload = pending else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try session.updateApplicationContext(["payload": data])
            pending = nil
        } catch {
            // Keep `pending` so the next activation/sync retries.
        }
    }
}

extension WatchConnectivityProvider: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a swapped watch keeps receiving updates.
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // A watch was paired or the app installed; flush any queued payload.
        Task { @MainActor in self.flush() }
    }
}
#endif
