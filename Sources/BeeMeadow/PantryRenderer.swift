import Foundation

final class PantryRenderer {
    static let bookRect: PixelRect = (196, 3, 14, 13)
    private static let shelves = [60, 112, 164]
    private static let perShelf = 13
    private static let jarWidth = 12, jarHeight = 17, step = 17, left = 11

    private enum C {
        static let wall = RGB("#6e4a2c"), plank = RGB("#5f3f24"), strip = RGB("#3e2816"), stripLine = RGB("#5a3a1e")
        static let shelf = RGB("#b07a42"), shelfLight = RGB("#cf9a5a"), shelfShade = RGB("#6b4520"), shadow = RGB("#1e0f05")
        static let lid = RGB("#c4573f"), lidDark = RGB("#a8452f"), cloth = RGB("#f2e6d8"), string = RGB("#8a5a2b"), glass = RGB("#c8d6cf")
        static let label = RGB("#f4e6c8"), ink = RGB("#b49a72"), sparkle = RGB("#fff6d0"), light = RGB("#ffd696")
        static let name = RGB("#f6dfa6"), stats = RGB("#e7c98c"), textShadow = RGB("#1c1108"), tipText = RGB("#4a2c14")
    }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private let backdrop = PixelCanvas(width: Layout.width, height: Layout.height)
    private var backdropReady = false
    private var scrollRow = 0
    private var lift: [Int: Double] = [:]
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, h:mma"
        return f
    }()

    func open(world: World) {
        scrollRow = max(0, rows(world) - Self.shelves.count)
        lift = [:]
    }

    func scroll(by delta: Int, world: World) {
        scrollRow = min(max(0, rows(world) - Self.shelves.count), max(0, scrollRow + delta))
    }

    private func rows(_ world: World) -> Int { (world.jars.count + Self.perShelf - 1) / Self.perShelf }

    func render(_ world: World, time: Double, dt: Double, mouse: (x: Double, y: Double)?) {
        if !backdropReady { drawBackdrop(); backdropReady = true }
        canvas.copy(from: backdrop)
        canvas.tint = .white

        var hovered: Int?
        let first = scrollRow * Self.perShelf
        let last = min(world.jars.count, first + Self.perShelf * Self.shelves.count)
        for i in first..<max(first, last) {
            let pos = position(of: i - first)
            if let m = mouse, m.x >= Double(pos.x), m.x < Double(pos.x + Self.jarWidth), m.y >= Double(pos.y), m.y < Double(pos.y + Self.jarHeight) { hovered = i }
        }
        for i in first..<max(first, last) {
            let target = i == hovered ? 2.0 : 0
            let current = lift[i] ?? 0
            lift[i] = current + (target - current) * min(1, dt * 14)
            let pos = position(of: i - first)
            drawJar(world.jars[i], x: pos.x, y: pos.y, lift: lift[i] ?? 0, newest: i == world.jars.count - 1, time: time)
        }

        Widgets.backArrow(canvas)
        PixelFont.draw("Pantry", on: canvas, x: Widgets.titleX, y: 7, colour: Widgets.titleColour, shadow: C.textShadow)
        let count = world.jars.count == 1 ? "1 jar" : "\(world.jars.count) jars"
        PixelFont.draw(count, on: canvas, x: PantryRenderer.bookRect.x - 8 - PixelFont.width(count), y: 7, colour: C.stats, shadow: C.textShadow)
        drawBookIcon()
        if world.jars.isEmpty { PixelFont.draw("no jars yet", on: canvas, x: (Layout.width - PixelFont.width("no jars yet")) / 2, y: 84, colour: C.stats) }
        if let hovered { drawTooltip(world.jars[hovered], at: position(of: hovered - first)) }
    }

    private func position(of slot: Int) -> (x: Int, y: Int) {
        (Self.left + (slot % Self.perShelf) * Self.step, Self.shelves[slot / Self.perShelf] - Self.jarHeight)
    }

    private func drawBackdrop() {
        let c = backdrop
        c.fill(0, 0, Layout.width, Layout.height, C.wall)
        var y = 19
        while y < Layout.height { c.fill(0, Double(y), Layout.width, 1, C.plank); y += 9 }
        for row in 0..<18 {
            var x = (row * 37) % 50
            while x < Layout.width { c.fill(Double(x), Double(19 + row * 9), 1, 9, C.plank); x += 50 }
        }
        for y in 19..<Layout.height {
            for x in 0..<Layout.width {
                let band = Double(x) + Double(y) * 0.9
                if band > 150 && band < 210 && (x + y) % 2 == 0 { c.pixel(x, y, C.light, alpha: 0.10) }
            }
        }
        c.fill(0, 0, Layout.width, 18, C.strip); c.fill(0, 18, Layout.width, 1, C.stripLine)
        for sy in Self.shelves {
            let y = Double(sy)
            c.fill(6, y, Layout.width - 12, 3, C.shelf); c.fill(6, y, Layout.width - 12, 1, C.shelfLight); c.fill(6, y + 3, Layout.width - 12, 1, C.shelfShade)
            c.fill(8, y + 4, Layout.width - 16, 2, C.shadow, alpha: 0.25)
            for bx in [18.0, Double(Layout.width - 22)] { c.fill(bx, y + 4, 3, 2, C.shelfShade); c.fill(bx + 1, y + 6, 2, 2, C.shelfShade) }
        }
    }

    private func drawBookIcon() {
        let r = PantryRenderer.bookRect, x = Double(r.x + 1), y = Double(r.y + 1)
        canvas.fill(x, y, 12, 11, RGB("#2a180a"))
        canvas.fill(x + 1, y + 1, 10, 9, RGB("#8a3a2a")); canvas.fill(x + 1, y + 1, 2, 9, RGB("#6a2a1e"))
        canvas.fill(x + 4, y + 3, 6, 1, RGB("#e8c070")); canvas.fill(x + 4, y + 5, 4, 1, RGB("#e8c070"))
        canvas.fill(x + 11, y + 2, 1, 8, RGB("#f4e6c8"))
    }

    private func drawJar(_ jar: Jar, x: Int, y: Int, lift: Double, newest: Bool, time: Double) {
        let honey = HoneyColour.of(jar.honey)
        let c = canvas, fx = Double(x), fy = (Double(y) - lift).rounded()
        c.fill(fx + 1, Double(y + 17), 10, 1, C.shadow, alpha: 0.3)
        c.fill(fx + 1, fy, 10, 3, C.lid)
        for i in 0..<10 { for k in 0..<3 where (i + k) % 2 == 0 { c.fill(fx + 1 + Double(i), fy + Double(k), 1, 1, C.cloth) } }
        c.fill(fx, fy + 2, 12, 1, C.lidDark)
        c.fill(fx + 2, fy + 3, 8, 1, C.string)
        c.fill(fx + 1, fy + 4, 10, 1, C.glass)
        c.fill(fx, fy + 5, 12, 12, honey.body)
        for (dx, dy) in [(0, 5), (11, 5), (0, 16), (11, 16)] { c.fill(fx + Double(dx), fy + Double(dy), 1, 1, C.wall) }
        c.fill(fx + 10, fy + 6, 1, 10, honey.deep); c.fill(fx + 1, fy + 15, 10, 1, honey.deep)
        c.fill(fx + 2, fy + 6, 1, 7, honey.hi)
        c.fill(fx + 3, fy + 8, 7, 5, C.label); c.fill(fx + 4, fy + 10, 5, 1, C.ink)
        guard newest else { return }
        let t = (time * 1.2).truncatingRemainder(dividingBy: 3)
        if t < 0.25 { c.fill(fx + 9, fy + 3, 1, 3, C.sparkle); c.fill(fx + 8, fy + 4, 3, 1, C.sparkle) }
        else if t < 0.5 { c.fill(fx + 9, fy + 4, 1, 1, C.sparkle) }
    }

    private func drawTooltip(_ jar: Jar, at pos: (x: Int, y: Int)) {
        let line1 = jar.hiveName.map { "\(jar.honey) · \($0)" } ?? "\(jar.honey) honey"
        let line2 = formatter.string(from: jar.collectedAt)
        let w = max(PixelFont.width(line1), PixelFont.width(line2)) + 10, h = 20
        let x = Double(min(Layout.width - w - 3, max(3, pos.x - 4))), y = Double(max(21, pos.y - h - 4))
        canvas.fill(x - 1, y - 1, w + 2, h + 2, C.tipText)
        canvas.fill(x, y, w, h, C.label)
        PixelFont.draw(line1, on: canvas, x: Int(x) + 5, y: Int(y) + 4, colour: C.tipText)
        PixelFont.draw(line2, on: canvas, x: Int(x) + 5, y: Int(y) + 11, colour: C.ink.mixed(with: C.tipText, 0.5))
    }
}
