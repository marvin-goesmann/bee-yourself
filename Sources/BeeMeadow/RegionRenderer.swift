#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

final class RegionRenderer {
    private static let area: PixelRect = (4, 23, 232, 153)
    private static let gap = 3

    private enum C {
        static let land = RGB("#6e8a44"), landDark = RGB("#62803c"), grass = RGB("#8fae58"), grassDark = RGB("#7c9a4c")
        static let locked = RGB("#55693a"), fog = RGB("#3e4a30"), yard = RGB("#8c7a58"), label = RGB("#3e2816")
        static let text = RGB("#fff6dc"), highlight = RGB("#fff2c0"), current = RGB("#ffd257")
    }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)

    static func radius(_ world: World) -> Int { world.openRing + 1 }

    static func tileRect(_ valley: Valley, world: World) -> PixelRect {
        let r = radius(world), n = 2 * r + 1, a = area
        let w = (a.w - (n - 1) * gap) / n, h = (a.h - (n - 1) * gap) / n
        let x0 = a.x + (a.w - (n * w + (n - 1) * gap)) / 2, y0 = a.y + (a.h - (n * h + (n - 1) * gap)) / 2
        return (x0 + (valley.x + r) * (w + gap), y0 + (valley.y + r) * (h + gap), w, h)
    }

    static func valley(at p: (x: Double, y: Double), world: World) -> Valley? {
        let r = radius(world)
        for y in -r...r {
            for x in -r...r {
                let v = Valley(x: x, y: y)
                if Widgets.contains(tileRect(v, world: world), p) { return v }
            }
        }
        return nil
    }

    func render(_ world: World, minute: Double, time: Double, current: Valley?, hover: (x: Double, y: Double)?, back: Bool) {
        let c = canvas, r = RegionRenderer.radius(world)
        c.tint = Clock.light(at: minute).tint.mixed(with: .white, 0.35)
        c.fill(0, 19, Layout.width, Layout.height - 19, C.land)
        for y in stride(from: 21, to: Layout.height, by: 3) { for x in stride(from: (y / 3) % 2 * 3, to: Layout.width, by: 6) { c.pixel(x, y, C.landDark) } }
        let hovered = hover.flatMap { RegionRenderer.valley(at: $0, world: world) }
        for y in -r...r {
            for x in -r...r {
                let v = Valley(x: x, y: y), rect = RegionRenderer.tileRect(v, world: world)
                if v == .home { drawFactory(rect, time: time, dark: Clock.light(at: minute).darkness) }
                else if world.isOpen(v) { drawValley(v, world: world, rect: rect) }
                else { drawLocked(rect) }
                if v == current { outline(rect, C.current) }
                else if v == hovered && (v == .home || world.isOpen(v)) { outline(rect, C.highlight) }
            }
        }
        c.tint = .white
        Widgets.header(c, title: "Map", detail: world.jars.count == 1 ? "1 jar" : "\(world.jars.count) jars", back: back)
    }

    private func outline(_ r: PixelRect, _ colour: RGB) {
        let x = Double(r.x - 1), y = Double(r.y - 1)
        canvas.fill(x, y, r.w + 2, 1, colour); canvas.fill(x, y + Double(r.h + 1), r.w + 2, 1, colour)
        canvas.fill(x, y, 1, r.h + 2, colour); canvas.fill(x + Double(r.w + 1), y, 1, r.h + 2, colour)
    }

    private func drawFactory(_ r: PixelRect, time: Double, dark: Double) {
        canvas.fill(Double(r.x), Double(r.y), r.w, r.h, C.yard)
        let art = FactoryArt.size
        if r.w >= art.w + 2 && r.h >= art.h + 2 {
            let x = r.x + (r.w - art.w) / 2, y = r.y + r.h - art.h - 1
            FactoryArt.draw(canvas, x: x, y: y, scale: 1, time: time)
            FactoryArt.lights(canvas, x: x, y: y, scale: 1, time: time, strength: dark)
        } else {
            FactoryArt.tiny(canvas, x: r.x + (r.w - 10) / 2, y: r.y + (r.h - 10) / 2)
        }
    }

    private func drawValley(_ v: Valley, world: World, rect r: PixelRect) {
        let c = canvas
        c.fill(Double(r.x), Double(r.y), r.w, r.h, C.grass)
        let labelSpace = r.h >= 20 ? 7 : 0
        let cw = (r.w - 4) / 3, ch = (r.h - 4 - labelSpace) / 3
        for plot in 0..<Layout.plots {
            let px = r.x + 2 + (plot % 3) * cw, py = r.y + 2 + (plot / 3) * ch
            if let garden = world.garden(in: v, plot: plot) {
                let palette = GroundPalette.of(garden.kind), colours = garden.kind.sampleColours
                c.fill(Double(px), Double(py), cw - 1, ch - 1, palette.ground)
                c.pixel(px + 1, py + 1, colours[0]); c.pixel(px + cw - 3, py + ch - 3, colours[1 % colours.count])
            } else {
                for yy in stride(from: 0, to: ch - 1, by: 2) { for xx in stride(from: (yy / 2) % 2, to: cw - 1, by: 2) { c.pixel(px + xx, py + yy, C.grassDark) } }
            }
        }
        guard labelSpace > 0 else { return }
        let label = "x\(world.priceMultiplier(in: v))"
        PixelFont.draw(label, on: c, x: r.x + (r.w - PixelFont.width(label)) / 2, y: r.y + r.h - 7, colour: C.text, shadow: C.label)
    }

    private func drawLocked(_ r: PixelRect) {
        canvas.fill(Double(r.x), Double(r.y), r.w, r.h, C.locked)
        for yy in stride(from: 0, to: r.h, by: 3) { canvas.fill(Double(r.x), Double(r.y + yy), r.w, 1, C.fog, alpha: 0.35) }
    }
}
