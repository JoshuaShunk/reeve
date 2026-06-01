#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// An off-screen pixel store the RFB client paints rectangles into, producing a
/// `CGImage` snapshot for rendering. Pixels are 4 bytes each in `[0, R, G, B]`
/// order to match `VNCProtocol.pixelFormat`.
public final class VNCFramebuffer {
    public private(set) var width: Int
    public private(set) var height: Int
    private var pixels: [UInt8]

    private var bytesPerRow: Int { width * VNCProtocol.bytesPerPixel }

    public init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        pixels = [UInt8](repeating: 0, count: self.width * self.height * VNCProtocol.bytesPerPixel)
    }

    /// Resize for a DesktopSize change, preserving nothing (server repaints).
    public func resize(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        pixels = [UInt8](repeating: 0, count: self.width * self.height * VNCProtocol.bytesPerPixel)
    }

    /// Paint a Raw rectangle. `data` is `w * h` pixels, 4 bytes each (`[x, R, G, B]`).
    /// Out-of-bounds rectangles are clipped defensively.
    public func applyRaw(x: Int, y: Int, w: Int, h: Int, data: [UInt8]) {
        let bpp = VNCProtocol.bytesPerPixel
        guard data.count >= w * h * bpp else { return }
        for row in 0..<h {
            let destY = y + row
            guard destY >= 0, destY < height else { continue }
            let copyWidth = min(w, width - x)
            guard copyWidth > 0, x >= 0 else { continue }
            let srcStart = row * w * bpp
            let destStart = destY * bytesPerRow + x * bpp
            pixels.replaceSubrange(
                destStart..<(destStart + copyWidth * bpp),
                with: data[srcStart..<(srcStart + copyWidth * bpp)]
            )
        }
    }

    /// Copy an existing rectangle to a new location (CopyRect encoding). Copies
    /// row-by-row in a direction that tolerates overlapping regions.
    public func applyCopyRect(x: Int, y: Int, w: Int, h: Int, srcX: Int, srcY: Int) {
        let bpp = VNCProtocol.bytesPerPixel
        let rows = srcY < y ? Array((0..<h).reversed()) : Array(0..<h)
        for row in rows {
            let from = srcY + row, to = y + row
            guard from >= 0, from < height, to >= 0, to < height else { continue }
            let copyWidth = min(w, width - max(x, srcX))
            guard copyWidth > 0, x >= 0, srcX >= 0 else { continue }
            let srcStart = from * bytesPerRow + srcX * bpp
            let destStart = to * bytesPerRow + x * bpp
            let slice = Array(pixels[srcStart..<(srcStart + copyWidth * bpp)])
            pixels.replaceSubrange(destStart..<(destStart + copyWidth * bpp), with: slice)
        }
    }

    #if canImport(CoreGraphics)
    /// An immutable snapshot of the current contents for display.
    public func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }
    #endif
}
