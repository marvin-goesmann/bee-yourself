import AppKit

enum AppIcon {
    private static let outline = RGB("#3b2416")

    static func writeIconset(to directory: String) {
        let (canvas, cells) = scene()
        guard let art = canvas.makeImage(), let master = master(art, cells: cells) else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            write(master, size: size, to: "\(directory)/icon_\(size)x\(size).png")
            write(master, size: size * 2, to: "\(directory)/icon_\(size)x\(size)@2x.png")
        }
    }

    private static func scene() -> (PixelCanvas, Int) {
        let cells = 22, pad = 3, g = cells + pad * 2
        let c = PixelCanvas(width: g, height: g)
        let sky = ["#8fc3e0", "#a9d2e6", "#c7e2ea", "#e6efe2"].map(RGB.init)
        for y in 0..<18 { c.fill(0, Double(y), g, 1, sky[min(3, max(0, y - 2) / 4)]) }
        c.fill(0, 18, g, 2, RGB("#98b066"))
        c.fill(0, 20, g, g - 20, RGB("#7f9c47"))
        for (x, y, petal) in [(6, 22, "#f6f2e6"), (19, 21, "#e8a0b4"), (14, 23, "#f6f2e6")] {
            c.pixel(x, y, RGB("#f2c94c")); c.pixel(x - 1, y, RGB(petal)); c.pixel(x + 1, y, RGB(petal)); c.pixel(x, y - 1, RGB(petal)); c.pixel(x, y + 1, RGB(petal))
        }
        drawBee(on: c, ox: 5, oy: 5)
        return (c, cells)
    }

    private static func drawBee(on c: PixelCanvas, ox: Int, oy: Int) {
        let w = 17, h = 15
        var art = [[RGB?]](repeating: [RGB?](repeating: nil, count: w), count: h)
        func inside(_ x: Int, _ y: Int, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Bool {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            return dx * dx + dy * dy <= 1
        }
        for y in 0..<h { for x in 0..<w where inside(x, y, 5.5, 4, 2.4, 3) || inside(x, y, 10.5, 4.5, 2, 2.6) {
            art[y][x] = y >= 5 ? RGB("#c9def0") : RGB("#f4f9ff")
        } }
        for y in 0..<h { for x in 0..<w where inside(x, y, 8, 9.5, 6.6, 4.6) {
            var colour = x == 4 || x == 7 ? outline : RGB("#f6c84a")
            if colour != outline && y <= 6 && x < 12 { colour = RGB("#ffe08a") }
            if colour != outline && y >= 13 { colour = RGB("#e2a52c") }
            art[y][x] = colour
        } }
        art[9][0] = outline
        art[8][11] = outline; art[8][12] = outline; art[9][11] = outline; art[9][12] = outline; art[8][11] = .white
        art[10][13] = RGB("#f29a8a")
        var edged = art
        for y in 0..<h { for x in 0..<w where art[y][x] == nil {
            let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                let nx = x + dx, ny = y + dy
                return nx >= 0 && ny >= 0 && nx < w && ny < h && art[ny][nx] != nil
            }
            if touches { edged[y][x] = outline }
        } }
        for (x, y) in [(13, 4), (13, 3), (14, 2), (15, 4), (16, 3)] { edged[y][x] = outline }
        for y in 0..<h { for x in 0..<w { if let colour = edged[y][x] { c.pixel(ox + x, oy + y, colour) } } }
    }

    private static func master(_ art: CGImage, cells: Int) -> CGImage? {
        let size = 1024
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
        ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(shape); ctx.clip()
        ctx.interpolationQuality = .none
        let cell = Double(body.width) / Double(cells)
        let side = cell * Double(art.width)
        ctx.draw(art, in: CGRect(x: body.midX - side / 2, y: body.midY - side / 2, width: side, height: side))
        return ctx.makeImage()
    }

    private static func write(_ image: CGImage, size: Int, to path: String) {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = size >= 256 ? .none : .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let scaled = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: scaled)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
