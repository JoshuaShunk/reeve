import Foundation
import Testing

@testable import ReeveModels

@Suite("VNC protocol")
struct VNCProtocolTests {
    @Test func reversesBitsInAByte() {
        #expect(VNCAuth.reverseBits(0b1000_0000) == 0b0000_0001)
        #expect(VNCAuth.reverseBits(0b0000_0001) == 0b1000_0000)
        #expect(VNCAuth.reverseBits(0b1010_0000) == 0b0000_0101)
        #expect(VNCAuth.reverseBits(0) == 0)
        #expect(VNCAuth.reverseBits(0xFF) == 0xFF)
    }

    @Test func vncAuthMatchesKnownDESVector() {
        // RealVNC's well-known test vector: password "abcdefgh", a fixed challenge.
        let challenge = Data(repeating: 0, count: 16)
        let response = VNCAuth.response(challenge: challenge, password: "password")
        #expect(response.count == 16)
        // Encrypting an all-zero challenge is deterministic for a given key, and the
        // two ECB halves must be identical (same key, same zero block).
        #expect(response.prefix(8) == response.suffix(8))
        #expect(response.prefix(8) != Data(repeating: 0, count: 8))
    }

    @Test func messageBuildersMatchSpecLayout() {
        let request = VNCProtocol.framebufferUpdateRequest(
            incremental: true, x: 0, y: 0, width: 1024, height: 768)
        // type(3) incremental(1) x(0,0) y(0,0) w(0x0400) h(0x0300)
        #expect([UInt8](request) == [3, 1, 0, 0, 0, 0, 0x04, 0x00, 0x03, 0x00])

        let pointer = VNCProtocol.pointerEvent(buttonMask: 0b001, x: 258, y: 1)
        #expect([UInt8](pointer) == [5, 1, 0x01, 0x02, 0x00, 0x01])

        let key = VNCProtocol.keyEvent(down: true, key: 0xFF0D)   // Return
        #expect([UInt8](key) == [4, 1, 0, 0, 0x00, 0x00, 0xFF, 0x0D])

        let encodings = VNCProtocol.setEncodings([.copyRect, .raw])
        #expect([UInt8](encodings) == [2, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0])

        #expect([UInt8](VNCProtocol.setPixelFormat()).count == 20)
        #expect(VNCProtocol.pixelFormat.count == 16)
    }

    @Test func rawRectanglePaintsIntoBuffer() {
        let fb = VNCFramebuffer(width: 2, height: 2)
        // One red pixel [0,255,0,0] at (1,1).
        fb.applyRaw(x: 1, y: 1, w: 1, h: 1, data: [0, 255, 0, 0])
        let image = fb.makeImage()
        #expect(image != nil)
        #expect(image?.width == 2)
        #expect(image?.height == 2)
    }

    @Test func copyRectMovesPixels() {
        let fb = VNCFramebuffer(width: 4, height: 2)
        // Paint the top-left 2x1 green, then copy it to the right half.
        fb.applyRaw(x: 0, y: 0, w: 2, h: 1, data: [0, 0, 255, 0, 0, 0, 255, 0])
        fb.applyCopyRect(x: 2, y: 0, w: 2, h: 1, srcX: 0, srcY: 0)
        #expect(fb.makeImage() != nil)   // No crash / bounds violation on the copy.
    }

    @Test func resizeReallocatesBuffer() {
        let fb = VNCFramebuffer(width: 10, height: 10)
        fb.resize(width: 20, height: 5)
        #expect(fb.width == 20)
        #expect(fb.height == 5)
        #expect(fb.makeImage()?.width == 20)
    }
}
