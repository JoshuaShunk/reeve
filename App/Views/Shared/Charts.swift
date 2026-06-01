import Charts
import ReeveModels
import SwiftUI

/// A titled card wrapper for a chart.
private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content.frame(height: 160)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CPUChart: View {
    let points: [RRDPoint]
    var body: some View {
        ChartCard(title: "CPU") {
            Chart(points.filter { $0.cpu != nil }) { point in
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
        }
    }
}

struct MemoryChart: View {
    let points: [RRDPoint]
    var body: some View {
        ChartCard(title: "Memory") {
            Chart(points.filter { $0.memoryUsedBytes != nil }) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", (point.memoryUsedBytes ?? 0) / 1_073_741_824)  // GiB
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.catmullRom)
            }
            .chartYAxisLabel("GiB")
        }
    }
}

struct DiskIOChart: View {
    let points: [RRDPoint]
    var body: some View {
        ChartCard(title: "Disk I/O") {
            Chart {
                ForEach(points.filter { $0.diskread != nil }) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.diskread ?? 0) / 1_048_576),
                        series: .value("Dir", "Read")
                    )
                    .foregroundStyle(.cyan)
                }
                ForEach(points.filter { $0.diskwrite != nil }) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.diskwrite ?? 0) / 1_048_576),
                        series: .value("Dir", "Write")
                    )
                    .foregroundStyle(.pink)
                }
            }
            .chartYAxisLabel("MiB/s")
            .chartForegroundStyleScale(["Read": .cyan, "Write": .pink])
        }
    }
}

struct NetworkChart: View {
    let points: [RRDPoint]
    var body: some View {
        ChartCard(title: "Network") {
            Chart {
                ForEach(points.filter { $0.netin != nil }) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.netin ?? 0) / 1_048_576),  // MiB/s
                        series: .value("Dir", "In")
                    )
                    .foregroundStyle(.green)
                }
                ForEach(points.filter { $0.netout != nil }) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Rate", (point.netout ?? 0) / 1_048_576),
                        series: .value("Dir", "Out")
                    )
                    .foregroundStyle(.orange)
                }
            }
            .chartYAxisLabel("MiB/s")
            .chartForegroundStyleScale(["In": .green, "Out": .orange])
        }
    }
}
