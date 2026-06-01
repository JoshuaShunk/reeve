import Testing

@testable import ReeveNetworking

@Suite("IPv4 subnet math")
struct IPv4SubnetTests {
    @Test("Parses and reconstructs dotted addresses")
    func roundTrip() {
        #expect(IPv4Subnet.value("10.0.0.150") == 0x0A_00_00_96)
        #expect(IPv4Subnet.string(0x0A_00_00_96) == "10.0.0.150")
        #expect(IPv4Subnet.value("256.0.0.1") == nil)
        #expect(IPv4Subnet.value("10.0.0") == nil)
    }

    @Test("Derives prefix length from a netmask")
    func prefix() {
        #expect(IPv4Subnet.prefixLength(netmask: "255.255.255.0") == 24)
        #expect(IPv4Subnet.prefixLength(netmask: "255.255.0.0") == 16)
        #expect(IPv4Subnet.prefixLength(netmask: "255.255.255.252") == 30)
    }

    @Test("A /24 yields 253 probe hosts, excluding network, broadcast, and self")
    func slash24() {
        let hosts = IPv4Subnet.scanHosts(address: "10.0.0.150", netmask: "255.255.255.0")
        #expect(hosts.count == 253)  // 254 usable minus our own .150
        #expect(hosts.contains("10.0.0.1"))
        #expect(hosts.contains("10.0.0.254"))
        #expect(!hosts.contains("10.0.0.0"))    // network
        #expect(!hosts.contains("10.0.0.255"))  // broadcast
        #expect(!hosts.contains("10.0.0.150"))  // self
    }

    @Test("A wide mask is capped to the local /24 to avoid huge scans")
    func wideMaskCapped() {
        let hosts = IPv4Subnet.scanHosts(address: "10.0.5.42", netmask: "255.255.0.0")
        #expect(hosts.count == 253)
        // Stays within the /24 containing the address (10.0.5.x), not the whole /16.
        #expect(hosts.allSatisfy { $0.hasPrefix("10.0.5.") })
    }

    @Test("Parses CIDR strings and includes every host (no self exclusion)")
    func cidr() {
        let hosts = IPv4Subnet.hosts(cidr: "10.0.0.0/24")
        #expect(hosts.count == 254)
        #expect(hosts.contains("10.0.0.150"))  // target not excluded
        #expect(hosts.first == "10.0.0.1")
        #expect(hosts.last == "10.0.0.254")
        // A bare address is treated as /24.
        #expect(IPv4Subnet.hosts(cidr: "10.0.0.150").count == 254)
        // Wide masks are still capped to a /24.
        #expect(IPv4Subnet.hosts(cidr: "192.168.5.20/16").allSatisfy { $0.hasPrefix("192.168.5.") })
        #expect(IPv4Subnet.hosts(cidr: "not-an-ip").isEmpty)
    }

    @Test("Derives the /24 network string for an address")
    func networkCIDR24() {
        #expect(IPv4Subnet.networkCIDR24(address: "10.0.0.150") == "10.0.0.0/24")
        #expect(IPv4Subnet.networkCIDR24(address: "192.168.1.73") == "192.168.1.0/24")
        #expect(IPv4Subnet.networkCIDR24(address: "nope") == nil)
    }

    @Test("A /30 yields just the sibling host; /31 and /32 yield none")
    func tinySubnets() {
        #expect(IPv4Subnet.scanHosts(address: "10.0.0.1", netmask: "255.255.255.252") == ["10.0.0.2"])
        #expect(IPv4Subnet.scanHosts(address: "10.0.0.1", netmask: "255.255.255.254").isEmpty)
        #expect(IPv4Subnet.scanHosts(address: "10.0.0.1", netmask: "255.255.255.255").isEmpty)
    }
}
