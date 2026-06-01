import SwiftUI

/// A labelled horizontal utilisation bar (0–1) with a trailing detail string.
struct MetricBar: View {
    /// Static, translatable metric name (e.g. "CPU"). Pass "" for a bare bar.
    let label: LocalizedStringKey
    let fraction: Double?
    /// Formatted, locale-aware data (e.g. "5.2 GB / 8 GB"), not a translation key.
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(loadColor(fraction))
                        .frame(width: geo.size.width * CGFloat(min(max(fraction ?? 0, 0), 1)))
                }
            }
            .frame(height: 6)
        }
        // Read the whole bar as one VoiceOver element with a spoken percentage.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(
            fraction.map { "\(Int((min(max($0, 0), 1) * 100).rounded())) percent, \(detail)" } ?? detail
        )
    }
}
