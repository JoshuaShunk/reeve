import Foundation
import ReeveModels

#if canImport(Network)
import Network
#endif

#if canImport(Darwin)
import Darwin
#endif

public enum ScanError: Error, Sendable, LocalizedError {
    case noLocalIPv4
    case localNetworkDenied
    case invalidSubnet

    public var errorDescription: String? {
        switch self {
        case .noLocalIPv4:
            "Couldn't determine your Wi-Fi network. Connect to Wi-Fi and try again."
        case .localNetworkDenied:
            "Local network access is off. Enable it for this app in Settings to scan."
        case .invalidSubnet:
            "That doesn't look like a valid network. Try something like 10.0.0.0/24."
        }
    }
}

/// Discovers Proxmox servers on the local network by probing the device's own
/// IPv4 /24 subnet for the API port (8006) and then confirming each responder is
/// genuinely Proxmox before surfacing it. Stock Proxmox doesn't advertise over
/// Bonjour/mDNS (it needs a manual Avahi service file), so a bounded, targeted TCP
/// probe is the only general approach, and validating the result keeps discovery
/// single-purpose (only the user's Proxmox servers, not a LAN device directory),
/// which is both correct and what App Store review expects (Guideline 5.1.2).
///
/// All work is `nonisolated`; call `scan` from a `Task` and observe `progress`.
public struct LANScanner: Sendable {
    public init() {}

    /// Probe every host on a /24 for `port`. With `cidr == nil`, scans the device's
    /// own local subnet(s); pass a CIDR like `"10.0.0.0/24"` to scan a specific
    /// network, useful when the target is reachable over a VPN rather than on the
    /// local Wi-Fi. Streams progress as `(probed, total)`. Throws `ScanError` if
    /// there's no usable network, the subnet is invalid, or access is denied.
    public func scan(
        cidr: String? = nil,
        port: Int = 8006,
        timeout: Duration = .seconds(1),
        maxConcurrent: Int = 32,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DiscoveredServer] {
        let hosts: [String]
        if let cidr, !cidr.isEmpty {
            hosts = IPv4Subnet.hosts(cidr: cidr)
            guard !hosts.isEmpty else { throw ScanError.invalidSubnet }
        } else {
            hosts = localScanHosts()
            guard !hosts.isEmpty else { throw ScanError.noLocalIPv4 }
        }

        // Pre-flight the Local Network permission with a single connection, waiting
        // for the user to answer the system prompt. Without this, launching the
        // whole scan at once races the prompt: every probe times out as "closed"
        // before the user taps Allow, yielding a spurious "no servers found".
        if let sample = hosts.first {
            let outcome = await PortProbe(host: sample, port: UInt16(port), connectTimeout: 20)
                .run(timeout: .seconds(20))
            if outcome == .denied { throw ScanError.localNetworkDenied }
        }

        var openHosts: [String] = []
        var denied = false
        var probed = 0
        let total = hosts.count
        let port16 = UInt16(port)

        try await withThrowingTaskGroup(of: (String, PortProbe.Outcome).self) { group in
            var next = 0
            func addNext() {
                guard next < hosts.count else { return }
                let host = hosts[next]
                next += 1
                group.addTask {
                    (host, await PortProbe(host: host, port: port16).run(timeout: timeout))
                }
            }

            for _ in 0..<min(maxConcurrent, hosts.count) { addNext() }

            while let (host, outcome) = try await group.next() {
                probed += 1
                progress?(probed, total)
                switch outcome {
                case .open:
                    openHosts.append(host)
                case .denied:
                    denied = true
                    group.cancelAll()
                case .closed, .timedOut:
                    break
                }
                addNext()
            }
        }

        if denied && openHosts.isEmpty { throw ScanError.localNetworkDenied }

        // Confirm each open :8006 actually speaks Proxmox before surfacing it. This
        // keeps discovery single-purpose, we only ever present the user's Proxmox
        // servers, never a directory of unrelated third-party devices on the LAN
        // (the pattern App Store review flags under Guideline 5.1.2).
        let servers = await withTaskGroup(of: DiscoveredServer?.self) { group in
            for host in openHosts {
                group.addTask {
                    guard await Self.looksLikeProxmox(host: host, port: port) else { return nil }
                    return DiscoveredServer(
                        ipAddress: host, port: port, hostname: Self.reverseDNS(host)
                    )
                }
            }
            var found: [DiscoveredServer] = []
            for await server in group where server != nil { found.append(server!) }
            return found
        }

        return servers.sorted { $0.ipAddress.compare($1.ipAddress, options: .numeric) == .orderedAscending }
    }

    /// A fingerprint check that a host is a Proxmox VE node: its API port is served
    /// by `pveproxy`, which tags responses with `Server: pve-api-daemon` and serves
    /// a page mentioning Proxmox. Accepts the node's self-signed certificate (the
    /// user explicitly confirms and pins trust later when adding the server).
    static func looksLikeProxmox(host: String, port: Int, timeout: TimeInterval = 3) async -> Bool {
        guard let url = URL(string: "https://\(host):\(port)/") else { return false }
        let delegate = ProxmoxTrustDelegate()
        delegate.setPolicy(.allowInsecure, forHost: host)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let (data, response) = try? await session.data(for: URLRequest(url: url)),
              let http = response as? HTTPURLResponse else { return false }
        if let server = http.value(forHTTPHeaderField: "Server"),
           server.lowercased().contains("pve-api-daemon") {
            return true
        }
        if let body = String(data: data, encoding: .utf8), body.contains("Proxmox") {
            return true
        }
        return false
    }

    /// The /24 subnets the device is directly attached to, derived from its own
    /// interface addresses, all the routing information iOS actually exposes.
    /// Useful as one-tap scan suggestions. Excludes the 100.64.0.0/10 CGNAT range
    /// (Tailscale's own address / carrier NAT), which is never a useful scan target.
    /// Note: subnets reached *over* a split-tunnel VPN cannot appear here, iOS
    /// doesn't expose the routing table, so those still require manual entry.
    public func candidateSubnets() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for iface in Self.localIPv4Interfaces() {
            guard let addr = IPv4Subnet.value(iface.address) else { continue }
            if (addr & 0xFFC0_0000) == 0x6440_0000 { continue }  // skip 100.64.0.0/10
            guard let cidr = IPv4Subnet.networkCIDR24(address: iface.address) else { continue }
            if seen.insert(cidr).inserted { result.append(cidr) }
        }
        return result
    }

    // MARK: - Local interfaces

    /// Host addresses to probe across all active IPv4 interfaces (capped per /24).
    func localScanHosts() -> [String] {
        var hosts: Set<String> = []
        for iface in Self.localIPv4Interfaces() {
            hosts.formUnion(IPv4Subnet.scanHosts(address: iface.address, netmask: iface.netmask))
        }
        return Array(hosts)
    }

    struct Interface: Sendable { let address: String; let netmask: String }

    static func localIPv4Interfaces() -> [Interface] {
        #if canImport(Darwin)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [Interface] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET),
                  let maskPtr = ptr.pointee.ifa_netmask,
                  let address = sockaddrIPv4String(addr),
                  let netmask = sockaddrIPv4String(maskPtr),
                  !address.hasPrefix("169.254.")  // skip link-local
            else { continue }
            result.append(Interface(address: address, netmask: netmask))
        }
        return result
        #else
        return []
        #endif
    }

    #if canImport(Darwin)
    private static func sockaddrIPv4String(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            sa, socklen_t(MemoryLayout<sockaddr_in>.size),
            &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
        )
        return result == 0 ? String(cString: host) : nil
    }
    #endif

    /// Best-effort reverse DNS for a discovered host (used as a suggested name).
    static func reverseDNS(_ ip: String) -> String? {
        #if canImport(Darwin)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(
                    sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                    &host, socklen_t(host.count), nil, 0, NI_NAMEREQD
                )
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: host)
        return name.isEmpty ? nil : name
        #else
        return nil
        #endif
    }
}

/// Pure IPv4 subnet math, separated out so it's unit-testable without networking.
public enum IPv4Subnet {
    public static func value(_ dotted: String) -> UInt32? {
        let parts = dotted.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            result = (result << 8) | octet
        }
        return result
    }

    public static func string(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    public static func prefixLength(netmask: String) -> Int? {
        guard let mask = value(netmask) else { return nil }
        return mask.nonzeroBitCount
    }

    /// Probeable host addresses for the subnet containing `address`. Capped to a
    /// /24 (≤254 hosts) so wide masks like /16 don't trigger huge scans. When
    /// `excludeSelf` is true the `address` itself is skipped (it's the device's
    /// own IP); for an explicitly chosen subnet pass `false` so every host is probed.
    public static func scanHosts(
        address: String, netmask: String, excludeSelf: Bool = true
    ) -> [String] {
        guard let addr = value(address), let prefix = prefixLength(netmask: netmask) else {
            return []
        }
        let effectivePrefix = max(prefix, 24)
        guard effectivePrefix < 31 else { return [] }
        let mask: UInt32 = effectivePrefix == 0 ? 0 : ~UInt32(0) << (32 - effectivePrefix)
        let network = addr & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return (network + 1..<broadcast).compactMap { host in
            (excludeSelf && host == addr) ? nil : string(host)
        }
    }

    /// Parse a CIDR string (`"10.0.0.0/24"`, or a bare `"10.0.0.5"` assumed /24)
    /// into the list of probe hosts, capped to a /24. Every host is included.
    public static func hosts(cidr: String) -> [String] {
        let trimmed = cidr.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/", maxSplits: 1)
        guard let addr = parts.first.map(String.init), value(addr) != nil else { return [] }
        let prefix = parts.count > 1 ? (Int(parts[1]) ?? 24) : 24
        guard (0...32).contains(prefix) else { return [] }
        let netmask = string(prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix))
        return scanHosts(address: addr, netmask: netmask, excludeSelf: false)
    }

    /// The `x.y.z.0/24` network string containing `address`.
    public static func networkCIDR24(address: String) -> String? {
        guard let addr = value(address) else { return nil }
        return "\(string(addr & 0xFFFF_FF00))/24"
    }

    /// First usable host of the (capped /24) subnet, a good sample address for a
    /// one-shot permission pre-flight (typically the gateway).
    public static func firstHost(address: String, netmask: String) -> String? {
        guard let addr = value(address), let prefix = prefixLength(netmask: netmask) else {
            return nil
        }
        let effectivePrefix = max(prefix, 24)
        guard effectivePrefix < 31 else { return nil }
        let mask: UInt32 = effectivePrefix == 0 ? 0 : ~UInt32(0) << (32 - effectivePrefix)
        return string((addr & mask) + 1)
    }
}

#if canImport(Network)
/// A single-shot "is this TCP port open?" probe. `NWConnection` is not `Sendable`,
/// so it's confined inside this `@unchecked Sendable` box, which guarantees the
/// continuation resumes exactly once (state handler + timeout can both fire).
private final class PortProbe: @unchecked Sendable {
    enum Outcome: Sendable, Equatable { case open, closed, denied, timedOut }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<Outcome, Never>?

    init(host: String, port: UInt16, connectTimeout: Int = 2) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = connectTimeout  // handshake bound; run() bounds stalls
        let params = NWParameters(tls: nil, tcp: tcp)
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params
        )
        queue = DispatchQueue(label: "homelab.portprobe")
    }

    func run(timeout: Duration) async -> Outcome {
        await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
            continuation = cont
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    finish(.open)
                case .failed:
                    finish(.closed)
                case .waiting:
                    // Denial stalls in .waiting forever; detect and bail out.
                    if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        finish(.denied)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            let seconds = Double(timeout.components.seconds)
                + Double(timeout.components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.finish(.timedOut)
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        connection.cancel()
        cont?.resume(returning: outcome)
    }
}
#else
private struct PortProbe {
    enum Outcome: Sendable, Equatable { case open, closed, denied, timedOut }
    init(host: String, port: UInt16, connectTimeout: Int = 2) {}
    func run(timeout: Duration) async -> Outcome { .timedOut }
}
#endif
