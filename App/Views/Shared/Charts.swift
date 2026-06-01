import Charts
import ReeveModels
import SwiftUI

/// A titled card wrapper for a chart. Height scales with Dynamic Type so the chart
/// stays usable at large text sizes (Larger Text criterion).
private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content.frame(height: height)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CPUChart: View {
    let points: [RRDPoint]
    var body: some View {
        let pts = points.filter { $0.cpu != nil }
        ChartCard(title: "CPU") {
            Chart(pts) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("CPU %", point.cpuPercent ?? 0)
                )
                .foregroundStyle(.blue.opacity(0.2))
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("CPU %", point.cpuPercent ?? 0)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .accessibilityChartDescriptor(TimeSeriesChartDescriptor(
                title: "CPU usage", yLabel: "percent",
                series: [AXSeries(name: "CPU", points: pts.map { ($0.date, $0.cpuPercent ?? 0) })]
            ))
        }
    }
}

struct MemoryChart: View {
    let points: [RRDPoint]
    var body: some View {
        let pts = points.filter { $0.memoryUsedBytes != nil }
        ChartCard(title: "Memory") {
            Chart(pts) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", (point.memoryUsedBytes ?? 0) / 1_073_741_824)  // GiB
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.catmullRom)
            }
            .chartYAxisLabel("GiB")
            .accessibilityChartDescriptor(TimeSeriesChartDescriptor(
                title: "Memory used", yLabel: "GiB",
                series: [AXSeries(name: "Memory", points: pts.map { ($0.date, ($0.memoryUsedBytes ?? 0) / 1_073_741_824) })]
            ))
        }
    }
}

struct DiskIOChart: View {
    let points: [RRDPoint]
    var body: some View {
        let reads = points.filter { $0.diskread != nil }
        let writes = points.filter { $0.diskwrite != nil }
        ChartCard(title: "Disk I/O") {
            Chart {
                ForEach(reads) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.diskread ?? 0) / 1_048_576),
                        series: .value("Dir", "Read")
                    )
                    .foregroundStyle(.cyan)
                }
                ForEach(writes) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.diskwrite ?? 0) / 1_048_576),
                        series: .value("Dir", "Write")
                    )
                    .foregroundStyle(.pink)
                    // Dashed so Read vs Write is distinguishable without relying on
                    // color (Differentiate Without Color Alone).
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            .chartYAxisLabel("MiB/s")
            .chartForegroundStyleScale(["Read": .cyan, "Write": .pink])
            .accessibilityChartDescriptor(TimeSeriesChartDescriptor(
                title: "Disk I/O", yLabel: "MiB per second",
                series: [
                    AXSeries(name: "Read", points: reads.map { ($0.date, ($0.diskread ?? 0) / 1_048_576) }),
                    AXSeries(name: "Write", points: writes.map { ($0.date, ($0.diskwrite ?? 0) / 1_048_576) }),
                ]
            ))
        }
    }
}

struct NetworkChart: View {
    let points: [RRDPoint]
    var body: some View {
        let ins = points.filter { $0.netin != nil }
        let outs = points.filter { $0.netout != nil }
        ChartCard(title: "Network") {
            Chart {
                ForEach(ins) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.netin ?? 0) / 1_048_576),  // MiB/s
                        series: .value("Dir", "In")
                    )
                    .foregroundStyle(.green)
                }
                ForEach(outs) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.netout ?? 0) / 1_048_576),
                        series: .value("Dir", "Out")
                    )
                    .foregroundStyle(.orange)
                    // Dashed so In vs Out is distinguishable without relying on color.
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            .chartYAxisLabel("MiB/s")
            .chartForegroundStyleScale(["In": .green, "Out": .orange])
            .accessibilityChartDescriptor(TimeSeriesChartDescriptor(
                title: "Network throughput", yLabel: "MiB per second",
                series: [
                    AXSeries(name: "In", points: ins.map { ($0.date, ($0.netin ?? 0) / 1_048_576) }),
                    AXSeries(name: "Out", points: outs.map { ($0.date, ($0.netout ?? 0) / 1_048_576) }),
                ]
            ))
        }
    }
}
