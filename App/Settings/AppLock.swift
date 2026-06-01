import Foundation
import Observation

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Gates the app behind biometric / passcode auth when enabled in Settings.
@MainActor
@Observable
final class AppLock {
    /// True when the app should be hidden behind the lock screen.
    var isLocked = false

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.biometricLock) }

    /// Lock the app (call when entering the background) if the feature is on.
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    /// Prompt for Face ID / Touch ID / passcode and unlock on success.
    func authenticate() async {
        guard isLocked else { return }
        #if canImport(LocalAuthentication)
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode available, don't trap the user out.
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "Unlock Reeve"
            )
            isLocked = !success
        } catch {
            // Leave locked; the user can retry from the lock screen.
        }
        #else
        isLocked = false
        #endif
    }
}
