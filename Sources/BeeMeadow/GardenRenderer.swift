#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

final class GardenRenderer {
    struct Ghost {
        let x: Int
        let y: Int
        let valid: Bool
        let hiding: Int?
    }

    private enum P {
        static let wood = RGB("#dba660"), woodLight = RGB("#e8bd7c"), woodShade = RGB("#bb8643"), woodDark = RGB("#8a5a2b")
        static let roof = RGB("#c4573f"), roofLight = RGB("#dc7a5c"), roofShade = RGB("#963d2d")
        static let entrance = RGB("#3b2416"), post = RGB("#6b4a2e")
        static let bee = RGB("#f2b632"), beeLoaded = RGB("#e9862f"), beeDark = RGB("#3b2a1a"), wing = RGB("#fff8e6")
        static let honey = RGB("#e8961e"), honeyHi = RGB("#ffc24a")
        static let glow = RGB("#f1b65e"), lanternLight = RGB("#ffd68c"), lanternCore = RGB("#fff6d2"), firefly = RGB("#fbeaa0")
        static let star = RGB("#d9dcf2"), brightStar = RGB("#fff7e0"), moon = RGB("#f4e6c6"), puff = RGB("#fff4dc")
        static let invalid = RGB("#e06050")
    }

    private struct Speck { let x: Int, y: Int, dark: Bool }
    private struct Star { let x: Int, y: Int, phase: Double, brightness: Double }
    private struct Cloud { var x: Double; let y: Int, width: Int }
    private struct Firefly { var x: Double; let y: Double, phase: Double, drift: Double }
    private enum Prop { case hive(Int), flower(Int), lantern }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private let background = PixelCanvas(width: Layout.width, height: Layout.height)
    private var backgroundKey = (minute: -10.0, garden: -1, layout: -1)
    private let W = Layout.width, H = Layout.height, horizon = Layout.horizon
    private var specks: [Speck] = []
    private var tufts: [(x: Int, y: Int)] = []
    private var stars: [Star] = []
    private var clouds = [Cloud(x: 24, y: 22, width: 30), Cloud(x: 140, y: 34, width: 20), Cloud(x: 200, y: 14, width: 26)]
    private var fireflies: [Firefly] = []
    private var drawOrder: [Prop] = []
    private var orderKey = -1

    init() {
        var r = SeededRandom(seed: 99)
        let groundSpan = H - horizon
        specks = (0..<320).map { _ in Speck(x: r.int(W), y: horizon + 2 + r.int(groundSpan), dark: r.next() < 0.6) }
        tufts = (0..<50).map { _ in (r.int(W), horizon + 4 + r.int(groundSpan - 4)) }
        stars = (0..<48).map { _ in Star(x: r.int(W), y: r.int(84), phase: r.next() * 10, brightness: r.next()) }
        fireflies = (0..<10).map { _ in Firefly(x: 104 + r.next() * 136, y: Double(horizon) + 4 + r.next() * 60, phase: r.next() * 10, drift: r.next() - 0.5) }
    }

    func render(_ world: World, garden: Garden, minute: Double, time: Double, ghost: Ghost?, hover: Int?) {
        let light = Clock.light(at: minute)
        let hives = world.hives(in: garden.id)
        let layout = hives.reduce(hives.count) { $0 &* 31 &+ $1.x &* 7 &+ $1.y } &+ (ghost?.hiding ?? -1)
        if abs(minute - backgroundKey.minute) > 0.05 || backgroundKey.garden != garden.id || backgroundKey.layout != layout {
            drawBackground(garden, hives: hives.filter { $0.id != ghost?.hiding }, light: light, minute: minute)
            backgroundKey = (minute, garden.id, layout)
        }
        canvas.copy(from: background)

        canvas.tint = .white
        let dark = light.darkness
        drawStars(time: time, dark: dark)
        drawClouds(light: light, dark: dark)

        canvas.tint = light.tint
        if orderKey != layout &+ garden.id &* 1000 {
            orderKey = layout &+ garden.id &* 1000
            var props: [(y: Int, prop: Prop)] = hives.map { ($0.y, .hive($0.id)) }
            props += garden.flowers.enumerated().map { ($0.element.y, .flower($0.offset)) }
            props.append((Layout.lantern.y, .lantern))
            drawOrder = props.sorted { $0.y < $1.y }.map(\.prop)
        }
        for prop in drawOrder {
            switch prop {
            case .hive(let id):
                guard id != ghost?.hiding, let hive = world.hive(id) else { continue }
                drawHive(hive, time: time, full: hive.isFull, lifted: hover == id)
            case .flower(let i): drawFlower(garden.kind, garden.flowers[i], time: time)
            case .lantern: drawLanternPost()
            }
        }
        drawBees(world, garden: garden, time: time)
        if let hornet = garden.hornet { drawHornet(hornet, time: time) }
        for puff in world.puffs {
            let r = 1 + (puff.age * 4).rounded(.down), p = puff.position
            canvas.fill(p.x - r, p.y, 1, 1, P.puff); canvas.fill(p.x + r, p.y, 1, 1, P.puff)
            canvas.fill(p.x, p.y - r, 1, 1, P.puff); canvas.fill(p.x, p.y + r, 1, 1, P.puff)
        }
        Widgets.jar(canvas, honey: garden.kind.honeyName, x: Double(Widgets.pantryRect.x + 2), y: Double(Widgets.pantryRect.y + 2))
        Widgets.shedIcon(canvas, count: world.spareBoxes)
        canvas.tint = .white
        drawGlows(world, hives: hives, time: time, dark: dark)
        if let ghost { drawGhost(ghost) }
        Widgets.mapIcon(canvas)
    }

    // MARK: Background

    private func drawBackground(_ garden: Garden, hives: [Hive], light: Clock.Light, minute: Double) {
        let c = background, palette = GroundPalette.of(garden.kind)
        c.tint = .white
        let bands = light.sky, bandHeight = Double(horizon) / Double(bands.count)
        for y in 0..<horizon {
            let f = Double(y) / bandHeight, i = Int(f), frac = f - Double(i)
            for x in 0..<W {
                var idx = i
                if i < bands.count - 1 && frac > 0.72 && (x + y) % 2 == 0 { idx = i + 1 }
                c.pixel(x, y, bands[min(idx, bands.count - 1)])
            }
        }
        drawSun(c, minute: minute)
        drawMoon(c, minute: minute)

        c.tint = light.tint
        drawHill(c, palette.hills[0], amplitude: 12, frequency: 0.04, phase: 1.2 + Double(garden.id), base: 5)
        drawHill(c, palette.hills[1], amplitude: 6, frequency: 0.06, phase: 3.1 + Double(garden.id) * 0.7, base: 3)
        if garden.kind == .yellowBox { drawGumTrees(c) }
        c.fill(0, Double(horizon), W, H - horizon, palette.ground)
        for s in specks { c.pixel(s.x, s.y, s.dark ? palette.groundDark : palette.groundLight) }
        for t in tufts {
            c.pixel(t.x, t.y, palette.grass); c.pixel(t.x - 1, t.y - 1, palette.grass); c.pixel(t.x + 1, t.y - 1, palette.grass)
        }
        if garden.kind == .lavender {
            for row in stride(from: horizon + 14, to: H, by: 12) { c.fill(Double(Layout.flowerMinX - 4), Double(row), W - Layout.flowerMinX + 4, 1, palette.groundDark) }
        }
        for hive in hives {
            c.fill(Double(hive.x - 3), Double(hive.y), 24, 2, palette.shadow)
            c.fill(Double(hive.x - 1), Double(hive.y + 2), 20, 1, palette.shadow)
        }
        c.fill(Double(Layout.lantern.x - 1), Double(Layout.lantern.y), 4, 1, palette.shadow)
    }

    private func drawGumTrees(_ c: PixelCanvas) {
        for (tx, top) in [(150, 30), (196, 22), (226, 40)] {
            let x = Double(tx)
            for y in top..<horizon + 2 { c.fill(x, Double(y), 3, 1, (y / 5) % 3 == 0 ? RGB("#d8ccb4") : RGB("#ece2cc")) }
            c.fill(x + 3, Double(top + 10), 1, horizon - top - 8, RGB("#c4b49a"))
            for (dx, dy, r) in [(-6, -2, 7), (6, 2, 6), (0, -8, 6), (-10, 6, 5), (9, -5, 5)] {
                for yy in -r...r {
                    for xx in -r...r where xx * xx + yy * yy <= r * r && (xx + yy + 64) % 3 != 0 {
                        c.pixel(tx + 1 + dx + xx, top + dy + yy, (xx + yy) % 2 == 0 ? RGB("#8aa088") : RGB("#748c72"))
                    }
                }
            }
        }
    }

    private func drawHill(_ c: PixelCanvas, _ colour: RGB, amplitude: Double, frequency: Double, phase: Double, base: Int) {
        for x in 0..<W {
            let xd = Double(x)
            let rise = (amplitude * (0.5 + 0.5 * sin(xd * frequency + phase)) + 2 * sin(xd * frequency * 2.7 + phase)).rounded()
            let top = horizon - base - Int(rise)
            c.fill(xd, Double(top), 1, horizon - top + 1, colour)
        }
    }

    private func arc(_ m: Double, start: Double, end: Double) -> (x: Double, y: Double, p: Double)? {
        let p = (m - start) / (end - start)
        guard p >= 0, p <= 1 else { return nil }
        return (10 + p * Double(W - 20), Double(horizon) + 6 - sin(Double.pi * p) * 88, p)
    }

    private func drawSun(_ c: PixelCanvas, minute: Double) {
        guard let a = arc(minute, start: 1.5, end: 58.5) else { return }
        let low = Clock.smooth(0.6, 1, 1 - sin(Double.pi * a.p))
        let core = RGB(r: 255, g: 246, b: 220).mixed(with: RGB(r: 255, g: 190, b: 120), low)
        let halo = RGB(r: 252, g: 236, b: 200).mixed(with: RGB(r: 250, g: 170, b: 120), low)
        let cx = Int(a.x.rounded()), cy = Int(a.y.rounded())
        for y in -13...13 {
            for x in -13...13 {
                let d = x * x + y * y
                if d <= 72 { c.pixel(cx + x, cy + y, core) } else if d > 100 && d <= 169 && (x + y) % 2 == 0 { c.pixel(cx + x, cy + y, halo) }
            }
        }
    }

    private func drawMoon(_ c: PixelCanvas, minute: Double) {
        let m = minute < 20 ? minute + Clock.cycleMinutes : minute
        guard let a = arc(m, start: 56, end: 78) else { return }
        let cx = Int(a.x.rounded()), cy = Int(a.y.rounded())
        for y in -7...7 {
            for x in -7...7 {
                let ox = x - 3, oy = y + 2
                if x * x + y * y <= 52 && ox * ox + oy * oy > 52 { c.pixel(cx + x, cy + y, P.moon) }
            }
        }
    }

    // MARK: Sky details

    private func drawStars(time: Double, dark: Double) {
        guard dark > 0.3 else { return }
        for s in stars {
            let twinkle = 0.6 + 0.4 * sin(time * (0.6 + s.brightness) + s.phase)
            if dark * twinkle > 0.35 + s.brightness * 0.3 { canvas.pixel(s.x, s.y, s.brightness > 0.85 && dark > 0.8 ? P.brightStar : P.star) }
        }
    }

    private func drawClouds(light: Clock.Light, dark: Double) {
        let colour = RGB(r: 255, g: 246, b: 230).mixed(with: light.tint, 0.55)
        for i in clouds.indices {
            clouds[i].x += 0.02
            if clouds[i].x > Double(W + 10) { clouds[i].x = -Double(clouds[i].width) - 10 }
            guard dark < 0.85 else { continue }
            let cl = clouds[i]
            canvas.fill(cl.x, Double(cl.y), cl.width, 3, colour)
            canvas.fill(cl.x + 4, Double(cl.y - 2), cl.width - 10, 2, colour)
        }
    }

    // MARK: Props

    private func drawHive(_ hive: Hive, time: Double, full: Bool, lifted: Bool) {
        let x = Double(hive.x), y = Double(hive.y) - (lifted ? 1 : 0)
        drawHiveBox(x: x, y: y)
        guard full else { return }
        let c = canvas
        for (dx, w) in [(1.0, 3), (6.0, 2), (12.0, 4)] { c.fill(x + dx, y - 24, w, 1, P.honey) }
        c.fill(x + 2, y - 23, 1, 1, P.honey)
        c.fill(x + 4, y - 5, 10, 1, P.honey)
        c.fill(x + 5, y - 5, 2, 1, P.honeyHi)
        c.fill(x + 8, Double(hive.y), 3, 1, P.honey)
        c.fill(x + 9, Double(hive.y), 1, 1, P.honeyHi)
        for (dx, offset, period) in [(6.0, 0.0, 3.4), (11.0, 0.45, 4.1), (2.0, 0.2, 5.0)] {
            let phase = (time / period + offset + Double(hive.id) * 0.31).truncatingRemainder(dividingBy: 1)
            let top = dx == 2 ? y - 23 : y - 4, room = dx == 2 ? 3.0 : 3.0
            if phase < 0.75 {
                let length = (phase / 0.75 * room).rounded(.down)
                if length > 0 { c.fill(x + dx, top, 1, Int(length), P.honey) }
                c.fill(x + dx, top + length, 1, 1, P.honeyHi)
            } else if dx != 2 {
                let fall = ((phase - 0.75) / 0.25 * (Double(hive.y) - top - room)).rounded(.down)
                c.fill(x + dx, top + room + fall, 1, 1, P.honeyHi)
            }
        }
    }

    private func drawHiveBox(x: Double, y: Double, colour: RGB? = nil, alpha: Double = 1) {
        let c = canvas
        func f(_ dx: Double, _ dy: Double, _ w: Int, _ h: Int, _ col: RGB) { c.fill(x + dx, y + dy, w, h, colour ?? col, alpha: alpha) }
        f(1, -3, 2, 3, P.woodDark); f(15, -3, 2, 3, P.woodDark); f(-1, -5, 20, 2, P.woodDark)
        f(0, -25, 18, 20, P.wood); f(0, -25, 1, 20, P.woodLight); f(17, -25, 1, 20, P.woodShade)
        f(0, -15, 18, 1, P.woodShade); f(7, -21, 4, 1, P.woodShade); f(7, -11, 4, 1, P.woodShade)
        f(5, -7, 8, 2, P.entrance); f(4, -5, 10, 1, P.woodShade)
        f(-2, -28, 22, 3, P.roof); f(-2, -28, 22, 1, P.roofLight); f(-2, -25, 22, 1, P.roofShade)
    }

    private func drawGhost(_ ghost: Ghost) {
        canvas.tint = .white
        drawHiveBox(x: Double(ghost.x), y: Double(ghost.y), colour: ghost.valid ? nil : P.invalid, alpha: ghost.valid ? 0.75 : 0.45)
    }

    private func drawFlower(_ kind: GardenKind, _ f: Flower, time: Double) {
        let c = canvas, x = Double(f.x), y = Double(f.y), h = Double(f.height)
        let sway = sin(time * 0.7 + f.phase) > 0.6 ? 1.0 : 0
        let stem = RGB("#4f7230")
        switch kind {
        case .clover:
            c.fill(x + 1, y - h, 1, f.height, stem)
            c.fill(x + 2, y - (h / 2).rounded(.down), 1, 1, stem)
            if f.height > 6 { c.fill(x, y - (h / 2).rounded(.down) - 1, 1, 1, stem) }
            let hx = x - 1 + sway, hy = y - h - 4
            c.fill(hx + 1, hy, 2, 1, f.petal); c.fill(hx, hy + 1, 4, 2, f.petal); c.fill(hx + 1, hy + 3, 2, 1, f.petal)
            c.fill(hx + 1, hy + 1, 2, 2, f.centre)
        case .heather:
            let top = y - h - 4
            c.fill(x - 2, top + 3, 7, Int(y - top - 3), RGB("#3f5a34"))
            c.fill(x - 1, top + 2, 5, 1, RGB("#3f5a34"))
            for dy in 0..<Int(y - top - 2) {
                for dx in -2...4 where (dx + dy + f.x) % 2 == 0 && dy < 5 {
                    c.fill(x + Double(dx), top + 1 + Double(dy), 1, 1, dy < 2 ? f.centre : f.petal)
                }
            }
            c.fill(x + sway, top, 2, 1, f.centre)
        case .bramble:
            let cane = RGB("#4a5a2a")
            c.fill(x, y - h, 1, f.height, cane)
            c.fill(x + 1, y - h - 1, 2, 1, cane); c.fill(x + 3, y - h, 1, 2, cane)
            c.fill(x - 1, y - h + 3, 1, 1, RGB("#5f8a3a")); c.fill(x + 1, y - h + 5, 2, 1, RGB("#5f8a3a"))
            let hx = x + sway, hy = y - h - 4
            if f.petal == RGB("#5a2a4a") {
                c.fill(hx, hy + 1, 2, 2, f.petal); c.fill(hx + 2, hy + 2, 2, 2, f.centre); c.fill(hx, hy + 1, 1, 1, RGB("#8a4a7a"))
            } else {
                c.fill(hx + 1, hy, 1, 1, f.petal); c.fill(hx, hy + 1, 3, 1, f.petal); c.fill(hx + 1, hy + 2, 1, 1, f.petal)
                c.fill(hx - 1, hy + 1, 1, 1, f.petal); c.fill(hx + 3, hy + 1, 1, 1, f.petal); c.fill(hx + 1, hy + 1, 1, 1, f.centre)
            }
        case .lavender:
            for (dx, extra) in [(0.0, 0.0), (2.0, -2.0)] {
                let top = y - h - 4 - extra
                c.fill(x + dx, top + 4, 1, Int(y - top - 4), RGB("#6f8a5a"))
                for k in 0..<5 {
                    c.fill(x + dx + (k == 0 ? sway : 0), top + Double(k), 1, 1, k % 2 == 0 ? f.petal : f.centre)
                    if k > 0 && k % 2 == 1 { c.fill(x + dx - 1, top + Double(k), 1, 1, f.petal); c.fill(x + dx + 1, top + Double(k), 1, 1, f.petal) }
                }
            }
        case .yellowBox:
            let top = y - h - 4
            c.fill(x + 1, top + 4, 1, Int(y - top - 4), RGB("#8a7a5a"))
            c.fill(x - 2, top + 2, 7, 4, RGB("#748c72")); c.fill(x - 1, top + 1, 5, 1, RGB("#8aa088")); c.fill(x - 3, top + 3, 1, 2, RGB("#748c72"))
            for (dx, dy) in [(0, 0), (-2, 2), (3, 1), (1, 3)] {
                c.fill(x + Double(dx) + (dx == 0 ? sway : 0), top + Double(dy), 2, 2, f.petal)
                c.fill(x + Double(dx), top + Double(dy), 1, 1, f.centre)
            }
        case .orangeBlossom:
            let top = y - h - 4
            c.fill(x, top + 7, 2, Int(y - top - 7), RGB("#7a5a3a"))
            for yy in 0..<8 {
                let half = [2, 3, 4, 4, 4, 4, 3, 2][yy]
                c.fill(x + 1 - Double(half), top + Double(yy), half * 2, 1, yy < 3 ? RGB("#6a9a4a") : RGB("#4f7a3a"))
            }
            for (dx, dy) in [(-2, 1), (1, 0), (3, 3), (-3, 4), (0, 5)] { c.fill(x + Double(dx) + (dx == 1 ? sway : 0), top + Double(dy), 1, 1, f.petal) }
            if f.centre == RGB("#f08a2a") { c.fill(x + 2, top + 5, 2, 2, f.centre); c.fill(x - 2, top + 3, 1, 1, f.centre) }
        }
    }

    private func drawLanternPost() {
        let c = canvas, x = Double(Layout.lantern.x), y = Double(Layout.lantern.y)
        c.fill(x, y - 16, 2, 16, P.post); c.fill(x, y - 16, 6, 1, P.post); c.fill(x + 4, y - 15, 1, 2, P.post)
        c.fill(x + 3, y - 13, 3, 4, RGB("#4a3a2a")); c.fill(x + 4, y - 12, 1, 2, RGB("#8a7a5a"))
    }

    private func drawBees(_ world: World, garden: Garden, time: Double) {
        let wingUp = Int(time * 14) % 2 == 0
        for bee in world.bees where bee.isOutside {
            guard let hive = world.hive(bee.hive), hive.garden == garden.id else { continue }
            let x = bee.position.x.rounded(), y = bee.position.y.rounded()
            canvas.fill(x, y, 1, 1, bee.isCarrying ? P.beeLoaded : P.bee)
            canvas.fill(x - bee.facing, y, 1, 1, P.beeDark)
            if wingUp { canvas.fill(x, y - 1, 1, 1, P.wing) }
        }
    }

    private func drawHornet(_ h: Hornet, time: Double) {
        let x = h.x.rounded(), y = h.y.rounded(), flip = h.facing < 0
        func px(_ i: Int, _ j: Int, _ col: RGB, _ a: Double = 1) { canvas.fill(flip ? x + Double(i) : x + Double(7 - i), y + Double(j), 1, 1, col, alpha: a) }
        let rows: [[String?]] = [
            ["#d07a22", "#7a3b12", "#7a3b12", "#f0a828", "#2a1a0a", "#f0a828", "#2a1a0a", nil],
            ["#2a1a0a", "#5e2c0c", "#5e2c0c", "#d08c1c", "#2a1a0a", "#d08c1c", "#2a1a0a", "#2a1a0a"],
            [nil, "#2a1a0a", nil, "#2a1a0a", nil, nil, nil, nil],
        ]
        for (j, row) in rows.enumerated() { for (i, col) in row.enumerated() { if let col { px(i, j, RGB(col)) } } }
        let wing = RGB("#e8f0f4")
        if Int(time * 18) % 2 == 0 { px(2, -1, wing, 0.9); px(3, -1, wing, 0.9); px(4, -1, wing, 0.9); px(3, -2, wing, 0.9); px(4, -2, wing, 0.9) }
        else { px(2, -1, wing, 0.9); px(3, -1, wing, 0.9); px(4, -1, wing, 0.9); px(5, -1, wing, 0.9) }
    }

    private func drawGlows(_ world: World, hives: [Hive], time: Double, dark: Double) {
        guard dark > 0.05 else { return }
        let lx = Double(Layout.lantern.x + 4), ly = Double(Layout.lantern.y - 11)
        let k = dark * (0.92 + 0.08 * sin(time * 7) * sin(time * 3.1))
        if k > 0.15 {
            for y in -14...14 { for x in -14...14 where x * x + y * y <= 196 { canvas.fill(lx + Double(x), ly + 10 + Double(y), 1, 1, P.lanternLight, alpha: 0.07 * k) } }
            for y in -7...7 { for x in -7...7 where (x + y) % 2 == 0 && x * x + y * y > 4 && x * x + y * y <= 49 { canvas.fill(lx + Double(x), ly + Double(y), 1, 1, P.lanternLight, alpha: 0.35 * k) } }
            canvas.fill(lx - 1, ly - 1, 3, 4, P.lanternLight, alpha: k)
            canvas.fill(lx, ly, 1, 2, P.lanternCore, alpha: k)
        }
        for hive in hives where world.beeCount(hive: hive.id) > 0 {
            let pulse = 0.8 + 0.2 * sin(time * 0.8 + Double(hive.x))
            canvas.fill(Double(hive.x + 5), Double(hive.y - 7), 8, 2, P.glow, alpha: 0.9 * dark * pulse)
            canvas.fill(Double(hive.x + 4), Double(hive.y - 5), 10, 1, P.glow, alpha: 0.25 * dark * pulse)
        }
        let strength = Clock.smooth(0.55, 0.9, dark)
        guard strength > 0 else { return }
        for i in fireflies.indices {
            fireflies[i].x += fireflies[i].drift * 0.05
            if fireflies[i].x < 100 { fireflies[i].x = Double(W) }
            if fireflies[i].x > Double(W) { fireflies[i].x = 100 }
            let f = fireflies[i], glow = sin(time * 0.9 + f.phase)
            guard glow > 0.3 else { continue }
            let fy = f.y + sin(time * 0.5 + f.phase) * 4
            canvas.fill(f.x, fy, 1, 1, P.firefly, alpha: strength)
            if glow > 0.8 { canvas.fill(f.x - 1, fy, 1, 1, P.firefly, alpha: 0.35 * strength); canvas.fill(f.x + 1, fy, 1, 1, P.firefly, alpha: 0.35 * strength) }
        }
    }
}
