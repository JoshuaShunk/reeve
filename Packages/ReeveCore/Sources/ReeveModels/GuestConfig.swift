import Foundation

/// A guest's configuration from `GET …/{kind}/{vmid}/config`. The key set varies
/// widely (cores, memory, scsi0, net0, ostype, …) so it's decoded into a flat
/// `[String: String]` with typed accessors for the interesting parts.
public struct GuestConfig: Decodable, Sendable {
    public let values: [String: String]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var dict: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? container.decode(Int.self, forKey: key) {
                dict[key.stringValue] = String(value)
            } else if let value = try? container.decode(Double.self, forKey: key) {
                dict[key.stringValue] = String(format: "%g", value)
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                dict[key.stringValue] = value ? "1" : "0"
            }
        }
        values = dict
    }

    public var cores: String? { values["cores"] }
    public var sockets: String? { values["sockets"] }
    /// Configured memory in MB (Proxmox stores it as a number of megabytes).
    public var memoryMB: Int? { values["memory"].flatMap(Int.init) }
    public var osType: String? { values["ostype"] }
    public var configuredName: String? { values["name"] ?? values["hostname"] }
    /// Raw notes/description (Proxmox stores this as Markdown/HTML, render it).
    public var notes: String? {
        let raw = values["description"]
        return (raw?.isEmpty == false) ? raw : nil
    }
    public var startsOnBoot: Bool? {
        values["onboot"].map { $0 == "1" }
    }
    public var bootOrder: String? { values["boot"] }

    private static let diskPattern =
        "^(scsi|virtio|ide|sata|mp|unused|efidisk|tpmstate)[0-9]+$"

    /// Disk entries (`scsi0`, `virtio0`, `rootfs`, …), sorted by id.
    public var disks: [(id: String, value: String)] {
        values
            .filter { $0.key == "rootfs"
                || $0.key.range(of: Self.diskPattern, options: .regularExpression) != nil }
            .map { (id: $0.key, value: $0.value) }
            .sorted { $0.id < $1.id }
    }

    /// Network interface entries (`net0`, `net1`, …), sorted by id.
    public var networks: [(id: String, value: String)] {
        values
            .filter { $0.key.hasPrefix("net") && $0.key.dropFirst(3).allSatisfy(\.isNumber)
                && $0.key.count > 3 }
            .map { (id: $0.key, value: $0.value) }
            .sorted { $0.id < $1.id }
    }

    /// IPv4 addresses configured on network interfaces (containers; `ip=` field).
    public var configuredIPs: [String] {
        networks.compactMap { network in
            guard let ipField = network.value
                .split(separator: ",")
                .first(where: { $0.hasPrefix("ip=") })?
                .dropFirst(3) else { return nil }
            let address = ipField.split(separator: "/").first.map(String.init)
            return address == "dhcp" ? nil : address
        }
    }
}

/// Result of the QEMU guest agent `network-get-interfaces` command (best effort;
/// requires the agent to be installed and running in the VM).
public struct AgentNetworkInterfaces: Decodable, Sendable {
    public let result: [Interface]

    public struct Interface: Decodable, Sendable {
        public let name: String?
        public let ipAddresses: [Address]?
        private enum CodingKeys: String, CodingKey {
            case name
            case ipAddresses = "ip-addresses"
        }
    }

    public struct Address: Decodable, Sendable {
        public let ipAddress: String?
        public let type: String?
        private enum CodingKeys: String, CodingKey {
            case ipAddress = "ip-address"
            case type = "ip-address-type"
        }
    }

    /// Non-loopback IPv4 addresses reported by the agent.
    public var ipv4Addresses: [String] {
        result.flatMap { $0.ipAddresses ?? [] }
            .filter { $0.type == "ipv4" }
            .compactMap { $0.ipAddress }
            .filter { $0 != "127.0.0.1" }
    }
}
