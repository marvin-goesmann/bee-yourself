#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

final class BookRenderer {
    private static let lineHeight = 9
    private static let visibleLines = 15
    private static let jarsPerLine = 26

    private enum C {
        static let desk = RGB("#4a2e18"), page = RGB("#f4e6c8"), pageEdge = RGB("#e2cfa6"), rule = RGB("#e6d4ae")
        static let ink = RGB("#4a2c14"), muted = RGB("#8a6a44"), spine = RGB("#8a3a2a")
    }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private var scroll = 0
    func open() { scroll = 0 }

    func scroll(by delta: Int, world: World) {
        scroll = min(max(0, lines(world).count - BookRenderer.visibleLines), max(0, scroll + delta))
    }

    private func lines(_ world: World) -> [(label: String?, jars: ArraySlice<Jar>)] {
        let days = Dictionary(grouping: world.harvests) { LocalDate.startOfDay($0.collectedAt) }
        var result: [(String?, ArraySlice<Jar>)] = []
        for day in days.keys.sorted(by: >) {
            let jars = days[day] ?? []
            var start = 0
            while start < jars.count {
                let end = min(jars.count, start + BookRenderer.jarsPerLine)
                result.append((start == 0 ? LocalDate.day(day) : nil, jars[start..<end]))
                start = end
            }
        }
        return result
    }

    func render(_ world: World) {
        let c = canvas
        c.tint = .white
        c.fill(0, 0, Layout.width, Layout.height, C.desk)
        c.fill(10, 26, 220, 148, C.pageEdge)
        c.fill(11, 25, 218, 148, C.page)
        c.fill(8, 24, 3, 152, C.spine)
        let all = lines(world)
        for i in 0..<BookRenderer.visibleLines {
            let y = 34 + i * BookRenderer.lineHeight
            c.fill(16, Double(y + 7), 208, 1, C.rule)
            guard scroll + i < all.count else { continue }
            let line = all[scroll + i]
            if let label = line.label { PixelFont.draw(label, on: c, x: 16, y: y, colour: C.ink) }
            for (k, jar) in line.jars.enumerated() { Widgets.jar(c, honey: jar.honey, x: Double(96 + k * 5), y: Double(y), small: true) }
        }
        if all.isEmpty { PixelFont.draw("no harvests yet", on: c, x: (Layout.width - PixelFont.width("no harvests yet")) / 2, y: 90, colour: C.muted) }
        let total = world.harvests.count
        Widgets.header(c, title: "Harvest book", detail: total == 1 ? "1 jar in all" : "\(total) jars in all")
    }
}
