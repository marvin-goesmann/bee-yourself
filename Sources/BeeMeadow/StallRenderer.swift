import Foundation

final class StallRenderer {
    static let tradeRect: PixelRect = (150, 62, 44, 13)
    static let valleyRect: PixelRect = (150, 122, 54, 13)

    static func pickerRect(_ index: Int) -> PixelRect {
        (12 + (index % 3) * 76, 34 + (index / 3) * 70, 64, 60)
    }

    private enum C {
        static let wall = RGB("#6e4a2c"), plank = RGB("#5f3f24"), card = RGB("#f4e6c8"), cardEdge = RGB("#4a2c14")
        static let title = RGB("#4a2c14"), muted = RGB("#8a6a44"), awning = RGB("#c4573f"), awningLight = RGB("#f2e6d8")
        static let dim = RGB("#2a1a0a")
    }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private var toast: (text: String, age: Double)?

    func show(_ text: String) { toast = (text, 0) }

    func renderStall(_ world: World, time: Double, dt: Double) {
        backdrop()
        card(x: 16, y: 40, w: 208, h: 46)
        hiveBoxIcon(x: 26, y: 72)
        PixelFont.draw("Hive box", on: canvas, x: 56, y: 50, colour: C.title)
        PixelFont.draw("\(World.hiveBoxPrice) jars", on: canvas, x: 56, y: 60, colour: C.muted)
        PixelFont.draw("in your shed: \(world.spareBoxes)", on: canvas, x: 56, y: 72, colour: C.muted)
        Widgets.button(canvas, StallRenderer.tradeRect, label: "Trade", enabled: world.jars.count >= World.hiveBoxPrice)

        card(x: 16, y: 100, w: 208, h: 46)
        Widgets.mapIconAt(canvas, x: 28, y: 114)
        PixelFont.draw("New garden", on: canvas, x: 56, y: 110, colour: C.title)
        PixelFont.draw("\(world.gardenPrice()) jars", on: canvas, x: 56, y: 120, colour: C.muted)
        PixelFont.draw(world.freePlots().isEmpty ? "the valley is full" : "pick a plot", on: canvas, x: 56, y: 132, colour: C.muted)
        Widgets.button(canvas, StallRenderer.valleyRect, label: "To valley", enabled: true)

        Widgets.header(canvas, title: "Honey stall", detail: world.jars.count == 1 ? "1 jar" : "\(world.jars.count) jars")
        drawToast(dt: dt)
    }

    func renderPicker(_ world: World, time: Double, dt: Double, hover: (x: Double, y: Double)?) {
        backdrop()
        let price = world.gardenPrice(), affordable = world.jars.count >= price
        for (i, kind) in GardenKind.allCases.enumerated() {
            let r = StallRenderer.pickerRect(i)
            let hovered = hover.map { Widgets.contains(r, $0) } ?? false
            card(x: r.x, y: r.y, w: r.w, h: r.h, lifted: hovered && affordable)
            let palette = GroundPalette.of(kind), sx = Double(r.x + 4), sy = Double(r.y + 4)
            canvas.fill(sx, sy, r.w - 8, 34, palette.ground)
            canvas.fill(sx, sy, r.w - 8, 8, palette.hills[0])
            var rng = SeededRandom(seed: 21 + i)
            let colours = kind.sampleColours
            for k in 0..<30 {
                let fx = Double(r.x + 6 + rng.int(r.w - 12)), fy = Double(r.y + 14 + rng.int(22))
                canvas.fill(fx, fy, 2, 2, colours[k % colours.count]); canvas.fill(fx, fy + 2, 1, 1, palette.grass)
            }
            PixelFont.draw(kind.shortName, on: canvas, x: r.x + 5, y: r.y + 42, colour: C.title)
            Widgets.jar(canvas, honey: kind.honeyName, x: Double(r.x + r.w - 11), y: Double(r.y + 41), small: true)
            PixelFont.draw("honey", on: canvas, x: r.x + 5, y: r.y + 50, colour: C.muted)
            if !affordable { canvas.fill(Double(r.x), Double(r.y), r.w, r.h, C.dim, alpha: 0.35) }
        }
        let detail = affordable ? "\(price) jars" : "need \(price) jars"
        Widgets.header(canvas, title: "New garden", detail: detail)
        drawToast(dt: dt)
    }

    private func backdrop() {
        let c = canvas
        c.tint = .white
        c.fill(0, 0, Layout.width, Layout.height, C.wall)
        var y = 19
        while y < Layout.height { c.fill(0, Double(y), Layout.width, 1, C.plank); y += 9 }
        for i in 0..<20 { c.fill(Double(i * 12), 19, 12, 8, i % 2 == 0 ? C.awning : C.awningLight) }
        for i in 0..<20 { c.fill(Double(i * 12 + 2), 27, 8, 2, i % 2 == 0 ? C.awning : C.awningLight) }
    }

    private func card(x: Int, y: Int, w: Int, h: Int, lifted: Bool = false) {
        let yy = Double(y - (lifted ? 1 : 0))
        canvas.fill(Double(x + 2), Double(y + 2), w, h, C.dim, alpha: 0.3)
        canvas.fill(Double(x - 1), yy - 1, w + 2, h + 2, C.cardEdge)
        canvas.fill(Double(x), yy, w, h, C.card)
    }

    private func hiveBoxIcon(x: Int, y: Int) {
        let c = canvas, fx = Double(x), fy = Double(y)
        c.fill(fx + 1, fy - 3, 2, 3, RGB("#8a5a2b")); c.fill(fx + 15, fy - 3, 2, 3, RGB("#8a5a2b")); c.fill(fx - 1, fy - 5, 20, 2, RGB("#8a5a2b"))
        c.fill(fx, fy - 25, 18, 20, RGB("#dba660")); c.fill(fx, fy - 25, 1, 20, RGB("#e8bd7c")); c.fill(fx + 17, fy - 25, 1, 20, RGB("#bb8643"))
        c.fill(fx, fy - 15, 18, 1, RGB("#bb8643")); c.fill(fx + 5, fy - 7, 8, 2, RGB("#3b2416"))
        c.fill(fx - 2, fy - 28, 22, 3, RGB("#c4573f")); c.fill(fx - 2, fy - 28, 22, 1, RGB("#dc7a5c"))
    }

    private func drawToast(dt: Double) {
        guard var t = toast else { return }
        t.age += dt
        toast = t.age > 2.4 ? nil : t
        Widgets.note(canvas, lines: [t.text], x: (Layout.width - PixelFont.width(t.text) - 10) / 2, y: 84 - Int(min(1, t.age) * 6))
    }
}
