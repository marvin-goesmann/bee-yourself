import CoreGraphics
import Foundation

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    static let white = RGB(r: 255, g: 255, b: 255)

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        r = Double((value >> 16) & 0xFF)
        g = Double((value >> 8) & 0xFF)
        b = Double(value & 0xFF)
    }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func multiplied(by tint: RGB) -> RGB {
        RGB(r: r * tint.r / 255, g: g * tint.g / 255, b: b * tint.b / 255)
    }

    var luminance: Double { (r + g + b) / 765 }
}

final class PixelCanvas {
    private static let colourSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    let width: Int
    let height: Int
    let pixels: UnsafeMutablePointer<UInt8>
    var tint = RGB.white
    private let context: CGContext

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = .allocate(capacity: width * height * 4)
        pixels.initialize(repeating: 255, count: width * height * 4)
        context = CGContext(
            data: pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: PixelCanvas.colourSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
    }

    deinit { pixels.deallocate() }

    func fill(_ x: Double, _ y: Double, _ w: Int, _ h: Int, _ colour: RGB, alpha: Double = 1) {
        let c = tint == .white ? colour : colour.multiplied(by: tint)
        let x0 = max(0, Int(x.rounded())), y0 = max(0, Int(y.rounded()))
        let x1 = min(width, Int(x.rounded()) + w), y1 = min(height, Int(y.rounded()) + h)
        guard x0 < x1, y0 < y1 else { return }
        let r = UInt8(clamping: Int(c.r)), g = UInt8(clamping: Int(c.g)), b = UInt8(clamping: Int(c.b))
        for yy in y0..<y1 {
            var p = pixels + (yy * width + x0) * 4
            for _ in x0..<x1 {
                if alpha >= 1 {
                    p[0] = r; p[1] = g; p[2] = b
                } else if alpha > 0 {
                    p[0] = UInt8(Double(p[0]) * (1 - alpha) + c.r * alpha)
                    p[1] = UInt8(Double(p[1]) * (1 - alpha) + c.g * alpha)
                    p[2] = UInt8(Double(p[2]) * (1 - alpha) + c.b * alpha)
                }
                p += 4
            }
        }
    }

    func pixel(_ x: Int, _ y: Int, _ colour: RGB, alpha: Double = 1) {
        fill(Double(x), Double(y), 1, 1, colour, alpha: alpha)
    }

    func multiplyAll(by colour: RGB) {
        let r = colour.r / 255, g = colour.g / 255, b = colour.b / 255
        var p = pixels
        for _ in 0..<(width * height) {
            p[0] = UInt8(Double(p[0]) * r); p[1] = UInt8(Double(p[1]) * g); p[2] = UInt8(Double(p[2]) * b)
            p += 4
        }
    }

    func copy(from other: PixelCanvas) {
        pixels.update(from: other.pixels, count: width * height * 4)
    }

    func makeImage() -> CGImage? { context.makeImage() }
}
