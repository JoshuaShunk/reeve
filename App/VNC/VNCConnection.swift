#if os(iOS)
import CoreGraphics
import Foundation
import ReeveModels
import Network
import Observation

/// A graphical (RFB/VNC) console session to a Proxmox QEMU guest.
///
/// Connects raw TCP to the node's `vncproxy` port and speaks RFB 3.8 (RFC 6143)
/// using the one-time proxy ticket as the VNC password, token-only, no separate
/// login. Decoding/auth/framebuffer live in `ReeveModels` (unit-tested); this
/// type owns the live socket and publishes frames to SwiftUI.
@MainActor
@Observable
final class VNCConnection {
    enum Phase: Equatable {
        case connecting, authenticating, connected
        case failed(String)
        case closed
    }

    private(set) var phase: Phase = .connecting
    private(set) var image: CGImage?
    private(set) var displaySize: CGSize = .zero

    private let client: RFBClient

    init(host: String, port: Int, password: String) {
        client = RFBClient(host: host, port: UInt16(port), password: password)
    }

    func start() {
        client.onPhase = { [weak self] phase in
            Task { @MainActor in self?.phase = phase }
        }
        client.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.image = frame.image
                self?.displaySize = frame.size
            }
        }
        client.start()
    }

    func stop() { client.stop() }

    /// Send a pointer event. `point` is in framebuffer pixel coordinates.
    func sendPointer(buttonMask: UInt8, at point: CGPoint) {
        client.sendPointer(buttonMask: buttonMask,
                           x: UInt16(clamping: Int(point.x)),
                           y: UInt16(clamping: Int(point.y)))
    }

    /// Press-and-release an X11 keysym, optionally with Control held (for chords
    /// like Ctrl-C). Control_L is keysym 0xFFE3.
    func tapKey(_ keysym: UInt32, ctrl: Bool = false) {
        if ctrl { client.sendKey(down: true, key: 0xFFE3) }
        client.sendKey(down: true, key: keysym)
        client.sendKey(down: false, key: keysym)
        if ctrl { client.sendKey(down: false, key: 0xFFE3) }
    }
}

/// An immutable frame snapshot handed across the actor → main-actor boundary.
/// `CGImage` is an immutable, thread-safe CF type.
struct VNCFrame: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
}

enum VNCError: LocalizedError {
    case connectionClosed
    case handshakeFailed(String)
    case authFailed(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed: "The console connection closed."
        case .handshakeFailed(let m): "Handshake failed: \(m)"
        case .authFailed(let m): "Authentication failed: \(m)"
        case .protocolError(let m): "Protocol error: \(m)"
        }
    }
}

/// Drives the RFB protocol over an `NWConnection`. An actor so the read loop and
/// input sends serialise safely; the read loop suspends at `receive`, letting
/// input events through (actor reentrancy) without blocking.
actor RFBClient {
    nonisolated(unsafe) var onPhase: (@Sendable (VNCConnection.Phase) -> Void)?
    nonisolated(unsafe) var onFrame: (@Sendable (VNCFrame) -> Void)?

    private let host: String
    private let port: UInt16
    private let password: String
    private let connection: NWConnection
    private var framebuffer: VNCFramebuffer?
    private var stopped = false

    init(host: String, port: UInt16, password: String) {
        self.host = host
        self.port = port
        self.password = password
        // Proxmox's VNC proxy speaks plaintext RFB (the API token authorised the
        // proxy; the transport itself is unencrypted, keep it on LAN/Tailscale).
        connection = NWConnection(
            host: .init(host), port: .init(rawValue: port) ?? .any, using: .tcp
        )
    }

    nonisolated func start() {
        Task { await run() }
    }

    nonisolated func stop() {
        Task { await teardown() }
    }

    nonisolated func sendPointer(buttonMask: UInt8, x: UInt16, y: UInt16) {
        Task { await send(VNCProtocol.pointerEvent(buttonMask: buttonMask, x: x, y: y)) }
    }

    nonisolated func sendKey(down: Bool, key: UInt32) {
        Task { await send(VNCProtocol.keyEvent(down: down, key: key)) }
    }

    private func teardown() {
        stopped = true
        connection.cancel()   // unblocks any pending receive, ending the read loop
    }

    private func run() async {
        do {
            try await waitUntilReady()
            try await handshake()
            onPhase?(.connected)
            try await readMessages()
            onPhase?(.closed)
        } catch {
            if stopped {
                onPhase?(.closed)
            } else {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                onPhase?(.failed(message))
            }
            connection.cancel()
        }
    }

    // MARK: - Handshake

    private func handshake() async throws {
        // 1. ProtocolVersion: read the server's, reply with ours.
        _ = try await receive(exactly: 12)
        try await send(Data(VNCProtocol.versionHandshake.utf8))

        // 2. Security types.
        onPhase?(.authenticating)
        let count = try await receive(exactly: 1)[0]
        guard count > 0 else {
            let reason = try await readFailureReason()
            throw VNCError.handshakeFailed(reason)
        }
        let types = [UInt8](try await receive(exactly: Int(count)))
        let chosen: VNCProtocol.SecurityType =
            types.contains(VNCProtocol.SecurityType.vncAuth.rawValue) ? .vncAuth
            : types.contains(VNCProtocol.SecurityType.none.rawValue) ? .none
            : .invalid
        guard chosen != .invalid else {
            throw VNCError.authFailed("No supported security type offered.")
        }
        try await send(Data([chosen.rawValue]))

        // 3. VNC authentication challenge/response.
        if chosen == .vncAuth {
            let challenge = try await receive(exactly: 16)
            try await send(VNCAuth.response(challenge: challenge, password: password))
        }

        // 4. SecurityResult (3.8 always sends it).
        let result = try await receiveUInt32()
        if result != 0 {
            throw VNCError.authFailed(try await readFailureReason())
        }

        // 5. ClientInit → ServerInit.
        try await send(VNCProtocol.clientInit(shared: true))
        let width = Int(try await receiveUInt16())
        let height = Int(try await receiveUInt16())
        _ = try await receive(exactly: 16)              // server pixel format (we override)
        let nameLength = Int(try await receiveUInt32())
        if nameLength > 0 { _ = try await receive(exactly: nameLength) }

        framebuffer = VNCFramebuffer(width: width, height: height)

        // 6. Negotiate our pixel format + encodings, then request the first frame.
        try await send(VNCProtocol.setPixelFormat())
        try await send(VNCProtocol.setEncodings([.copyRect, .raw, .desktopSize, .lastRect]))
        try await requestUpdate(incremental: false)
    }

    // MARK: - Update loop

    private func readMessages() async throws {
        while !stopped {
            let type = try await receive(exactly: 1)[0]
            switch VNCProtocol.ServerMessage(rawValue: type) {
            case .framebufferUpdate:
                try await readFramebufferUpdate()
            case .bell:
                break
            case .serverCutText:
                _ = try await receive(exactly: 3)
                let length = Int(try await receiveUInt32())
                if length > 0 { _ = try await receive(exactly: length) }
            case .setColorMapEntries:
                _ = try await receive(exactly: 3)
                _ = try await receiveUInt16()
                let colours = Int(try await receiveUInt16())
                if colours > 0 { _ = try await receive(exactly: colours * 6) }
            case .none:
                throw VNCError.protocolError("Unknown server message \(type)")
            }
        }
    }

    private func readFramebufferUpdate() async throws {
        _ = try await receive(exactly: 1)               // padding
        let rectangles = try await receiveUInt16()
        for _ in 0..<rectangles {
            let x = Int(try await receiveUInt16())
            let y = Int(try await receiveUInt16())
            let w = Int(try await receiveUInt16())
            let h = Int(try await receiveUInt16())
            let encoding = Int32(bitPattern: try await receiveUInt32())

            switch VNCProtocol.Encoding(rawValue: encoding) {
            case .raw:
                let bytes = w * h * VNCProtocol.bytesPerPixel
                let data = bytes > 0 ? [UInt8](try await receive(exactly: bytes)) : []
                framebuffer?.applyRaw(x: x, y: y, w: w, h: h, data: data)
            case .copyRect:
                let srcX = Int(try await receiveUInt16())
                let srcY = Int(try await receiveUInt16())
                framebuffer?.applyCopyRect(x: x, y: y, w: w, h: h, srcX: srcX, srcY: srcY)
            case .desktopSize:
                framebuffer?.resize(width: w, height: h)
            case .lastRect:
                publishFrame()
                try await requestUpdate(incremental: true)
                return
            case .none:
                throw VNCError.protocolError("Unsupported encoding \(encoding)")
            }
        }
        publishFrame()
        try await requestUpdate(incremental: true)
    }

    private func publishFrame() {
        guard let framebuffer, let image = framebuffer.makeImage() else { return }
        onFrame?(VNCFrame(image: image,
                          size: CGSize(width: framebuffer.width, height: framebuffer.height)))
    }

    private func requestUpdate(incremental: Bool) async throws {
        guard let framebuffer else { return }
        try await send(VNCProtocol.framebufferUpdateRequest(
            incremental: incremental, x: 0, y: 0,
            width: UInt16(clamping: framebuffer.width), height: UInt16(clamping: framebuffer.height)
        ))
    }

    // MARK: - Socket primitives

    private func waitUntilReady() async throws {
        let queue = DispatchQueue(label: "vnc.rfb")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let error): cont.resume(throwing: error)
                case .cancelled: cont.resume(throwing: VNCError.connectionClosed)
                default: break
                }
            }
            connection.start(queue: queue)
        }
        connection.stateUpdateHandler = nil
    }

    private func receive(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        return try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) {
                data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if let data, data.count == count { cont.resume(returning: data); return }
                cont.resume(throwing: isComplete ? VNCError.connectionClosed
                                                 : VNCError.protocolError("short read"))
            }
        }
    }

    private func send(_ data: Data) async {
        // Best-effort: a send failure surfaces on the next receive as a closed socket.
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receiveUInt16() async throws -> UInt16 {
        let data = try await receive(exactly: 2)
        return UInt16(data[0]) << 8 | UInt16(data[1])
    }

    private func receiveUInt32() async throws -> UInt32 {
        let data = try await receive(exactly: 4)
        return UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
    }

    private func readFailureReason() async throws -> String {
        let length = Int(try await receiveUInt32())
        guard length > 0 else { return "Connection rejected." }
        let data = try await receive(exactly: length)
        return String(data: data, encoding: .utf8) ?? "Connection rejected."
    }
}
#endif
