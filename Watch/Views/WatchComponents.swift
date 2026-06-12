import SwiftUI
import ReeveModels

extension Health {
    var tint: Color {
        switch self {
        case .ok: .green
        case .warn: .yellow
        case .down: .red
        case .unknown: .gray
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .down: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

/// A small filled status dot.
struct HealthDot: View {
    let health: Health
    var body: some View {
        Circle()
            .fill(health.tint)
            .frame(width: 10, height: 10)
            .accessibilityLabel(Text(healthLabel))
    }

    private var healthLabel: String {
        switch health {
        case .ok: "Healthy"
        case .warn: "Warning"
        case .down: "Down"
        case .unknown: "Unknown"
        }
    }
}

/// A compact circular gauge for a 0...1 metric, sized for the wrist.
struct MetricGauge: View {
    let title: String
    let fraction: Double?
    var tint: Color = .accentColor

    var body: some View {
        Gauge(value: fraction ?? 0) {
            Text(title)
        } currentValueLabel: {
            Text(percentText)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeTint)
    }

    private var percentText: String {
        guard let fraction else { return "--" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    private var gaugeTint: Color {
        guard let fraction else { return .gray }
        switch fraction {
        case ..<0.75: return tint
        case ..<0.9: return .yellow
        default: return .red
        }
    }
}

/// Bytes formatted compactly (e.g. "3.2 GB"). Int64 because Proxmox byte counts
/// exceed 32-bit Int on watchOS (arm64_32).
func formatBytes(_ bytes: Int64?) -> String {
    guard let bytes else { return "--" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
}

/// Seconds of uptime as a short "3d 4h" style string.
func formatUptime(_ seconds: Int?) -> String {
    guard let seconds, seconds > 0 else { return "--" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}
