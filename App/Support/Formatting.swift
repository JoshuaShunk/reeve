import Foundation
import ReeveModels
import SwiftUI

/// Shared display formatting helpers.
enum Format {
    static func bytes(_ value: Int?) -> String {
        guard let value else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "-" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func percentValue(_ percent: Double?) -> String {
        guard let percent else { return "-" }
        return String(format: "%.1f%%", percent)
    }

    /// A temperature in degrees Celsius, e.g. `45°C`.
    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "-" }
        return "\(Int(celsius.rounded()))°C"
    }

    static func uptime(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "-" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

/// Colour for a temperature relative to the sensor's own thresholds when reported,
/// else fixed homelab-sane bands (warm ≥ 70 °C, hot ≥ 85 °C).
func tempColor(_ reading: TemperatureReading) -> Color {
    let warn = reading.high ?? 70
    let crit = reading.critical ?? 85
    if reading.celsius >= crit { return .red }
    if reading.celsius >= warn { return .orange }
    return .primary
}

/// Color for a utilisation fraction (0–1): green → yellow → red.
func loadColor(_ fraction: Double?) -> Color {
    guard let fraction else { return .secondary }
    switch fraction {
    case ..<0.6: return .green
    case ..<0.85: return .yellow
    default: return .red
    }
}
