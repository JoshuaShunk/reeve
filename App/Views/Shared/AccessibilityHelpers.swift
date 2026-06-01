import Accessibility
import SwiftUI

// Shared accessibility helpers used to meet Apple's Accessibility Nutrition Label
// criteria: status conveyed by shape + text (not color alone), VoiceOver labels,
// and audio-graph descriptors for the time-series charts.

/// A status indicator that conveys state with an SF Symbol shape AND color, never
/// color alone, and announces a spoken label to VoiceOver / Voice Control.
/// Satisfies "Differentiate Without Color Alone" and gives assistive tech a label.
struct StatusGlyph: View {
    enum Level { case ok, warn, down, neutral }
    let level: Level
    /// Spoken description, e.g. "Running", "11 of 12 monitors up", "Offline".
    let label: String
    var size: CGFloat = 11

    private var symbol: String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .down: "xmark.octagon.fill"
        case .neutral: "circle.fill"
        }
    }
    private var color: Color {
        switch level {
        case .ok: .green
        case .warn: .yellow
        case .down: .red
        case .neutral: .secondary
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    /// Convenience for a simple up/down boolean.
    init(isUp: Bool, label: String, size: CGFloat = 11) {
        self.level = isUp ? .ok : .down
        self.label = label
        self.size = size
    }

    init(level: Level, label: String, size: CGFloat = 11) {
        self.level = level
        self.label = label
        self.size = size
    }
}

// MARK: - Chart audio-graph descriptor

/// One named series of (date, value) samples for a time-series chart.
struct AXSeries {
    let name: String
    let points: [(date: Date, value: Double)]
}

/// Generic `AXChartDescriptor` for the app's time-series charts, enabling
/// VoiceOver's "Describe Chart", "Chart Details", and audio-graph (pitch) output.
struct TimeSeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let yLabel: String
    let series: [AXSeries]

    func makeChartDescriptor() -> AXChartDescriptor {
        let allPoints = series.flatMap(\.points)
        let xs = allPoints.map(\.date.timeIntervalSince1970)
        let ys = allPoints.map(\.value)
        let xRange = (xs.min() ?? 0)...(xs.max() ?? 1)
        let yRange = (ys.min() ?? 0)...(ys.max() ?? 1)

        let timeFormatter = DateComponentsFormatter()
        timeFormatter.allowedUnits = [.hour, .minute]
        timeFormatter.unitsStyle = .abbreviated

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: xRange,
            gridlinePositions: []
        ) { value in
            let date = Date(timeIntervalSince1970: value)
            return date.formatted(date: .omitted, time: .shortened)
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: yLabel,
            range: yRange,
            gridlinePositions: []
        ) { value in String(format: "%.1f \(yLabel)", value) }

        let dataSeries = series.map { s in
            AXDataSeriesDescriptor(
                name: s.name,
                isContinuous: true,
                dataPoints: s.points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value) }
            )
        }

        return AXChartDescriptor(
            title: title,
            summary: series.count > 1
                ? "\(title) over time, \(series.count) series: \(series.map(\.name).joined(separator: ", "))."
                : "\(title) over time.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: dataSeries
        )
    }
}
