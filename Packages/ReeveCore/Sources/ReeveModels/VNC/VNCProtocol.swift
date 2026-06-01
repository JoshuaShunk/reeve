import Foundation

/// Wire-format constants and message builders for the RFB 3.8 protocol
/// (RFC 6143). All multi-byte integers are big-endian (network order).
public enum VNCProtocol {
    /// The protocol version this client speaks.
    public static let versionHandshake = "RFB 003.008\n"

    public enum SecurityType: UInt8 {
        case invalid = 0, none = 1, vncAuth = 2
    }

    /// Encoding numbers we advertise (preference order) plus pseudo-encodings.
    public enum Encoding: Int32 {
        case raw = 0
        case copyRect = 1
        case desktopSize = -223   // pseudo: server can resize the framebuffer
        case lastRect = -224      // pseudo: "no more rectangles" sentinel
    }

    /// Server→client message types.
    public enum ServerMessage: UInt8 {
        case framebufferUpdate = 0
        case setColorMapEntries = 1
        case bell = 2
        case serverCutText = 3
    }

    /// Our fixed pixel format: 32-bit true colour, big-endian, channels packed as
    /// 0x00RRGGBB, so each pixel arrives as bytes [0, R, G, B], which maps directly
    /// to a `byteOrder32Big` + alpha-skip-first `CGImage` (see `VNCFramebuffer`).
    public static let pixelFormat: [UInt8] = [
        32,        // bits-per-pixel
        24,        // depth
        1,         // big-endian-flag
        1,         // true-colour-flag
        0, 255,    // red-max   (u16)
        0, 255,    // green-max (u16)
        0, 255,    // blue-max  (u16)
        16,        // red-shift
        8,         // green-shift
        0,         // blue-shift
        0, 0, 0,   // padding
    ]
    public static let bytesPerPixel = 4

    // MARK: - Client message builders

    /// SetPixelFormat (type 0).
    public static func setPixelFormat() -> Data {
        var data = Data([0, 0, 0, 0])   // type + 3 padding
        data.append(contentsOf: pixelFormat)
        return data
    }

    /// SetEncodings (type 2).
    public static func setEncodings(_ encodings: [Encoding]) -> Data {
        var data = Data([2, 0])   // type + 1 padding
        data.appendBigEndian(UInt16(encodings.count))
        for encoding in encodings { data.appendBigEndian(UInt32(bitPattern: encoding.rawValue)) }
        return data
    }

    /// FramebufferUpdateRequest (type 3).
    public static func framebufferUpdateRequest(
        incremental: Bool, x: UInt16, y: UInt16, width: UInt16, height: UInt16
    ) -> Data {
        var data = Data([3, incremental ? 1 : 0])
        data.appendBigEndian(x); data.appendBigEndian(y)
        data.appendBigEndian(width); data.appendBigEndian(height)
        return data
    }

    /// KeyEvent (type 4). `key` is an X11 keysym.
    public static func keyEvent(down: Bool, key: UInt32) -> Data {
        var data = Data([4, down ? 1 : 0, 0, 0])   // type + down + 2 padding
        data.appendBigEndian(key)
        return data
    }

    /// PointerEvent (type 5). `buttonMask` bit 0 = left, 1 = middle, 2 = right.
    public static func pointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) -> Data {
        var data = Data([5, buttonMask])
        data.appendBigEndian(x); data.appendBigEndian(y)
        return data
    }

    /// ClientInit (shared-flag).
    public static func clientInit(shared: Bool) -> Data { Data([shared ? 1 : 0]) }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(value >> 8)); append(UInt8(value & 0xFF))
    }
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF)); append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF)); append(UInt8(value & 0xFF))
    }
}
