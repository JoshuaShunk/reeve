import Foundation

/// UserDefaults keys shared between the Settings UI and the features that read
/// them (dashboard refresh cadence, background alerts, biometric lock).
enum PreferenceKey {
    static let biometricLock = "pref.biometricLock"
    static let refreshInterval = "pref.refreshInterval"      // seconds
    static let defaultTimeframe = "pref.defaultTimeframe"    // RRDTimeframe.rawValue
    static let alertsEnabled = "pref.alertsEnabled"
    static let cpuThreshold = "pref.cpuThreshold"            // percent 0–100, 0 = off
    static let memThreshold = "pref.memThreshold"            // percent 0–100, 0 = off
    static let tempThreshold = "pref.tempThreshold"          // °C, 0 = off
    static let notifyGuestDown = "pref.notifyGuestDown"
    static let notifyTaskComplete = "pref.notifyTaskComplete"
    static let liveActivitiesEnabled = "pref.liveActivitiesEnabled"
}

extension UserDefaults {
    /// Refresh interval with a sane default when unset (0).
    var refreshIntervalOrDefault: Double {
        let value = double(forKey: PreferenceKey.refreshInterval)
        return value > 0 ? value : 5
    }
}
