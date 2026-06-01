import Foundation

/// Response from `POST /nodes/{node}/{qemu|lxc}/{vmid}/vncproxy`.
///
/// Proxmox opens a short-lived VNC proxy listening on `port` on the node and
/// returns a one-time `ticket` that doubles as the VNC password during the RFB
/// handshake. The proxy only listens for a few seconds, so connect promptly.
public struct VNCProxyTicket: Decodable, Sendable {
    public let ticket: String
    /// Proxmox returns the port as a string; use `portNumber`.
    public let port: String
    public let user: String?
    public let upid: String?

    public var portNumber: Int? { Int(port) }

    public init(ticket: String, port: String, user: String? = nil, upid: String? = nil) {
        self.ticket = ticket
        self.port = port
        self.user = user
        self.upid = upid
    }
}
