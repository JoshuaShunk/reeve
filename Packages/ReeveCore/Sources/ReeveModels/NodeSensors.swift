import Foundation

/// One temperature channel reported by `lm-sensors` (e.g. a CPU package, a core,
/// an NVMe composite, or a SATA drive).
public struct TemperatureReading: Sendable, Hashable, Identifiable {
    /// Where the reading sits in the hardware, used for grouping and icons.
    public enum Category: Sendable {
        case cpu, drive, other
    }

    /// The lm-sensors chip the reading came from, e.g. `coretemp-isa-0000`.
    public let chip: String
    /// The feature label within the chip, e.g. `Package id 0`, `Core 0`, `Composite`, `Tctl`.
    public let label: String
    public let celsius: Double
    /// `*_max`, the manufacturer's high-but-acceptable threshold, when present.
    public let high: Double?
    /// `*_crit`, the critical threshold, when present.
    public let critical: Double?
    public let category: Category

    public var id: String { "\(chip)/\(label)" }

    public init(
        chip: String, label: String, celsius: Double,
        high: Double? = nil, critical: Double? = nil, category: Category
    ) {
        self.chip = chip
        self.label = label
        self.celsius = celsius
        self.high = high
        self.critical = critical
        self.category = category
    }
}

/// One fan speed channel (RPM) reported by `lm-sensors`.
public struct FanReading: Sendable, Hashable, Identifiable {
    public let chip: String
    public let label: String
    public let rpm: Double

    public var id: String { "\(chip)/\(label)" }

    public init(chip: String, label: String, rpm: Double) {
        self.chip = chip
        self.label = label
        self.rpm = rpm
    }
}

/// A node's hardware sensor readings, parsed from `sensors -j` (run over SSH;
/// Proxmox doesn't expose temperatures through its REST API). Empty when the node
/// has no `lm-sensors` configured.
public struct NodeSensors: Sendable, Hashable {
    public let temperatures: [TemperatureReading]
    public let fans: [FanReading]

    public init(temperatures: [TemperatureReading], fans: [FanReading]) {
        self.temperatures = temperatures
        self.fans = fans
    }

    public var isEmpty: Bool { temperatures.isEmpty && fans.isEmpty }

    public var cpuTemperatures: [TemperatureReading] {
        temperatures.filter { $0.category == .cpu }
    }

    public var driveTemperatures: [TemperatureReading] {
        temperatures.filter { $0.category == .drive }
    }

    public var otherTemperatures: [TemperatureReading] {
        temperatures.filter { $0.category == .other }
    }

    /// The most representative CPU temperature for an at-a-glance indicator:
    /// prefer a package/Tctl reading, otherwise the hottest CPU core.
    public var primaryCPU: TemperatureReading? {
        let cpu = cpuTemperatures
        let preferred = cpu.first {
            let l = $0.label.lowercased()
            return l.contains("package") || l == "tctl" || l == "tdie"
        }
        return preferred ?? cpu.max { $0.celsius < $1.celsius }
    }

    /// The single hottest temperature across every channel, used for alerting.
    public var hottest: TemperatureReading? {
        temperatures.max { $0.celsius < $1.celsius }
    }
}

extension NodeSensors {
    /// Parse the JSON emitted by `sensors -j`. Returns `nil` if the text isn't the
    /// expected object (e.g. `sensors` isn't installed, or emitted an error).
    ///
    /// The format is `{ chip: { "Adapter": String, feature: { subfeature: Double } } }`.
    /// Each feature exposes a `*_input` subfeature; we classify it as a temperature
    /// or a fan by the subfeature name and pair temperatures with their `*_max` /
    /// `*_crit` companions.
    public static func parse(sensorsJSON text: String) -> NodeSensors? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{") else { return nil }
        let jsonText = String(trimmed[start...])
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var temperatures: [TemperatureReading] = []
        var fans: [FanReading] = []

        for chip in root.keys.sorted() {
            guard let features = root[chip] as? [String: Any] else { continue }
            let category = Self.category(forChip: chip)

            for feature in features.keys.sorted() {
                guard let sub = features[feature] as? [String: Any] else { continue }  // skips "Adapter": String

                // Temperature: a *_input that names a temperature channel.
                if let (prefix, value) = Self.inputValue(in: sub, matching: "temp") {
                    temperatures.append(TemperatureReading(
                        chip: chip, label: feature, celsius: value,
                        high: sub["\(prefix)_max"] as? Double,
                        critical: sub["\(prefix)_crit"] as? Double,
                        category: category
                    ))
                }
                // Fan: a *_input naming a fan channel (ignore the common 0-RPM headers).
                if let (_, rpm) = Self.inputValue(in: sub, matching: "fan"), rpm > 0 {
                    fans.append(FanReading(chip: chip, label: feature, rpm: rpm))
                }
            }
        }

        guard !temperatures.isEmpty || !fans.isEmpty else { return nil }
        return NodeSensors(temperatures: temperatures, fans: fans)
    }

    /// Find a `<prefix>N_input` subfeature whose prefix contains `kind`, returning
    /// the prefix (e.g. `temp1`) and its value.
    private static func inputValue(
        in feature: [String: Any], matching kind: String
    ) -> (prefix: String, value: Double)? {
        for key in feature.keys.sorted() where key.hasSuffix("_input") && key.contains(kind) {
            if let value = feature[key] as? Double {
                return (String(key.dropLast("_input".count)), value)
            }
        }
        return nil
    }

    private static func category(forChip chip: String) -> TemperatureReading.Category {
        let name = chip.lowercased()
        let cpuPrefixes = ["coretemp", "k10temp", "k8temp", "zenpower", "cpu_thermal", "cpu-thermal"]
        if cpuPrefixes.contains(where: name.hasPrefix) { return .cpu }
        if name.hasPrefix("nvme") || name.hasPrefix("drivetemp") { return .drive }
        return .other
    }
}
