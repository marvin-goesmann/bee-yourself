#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

enum FactoryArt {
    static let size = (w: 40, h: 26)

    private enum C {
        static let brick = RGB("#b85c3c"), brickLight = RGB("#d0744e"), mortar = RGB("#9c4a32"), roof = RGB("#5a3a2e")
        static let chimney = RGB("#a04e36"), cap = RGB("#3b2416"), frame = RGB("#3b2416"), glow = RGB("#ffc24a"), glowHi = RGB("#ffe08a")
        static let door = RGB("#3b2416"), doorInside = RGB("#5a3a22"), pipe = RGB("#c8a070"), pipeDark = RGB("#8a6a44")
        static let sign = RGB("#e8d0a0"), smoke = RGB("#ece6de"), honey = RGB("#e8961e"), lamplight = RGB("#ffd68c")
    }

    static func draw(_ c: PixelCanvas, x: Int, y: Int, scale s: Int, time: Double) {
        func r(_ ux: Int, _ uy: Int, _ uw: Int, _ uh: Int, _ colour: RGB) {
            c.fill(Double(x + ux * s), Double(y + uy * s), uw * s, uh * s, colour)
        }
        r(5, 0, 4, 11, C.chimney); r(4, 0, 6, 1, C.cap)
        r(12, 3, 3, 8, C.chimney); r(11, 3, 5, 1, C.cap)
        r(2, 8, 16, 2, C.roof)
        for tooth in 0..<4 {
            let tx = 18 + tooth * 5
            for k in 0..<4 { r(tx + k, 9 - k, 1, k + 1, C.roof) }
            r(tx + 4, 5, 1, 5, C.glowHi)
        }
        r(2, 10, 36, 16, C.brick)
        r(2, 10, 36, 1, C.brickLight)
        for row in stride(from: 13, to: 26, by: 3) { r(2, row, 36, 1, C.mortar) }
        for i in 0..<4 {
            let flicker = 0.5 + 0.5 * sin(time * 3 + Double(i) * 1.9)
            r(5 + i * 8, 13, 5, 5, C.frame)
            r(6 + i * 8, 14, 3, 3, C.glow.mixed(with: C.glowHi, flicker))
        }
        r(17, 19, 6, 7, C.door); r(18, 20, 4, 6, C.doorInside)
        r(26, 20, 9, 4, C.frame); r(26, 20, 9, 3, C.sign)
        if s >= 3 { PixelFont.draw("HONEY", on: c, x: x + 26 * s + (9 * s - PixelFont.width("HONEY")) / 2, y: y + 20 * s + 2, colour: C.frame) }
        r(38, 14, 2, 2, C.pipe); r(39, 16, 1, 8, C.pipe); r(39, 23, 1, 1, C.pipeDark)
        let drip = (time * 0.8).truncatingRemainder(dividingBy: 1)
        c.fill(Double(x + 39 * s), Double(y + 24 * s) + drip * Double(2 * s), s, s, C.honey, alpha: 1 - drip)
        smoke(c, x: x + 7 * s, y: y, scale: s, time: time, seed: 0)
        smoke(c, x: x + 13 * s, y: y + 3 * s, scale: s, time: time, seed: 1)
    }

    static func lights(_ c: PixelCanvas, x: Int, y: Int, scale s: Int, time: Double, strength: Double) {
        guard strength > 0 else { return }
        let tint = c.tint, k = Double(s), cx = Double(x), cy = Double(y)
        c.tint = .white
        func r(_ ux: Int, _ uy: Int, _ uw: Int, _ uh: Int, _ colour: RGB, alpha: Double = 1) {
            c.fill(Double(x + ux * s), Double(y + uy * s), uw * s, uh * s, colour, alpha: alpha)
        }
        let base = cy + 26 * k
        for dy in 0..<Int(14 * k) {
            let fade = 1 - Double(dy) / (14 * k), w = Int(36 * k * (0.5 + 0.5 * fade))
            c.fill(cx + 20 * k - Double(w / 2), base + Double(dy), w, 1, C.lamplight, alpha: 0.28 * strength * fade)
        }
        for i in 0..<4 {
            let wx = cx + (7.5 + Double(i * 8)) * k, wy = cy + 15.5 * k
            for ring in 0..<5 { c.disc(wx, wy, radius: (2.5 + Double(ring)) * k, C.lamplight, alpha: 0.045 * strength) }
        }
        for tooth in 0..<4 {
            for ring in 0..<3 { c.disc(cx + Double(22 + tooth * 5) * k, cy + 7 * k, radius: (1 + Double(ring)) * k, C.lamplight, alpha: 0.04 * strength) }
        }
        for i in 0..<4 {
            let flicker = 0.5 + 0.5 * sin(time * 3 + Double(i) * 1.9)
            r(6 + i * 8, 14, 3, 3, C.glow.mixed(with: C.glowHi, flicker), alpha: strength)
        }
        for tooth in 0..<4 { r(22 + tooth * 5, 5, 1, 5, C.glowHi, alpha: strength) }
        r(18, 20, 4, 6, C.lamplight.mixed(with: C.glow, 0.4), alpha: strength * 0.85)
        c.tint = tint
    }

    private static func smoke(_ c: PixelCanvas, x: Int, y: Int, scale s: Int, time: Double, seed: Int) {
        for k in 0..<4 {
            let phase = (time * 0.3 + Double(k) / 4 + Double(seed) * 0.13).truncatingRemainder(dividingBy: 1)
            let px = Double(x) + phase * 10 * Double(s) + sin(time + Double(k)) * Double(s) * 0.5
            let py = Double(y) - phase * 9 * Double(s) - Double(s)
            let radius = max(0.6, (0.6 + phase * 1.6) * Double(s))
            c.disc(px, py, radius: radius, C.smoke, alpha: 0.75 * (1 - phase))
        }
    }

    static func tiny(_ c: PixelCanvas, x: Int, y: Int) {
        c.fill(Double(x + 2), Double(y), 2, 4, C.chimney)
        c.fill(Double(x), Double(y + 4), 10, 6, C.brick)
        c.fill(Double(x + 1), Double(y + 6), 2, 2, C.glow); c.fill(Double(x + 5), Double(y + 6), 2, 2, C.glow)
    }
}

final class FactoryRenderer {
    static let ground = 116
    static let duration = 4.4
    private static let factoryOrigin = (x: 104, y: ground - FactoryArt.size.h * 3)
    private static let chunk = 8

    private enum C {
        static let yard = RGB("#8c7a58"), yardDark = RGB("#7a6a4a"), yardLight = RGB("#a08c68"), hill = RGB("#9cae6a")
        static let grass = RGB("#7f9c47"), grassDark = RGB("#6c8b3c"), belt = RGB("#4a3a2e"), roller = RGB("#8a6a44")
        static let tent = RGB("#c8a070"), tentDark = RGB("#8a6a44"), log = RGB("#6b4a2e"), flame = RGB("#f2a548"), flameHi = RGB("#ffe08a")
        static let dust = RGB("#a8946c"), dustLight = RGB("#d8c8a0"), rubble = RGB("#5a4a36"), text = RGB("#fff6dc"), shadow = RGB("#3e2816")
    }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private var specks: [(x: Int, y: Int, dark: Bool)] = []
    private var debris: [(x: Int, y: Int, vx: Double, vy: Double, delay: Double)] = []
    private let before = PixelCanvas(width: Layout.width, height: Layout.height)

    init() {
        var r = SeededRandom(seed: 919)
        specks = (0..<180).map { _ in (r.int(Layout.width), FactoryRenderer.ground + 1 + r.int(Layout.height - FactoryRenderer.ground - 1), r.next() < 0.6) }
        let n = FactoryRenderer.chunk
        for y in stride(from: 19, to: Layout.height, by: n) {
            for x in stride(from: 0, to: Layout.width, by: n) {
                let dx = Double(x + n / 2 - Layout.width / 2), dy = Double(y + n / 2 - 100)
                let d = max(1, hypot(dx, dy))
                debris.append((x, y, dx / d * (40 + r.next() * 70), dy / d * 30 - 60 - r.next() * 70, d / 400 + r.next() * 0.15))
            }
        }
    }

    func capture(_ valley: PixelCanvas) { before.copy(from: valley) }

    func render(_ world: World, minute: Double, time: Double, hover: (x: Double, y: Double)?) {
        drawScene(world, minute: minute, time: time, rise: 1)
        let tenths = Int((World.factoryJarsPerMinute * 10).rounded())
        let line = "making \(tenths / 10).\(tenths % 10) jars a minute"
        PixelFont.draw(line, on: canvas, x: (Layout.width - PixelFont.width(line)) / 2, y: 168, colour: C.text, shadow: C.shadow)
        Widgets.header(canvas, title: "Factory", detail: world.jars.count == 1 ? "1 jar" : "\(world.jars.count) jars")
    }

    func renderDemolition(_ world: World, age: Double, minute: Double, time: Double) {
        let c = canvas
        c.tint = .white
        if age < 1 {
            c.fill(0, 19, Layout.width, Layout.height - 19, C.rubble)
            let amp = age * 3
            c.blit(from: before, x: 0, y: 19, w: Layout.width, h: Layout.height - 19, to: Int((sin(age * 70) * amp).rounded()), 19 + Int((cos(age * 53) * amp * 0.6).rounded()))
            var r = SeededRandom(seed: 31)
            for k in 0..<10 {
                let start = 0.3 + Double(k) * 0.06, t = age - start
                let px = 62 + Double(r.int(176)), py = 28 + Double(r.int(140))
                guard t > 0 else { continue }
                c.disc(px, py, radius: 2 + t * 14, C.dust, alpha: max(0, 0.9 - t))
                if t < 0.4 { c.disc(px, py, radius: 1 + t * 12, C.flame, alpha: 1 - t / 0.4) }
                if t < 0.2 { c.disc(px, py, radius: 1 + t * 8, C.flameHi, alpha: 1 - t / 0.2) }
            }
        } else {
            let t = age - 1
            drawScene(world, minute: minute, time: time, rise: Clock.smooth(1.2, 3.0, t))
            for d in debris {
                let tt = t - d.delay
                guard tt > 0 else {
                    c.blit(from: before, x: d.x, y: d.y, w: FactoryRenderer.chunk, h: FactoryRenderer.chunk, to: d.x, d.y)
                    continue
                }
                let x = Double(d.x) + d.vx * tt, y = Double(d.y) + d.vy * tt + 160 * tt * tt
                guard y < Double(Layout.height) else { continue }
                c.blit(from: before, x: d.x, y: d.y, w: FactoryRenderer.chunk, h: FactoryRenderer.chunk, to: Int(x.rounded()), Int(y.rounded()))
            }
            let cloud = max(0, 1 - t / 2.6)
            var r = SeededRandom(seed: 77)
            for _ in 0..<14 {
                let px = Double(r.int(Layout.width)), py = 60 + Double(r.int(120)), grow = 10 + r.next() * 16
                c.disc(px, py - t * 6, radius: 6 + t * grow * 0.6, r.next() < 0.5 ? C.dust : C.dustLight, alpha: 0.55 * cloud)
            }
            if t < 0.35 { c.fill(0, 19, Layout.width, Layout.height - 19, .white, alpha: 0.9 * (1 - t / 0.35)) }
        }
        Widgets.header(c, title: "Factory", detail: nil, back: false)
    }

    private func drawScene(_ world: World, minute: Double, time: Double, rise: Double) {
        let c = canvas, light = Clock.light(at: minute), ground = FactoryRenderer.ground
        c.tint = .white
        let bands = light.sky, bandHeight = Double(ground - 19) / Double(bands.count)
        for (i, colour) in bands.enumerated() { c.fill(0, 19 + Double(i) * bandHeight, Layout.width, Int(bandHeight.rounded(.up)), colour) }
        c.tint = light.tint
        for x in 0..<Layout.width {
            let h = 8 + Int(5 * sin(Double(x) * 0.035 + 1.4) + 3 * sin(Double(x) * 0.09))
            c.fill(Double(x), Double(ground - h), 1, h, C.hill)
        }
        let origin = FactoryRenderer.factoryOrigin
        FactoryArt.draw(c, x: origin.x, y: origin.y + Int(((1 - rise) * Double(FactoryArt.size.h * 3 + 14)).rounded()), scale: 3, time: time)
        c.fill(0, Double(ground), Layout.width, Layout.height - ground, C.yard)
        for s in specks { c.pixel(s.x, s.y, s.dark ? C.yardDark : C.yardLight) }
        c.fill(0, Double(ground), 78, Layout.height - ground, C.grass)
        for s in specks where s.x < 78 { c.pixel(s.x, s.y, C.grassDark) }
        let dark = light.darkness
        if rise >= 1 { FactoryArt.lights(c, x: origin.x, y: origin.y, scale: 3, time: time, strength: dark) }
        drawConveyor(world, minute: minute, time: time, visible: rise >= 1)
        drawCamp(time: time)
        let helpers = world.homelessHelpers.sorted { $0.y < $1.y }
        for helper in helpers { HelperSprite.drawInScene(helper, on: c, time: time, dark: dark) }
        for helper in helpers { HelperSprite.drawGlow(helper, on: c, time: time, dark: dark); HelperSprite.drawHeart(helper, on: c) }
        c.tint = .white
    }

    private func drawConveyor(_ world: World, minute: Double, time: Double, visible: Bool) {
        let c = canvas, y = Double(FactoryRenderer.ground + 8), start = 150
        c.fill(Double(start), y, Layout.width - start, 3, C.belt)
        for x in stride(from: start + 2, to: Layout.width, by: 6) { c.fill(Double(x), y + 3, 2, 2, C.roller) }
        guard visible else { return }
        let speed = 10.0
        for k in 0..<6 {
            let jx = Double(start) + 8 + (time * speed + Double(k) * 15).truncatingRemainder(dividingBy: 90)
            Widgets.jar(c, honey: World.factoryHoneyName, x: jx, y: y - 5, small: true)
        }
    }

    private func drawCamp(time: Double) {
        let c = canvas, tx = 18.0, ty = 136.0
        for k in 0..<14 { c.fill(tx + 13 - Double(k), ty + Double(k), k * 2 + 1, 1, k % 4 == 0 ? C.tentDark : C.tent) }
        c.fill(tx + 11, ty + 8, 5, 6, C.log)
        let fx = 58.0, fy = 160.0
        c.fill(fx - 4, fy + 2, 9, 2, C.log)
        let lick = sin(time * 11) * 0.5 + 0.5
        c.fill(fx - 2, fy - 2, 5, 4, C.flame)
        c.fill(fx - 1, fy - 4 - lick, 3, 3, C.flame)
        c.fill(fx, fy - 2, 1, 3, C.flameHi)
    }
}
