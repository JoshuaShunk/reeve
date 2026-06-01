import Foundation
import Testing

@testable import ReeveModels

/// Parsing tests for `sensors -j` output across Intel, AMD, NVMe, SATA and
/// super-IO fan chips.
@Suite("Node sensors parsing")
struct NodeSensorsTests {
    @Test func parsesIntelCoresPackageAndThresholds() throws {
        let sensors = try #require(NodeSensors.parse(sensorsJSON: #"""
        {
          "coretemp-isa-0000": {
            "Adapter": "ISA adapter",
            "Package id 0": { "temp1_input": 45.000, "temp1_max": 80.000, "temp1_crit": 100.000 },
            "Core 0": { "temp2_input": 43.000, "temp2_max": 80.000, "temp2_crit": 100.000 },
            "Core 1": { "temp3_input": 49.000 }
          }
        }
        """#))

        #expect(sensors.cpuTemperatures.count == 3)
        let package = try #require(sensors.primaryCPU)
        #expect(package.label == "Package id 0")
        #expect(package.celsius == 45)
        #expect(package.high == 80)
        #expect(package.critical == 100)
        // Hottest channel is Core 1 at 49°C.
        #expect(sensors.hottest?.celsius == 49)
    }

    @Test func parsesAmdTctlAsCPU() throws {
        let sensors = try #require(NodeSensors.parse(sensorsJSON: #"""
        {
          "k10temp-pci-00c3": {
            "Adapter": "PCI adapter",
            "Tctl": { "temp1_input": 50.250 },
            "Tccd1": { "temp3_input": 47.000 }
          }
        }
        """#))
        #expect(sensors.cpuTemperatures.count == 2)
        #expect(sensors.primaryCPU?.label == "Tctl")
        #expect(sensors.primaryCPU?.celsius == 50.25)
    }

    @Test func classifiesDrivesAndParsesFans() throws {
        let sensors = try #require(NodeSensors.parse(sensorsJSON: #"""
        {
          "nvme-pci-0100": {
            "Adapter": "PCI adapter",
            "Composite": { "temp1_input": 38.850, "temp1_crit": 84.850 }
          },
          "drivetemp-scsi-0-0": {
            "Adapter": "SCSI adapter",
            "temp1": { "temp1_input": 34.000 }
          },
          "nct6798-isa-0290": {
            "Adapter": "ISA adapter",
            "fan1": { "fan1_input": 0.000 },
            "fan2": { "fan2_input": 879.000 }
          }
        }
        """#))

        #expect(sensors.driveTemperatures.count == 2)
        #expect(sensors.driveTemperatures.contains { $0.label == "Composite" && $0.celsius == 38.85 })
        // 0-RPM fan headers are dropped; only the spinning fan remains.
        #expect(sensors.fans.count == 1)
        #expect(sensors.fans.first?.rpm == 879)
    }

    @Test func ignoresNonTemperatureChannels() throws {
        // Voltage / power channels (in*, power*) must not be read as temperatures.
        let sensors = try #require(NodeSensors.parse(sensorsJSON: #"""
        {
          "nct6798-isa-0290": {
            "in0": { "in0_input": 1.080 },
            "fan1": { "fan1_input": 1200.0 }
          },
          "coretemp-isa-0000": { "Core 0": { "temp1_input": 40.0 } }
        }
        """#))
        #expect(sensors.temperatures.count == 1)
        #expect(sensors.temperatures.first?.celsius == 40)
        #expect(sensors.fans.count == 1)
    }

    @Test func returnsNilForUnusableOutput() {
        #expect(NodeSensors.parse(sensorsJSON: "") == nil)
        #expect(NodeSensors.parse(sensorsJSON: "command not found") == nil)
        #expect(NodeSensors.parse(sensorsJSON: "{}") == nil)
    }

    @Test func toleratesLeadingNoiseBeforeJSON() throws {
        // sensors sometimes prints a warning line before the JSON body.
        let sensors = try #require(NodeSensors.parse(sensorsJSON: """
        sensors: warning
        { "coretemp-isa-0000": { "Core 0": { "temp1_input": 41.0 } } }
        """))
        #expect(sensors.primaryCPU?.celsius == 41)
    }
}
