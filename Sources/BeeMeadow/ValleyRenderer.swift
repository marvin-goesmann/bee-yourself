import Foundation

extension GardenKind {
    var shortName: String {
        switch self {
        case .clover: "Clover"
        case .heather: "Heather"
        case .bramble: "Bramble"
        case .lavender: "Lavender"
        case .yellowBox: "Yellow box"
        case .orangeBlossom: "Orange"
        }
    }

    var sampleColours: [RGB] {
        switch self {
        case .clover: [RGB("#f6f2e6"), RGB("#e8a0b4"), RGB("#c592d8")]
        case .heather: [RGB("#a46cc0"), RGB("#8e5aa8"), RGB("#c08ad0")]
        case .bramble: [RGB("#f6f0e8"), RGB("#5a2a4a"), RGB("#f6f0e8")]
        case .lavender: [RGB("#8a6cc8"), RGB("#7a5cb8"), RGB("#b49ce0")]
        case .yellowBox: [RGB("#f4ecc8"), RGB("#748c72"), RGB("#f8f2d8")]
        case .orangeBlossom: [RGB("#4f7a3a"), RGB("#fbf6ee"), RGB("#f08a2a")]
        }
    }
}

final class ValleyRenderer {
    static let stallRect: PixelRect = (6, 66, 48, 50)

    static func plotRect(_ plot: Int) -> PixelRect {
        (62 + (plot % 3) * 60, 28 + (plot / 3) * 50, 52, 36)
    }

    static func plot(at p: (x: Double, y: Double)) -> Int? {
        (0..<Layout.plots).first { Widgets.contains(plotRect($0), p) }
    }

    private enum C {
        static let grass = RGB("#8fae58"), grassDark = RGB("#7c9a4c"), grassLight = RGB("#a2be68"), path = RGB("#d8c08a"), pathEdge = RGB("#bca470")
        static let fence = RGB("#8a5a2b"), fenceLight = RGB("#b07a42"), label = RGB("#3e2816"), highlight = RGB("#fff2c0")
        static let sign = RGB("#b07a42"), signFace = RGB("#e8d0a0"), awning = RGB("#c4573f"), awningLight = RGB("#f2e6d8"), counter = RGB("#9c6a34")
    }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private var specks: [(x: Int, y: Int, dark: Bool)] = []

    init() {
        var r = SeededRandom(seed: 555)
        specks = (0..<260).map { _ in (r.int(Layout.width), 19 + r.int(Layout.height - 19), r.next() < 0.6) }
    }

    func render(_ world: World, minute: Double, time: Double, current: Int, hover: (x: Double, y: Double)?) {
        let c = canvas
        c.tint = Clock.light(at: minute).tint.mixed(with: .white, 0.35)
        c.fill(0, 19, Layout.width, Layout.height - 19, C.grass)
        for s in specks { c.pixel(s.x, s.y, s.dark ? C.grassDark : C.grassLight) }
        for row in 0..<3 {
            let y = Double(28 + row * 50 + 40)
            c.fill(54, y, 182, 3, C.path); c.fill(54, y + 3, 182, 1, C.pathEdge)
        }
        for col in 0..<3 {
            let x = Double(62 + col * 60 + 54)
            if col < 2 { c.fill(x, 26, 4, 146, C.path); c.fill(x + 4, 26, 1, 146, C.pathEdge) }
        }
        c.fill(30, 91, 32, 3, C.path)

        drawStall(time: time)
        let hoveredPlot = hover.flatMap(ValleyRenderer.plot(at:))
        for plot in 0..<Layout.plots {
            let r = ValleyRenderer.plotRect(plot)
            if let garden = world.gardens.first(where: { $0.plot == plot }) {
                drawGarden(garden, world: world, r: r, time: time)
                if garden.id == current || hoveredPlot == plot { outline(r, C.highlight) }
            } else {
                drawEmptyPlot(r, price: world.gardenPrice(), hovered: hoveredPlot == plot)
            }
        }
        c.tint = .white
        Widgets.header(c, title: "Valley", detail: world.jars.count == 1 ? "1 jar" : "\(world.jars.count) jars")
    }

    private func outline(_ r: PixelRect, _ colour: RGB) {
        let x = Double(r.x - 2), y = Double(r.y - 2)
        canvas.fill(x, y, r.w + 4, 1, colour); canvas.fill(x, y + Double(r.h + 3), r.w + 4, 1, colour)
        canvas.fill(x, y, 1, r.h + 4, colour); canvas.fill(x + Double(r.w + 3), y, 1, r.h + 4, colour)
    }

    private func drawGarden(_ garden: Garden, world: World, r: PixelRect, time: Double) {
        let c = canvas, palette = GroundPalette.of(garden.kind), x = Double(r.x), y = Double(r.y)
        c.fill(x, y, r.w, r.h, palette.ground)
        var rng = SeededRandom(seed: 77 + garden.id)
        for _ in 0..<26 { c.pixel(r.x + rng.int(r.w), r.y + rng.int(r.h), palette.groundDark) }
        let colours = garden.kind.sampleColours
        for i in 0..<22 {
            let fx = r.x + 26 + rng.int(r.w - 28), fy = r.y + 4 + rng.int(r.h - 7)
            c.pixel(fx, fy, colours[i % colours.count]); c.pixel(fx, fy + 1, palette.grass)
        }
        for (i, hive) in world.hives(in: garden.id).prefix(World.hivesPerGarden).enumerated() {
            let hx = x + 4 + Double(i % 2) * 10, hy = y + 6 + Double(i / 2) * 13
            c.fill(hx, hy, 7, 2, RGB("#c4573f")); c.fill(hx + 1, hy + 2, 5, 5, RGB("#dba660")); c.fill(hx + 2, hy + 5, 3, 1, RGB("#3b2416"))
            if hive.isFull { c.fill(hx + 6, hy + 3, 1, 1, RGB("#ffc24a")) }
        }
        let wingUp = Int(time * 6) % 2 == 0
        for k in 0..<min(6, world.hives(in: garden.id).count * 2) {
            let bx = x + 14 + Double(r.w - 18) * (0.5 + 0.45 * sin(time * 0.4 + Double(k) * 1.7 + Double(garden.id)))
            let by = y + 8 + Double(r.h - 14) * (0.5 + 0.4 * sin(time * 0.53 + Double(k) * 2.3))
            c.fill(bx, by, 1, 1, RGB("#f2b632")); if wingUp { c.fill(bx, by - 1, 1, 1, RGB("#fff8e6")) }
        }
        for i in stride(from: 0, to: r.w, by: 4) { c.fill(x + Double(i), y + Double(r.h - 1), 2, 1, C.fenceLight) }
        c.fill(x, y + Double(r.h), r.w, 1, C.fence)
        let label = garden.kind.shortName
        c.fill(x + Double((r.w - PixelFont.width(label)) / 2 - 2), y + Double(r.h + 2), PixelFont.width(label) + 4, 0, C.path)
        PixelFont.draw(label, on: c, x: r.x + (r.w - PixelFont.width(label)) / 2, y: r.y + r.h - 8, colour: RGB("#fff6dc"), shadow: C.label)
    }

    private func drawEmptyPlot(_ r: PixelRect, price: Int, hovered: Bool) {
        let c = canvas, x = Double(r.x), y = Double(r.y)
        for yy in stride(from: 0, to: r.h, by: 2) { for xx in stride(from: (yy / 2) % 2 * 2, to: r.w, by: 4) { c.fill(x + Double(xx), y + Double(yy), 1, 1, C.grassDark) } }
        let sx = x + Double(r.w / 2 - 9), sy = y + 8
        c.fill(sx + 8, sy + 6, 2, 12, C.sign)
        c.fill(sx, sy, 18, 8, C.label); c.fill(sx + 1, sy + 1, 16, 6, hovered ? C.highlight : C.signFace)
        PixelFont.draw("+", on: c, x: Int(sx) + 7, y: Int(sy) + 2, colour: C.label)
        let label = "\(price) jars"
        PixelFont.draw(label, on: c, x: r.x + (r.w - PixelFont.width(label)) / 2, y: r.y + r.h - 8, colour: RGB("#fff6dc"), shadow: C.label)
        if hovered { outline(r, C.highlight) }
    }

    private func drawStall(time: Double) {
        let c = canvas, r = ValleyRenderer.stallRect, x = Double(r.x), y = Double(r.y)
        c.fill(x + 3, y + 10, 2, 30, C.fence); c.fill(x + Double(r.w - 5), y + 10, 2, 30, C.fence)
        for i in 0..<8 { c.fill(x + Double(i * 6), y + 4, 6, 7, i % 2 == 0 ? C.awning : C.awningLight) }
        for i in 0..<8 { c.fill(x + Double(i * 6) + 1, y + 11, 4, 2, i % 2 == 0 ? C.awning : C.awningLight) }
        c.fill(x, y + 3, r.w, 1, RGB("#963d2d"))
        c.fill(x + 1, y + 28, r.w - 2, 12, C.counter); c.fill(x + 1, y + 28, r.w - 2, 1, RGB("#b88446"))
        for (i, honey) in ["Clover", "Heather", "Lavender", "Bramble"].enumerated() {
            Widgets.jar(c, honey: honey, x: x + 5 + Double(i) * 10, y: y + 19, small: false)
        }
        PixelFont.draw("Stall", on: c, x: r.x + (r.w - PixelFont.width("Stall")) / 2, y: r.y + 43, colour: RGB("#fff6dc"), shadow: C.label)
    }
}
