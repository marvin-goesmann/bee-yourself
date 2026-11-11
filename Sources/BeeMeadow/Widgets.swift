import Foundation

typealias PixelRect = (x: Int, y: Int, w: Int, h: Int)

enum Widgets {
    enum C {
        static let strip = RGB("#3e2816"), stripLine = RGB("#5a3a1e")
        static let name = RGB("#f6dfa6"), stats = RGB("#e7c98c"), textShadow = RGB("#1c1108")
        static let button = RGB("#e8b04a"), buttonBright = RGB("#f6c55c"), buttonLight = RGB("#f7d58a"), buttonShade = RGB("#b97f2a")
        static let buttonText = RGB("#4a2c14"), buttonOff = RGB("#a88a62"), buttonOffText = RGB("#6b5236"), outline = RGB("#4a2c14")
        static let paper = RGB("#f4e6c8"), ink = RGB("#8a6a44")
    }

    static var backRect: PixelRect { (inset, 0, 110, 19) }
    nonisolated(unsafe) static var backHovered = false

    static var titleColour: RGB { backHovered ? RGB("#fff8e0") : C.name }
    nonisolated(unsafe) static var inset = 0
    static var mapRect: PixelRect { (inset + 3, 3, 14, 13) }
    static var titleX: Int { inset + 16 }

    static func updateInset(viewWidth: Double) {
        let pointsPerPixel = max(1, viewWidth / Double(Layout.width))
        inset = Int((66 / pointsPerPixel).rounded(.up))
    }
    static let shedRect: PixelRect = (3, 160, 18, 17)
    static let pantryRect: PixelRect = (222, 160, 14, 16)
    static let bedRect: PixelRect = (220, 3, 17, 13)

    static func contains(_ r: PixelRect, _ p: (x: Double, y: Double)) -> Bool {
        p.x >= Double(r.x) && p.x < Double(r.x + r.w) && p.y >= Double(r.y) && p.y < Double(r.y + r.h)
    }

    static func header(_ canvas: PixelCanvas, title: String, detail: String?, back: Bool = true) {
        canvas.tint = .white
        canvas.fill(0, 0, Layout.width, 18, C.strip)
        canvas.fill(0, 18, Layout.width, 1, C.stripLine)
        if back { backArrow(canvas) }
        PixelFont.draw(title, on: canvas, x: back ? titleX : inset + 8, y: 7, colour: back ? titleColour : C.name, shadow: C.textShadow)
        if let detail {
            PixelFont.draw(detail, on: canvas, x: Layout.width - 8 - PixelFont.width(detail), y: 7, colour: C.stats, shadow: C.textShadow)
        }
    }

    static func backArrow(_ canvas: PixelCanvas) {
        let nudge = backHovered ? -1.0 : 0
        for (i, dx) in [2, 1, 0, 1, 2].enumerated() { canvas.fill(Double(inset + 6 + dx) + nudge, Double(7 + i), 2, 1, titleColour) }
    }

    static func button(_ canvas: PixelCanvas, _ r: PixelRect, label: String, enabled: Bool, pulse: Double = 0) {
        let x = Double(r.x), y = Double(r.y)
        let face = enabled ? C.button.mixed(with: C.buttonBright, pulse) : C.buttonOff
        canvas.fill(x - 1, y - 1, r.w + 2, r.h + 2, C.outline)
        canvas.fill(x, y, r.w, r.h, face)
        canvas.fill(x, y, r.w, 1, enabled ? C.buttonLight : face.mixed(with: .white, 0.15))
        canvas.fill(x, y + Double(r.h - 1), r.w, 1, enabled ? C.buttonShade : face.mixed(with: C.outline, 0.25))
        PixelFont.draw(label, on: canvas, x: r.x + (r.w - PixelFont.width(label)) / 2, y: r.y + (r.h - 5) / 2, colour: enabled ? C.buttonText : C.buttonOffText)
    }

    static func note(_ canvas: PixelCanvas, lines: [String], x: Int, y: Int) {
        let w = (lines.map(PixelFont.width).max() ?? 0) + 10, h = lines.count * 7 + 6
        let left = min(Layout.width - w - 3, max(3, x)), top = min(Layout.height - h - 3, max(21, y))
        canvas.fill(Double(left - 1), Double(top - 1), w + 2, h + 2, C.outline)
        canvas.fill(Double(left), Double(top), w, h, C.paper)
        for (i, line) in lines.enumerated() {
            PixelFont.draw(line, on: canvas, x: left + 5, y: top + 4 + i * 7, colour: i == 0 ? C.buttonText : C.ink)
        }
    }

    static func jar(_ canvas: PixelCanvas, honey: String, x: Double, y: Double, small: Bool = false) {
        let colour = HoneyColour.of(honey)
        if small {
            canvas.fill(x, y, 4, 1, RGB("#c4573f"))
            canvas.fill(x, y + 1, 4, 4, colour.body)
            canvas.fill(x + 3, y + 2, 1, 3, colour.deep)
            canvas.fill(x + 1, y + 2, 1, 2, colour.hi)
            return
        }
        canvas.fill(x + 1, y, 8, 2, RGB("#c4573f")); canvas.fill(x + 2, y, 2, 1, RGB("#f2e6d8")); canvas.fill(x + 6, y, 2, 1, RGB("#f2e6d8"))
        canvas.fill(x + 2, y + 2, 6, 1, RGB("#8a5a2b"))
        canvas.fill(x, y + 3, 10, 9, colour.body); canvas.fill(x + 8, y + 4, 1, 7, colour.deep); canvas.fill(x + 1, y + 4, 1, 5, colour.hi)
        canvas.fill(x + 3, y + 6, 4, 3, C.paper)
    }

    static func mapIcon(_ canvas: PixelCanvas) { mapIconAt(canvas, x: mapRect.x + 1, y: mapRect.y + 1) }

    static func mapIconAt(_ canvas: PixelCanvas, x ix: Int, y iy: Int) {
        let x = Double(ix), y = Double(iy)
        canvas.fill(x - 1, y - 1, 14, 12, C.outline)
        canvas.fill(x, y, 4, 10, RGB("#e8d8a8")); canvas.fill(x + 4, y, 4, 10, RGB("#d8c890")); canvas.fill(x + 8, y, 4, 10, RGB("#e8d8a8"))
        canvas.fill(x + 1, y + 3, 2, 2, RGB("#7f9c47")); canvas.fill(x + 5, y + 6, 2, 2, RGB("#a46cc0")); canvas.fill(x + 9, y + 2, 2, 2, RGB("#e8961e"))
        canvas.fill(x + 2, y + 5, 7, 1, RGB("#b08a5a"))
    }

    static func bedIcon(_ canvas: PixelCanvas, lifted: Bool) {
        let x = Double(bedRect.x + 1), y = Double(bedRect.y + 2 - (lifted ? 1 : 0))
        let wood = RGB("#8a5a2b"), woodLight = RGB("#b88446"), woodDark = RGB("#5f3f24")
        let parts: [(Double, Double, Int, Int, RGB)] = [
            (0, 0, 2, 10, wood), (13, 3, 2, 7, wood), (2, 7, 11, 2, woodDark),
            (2, 5, 3, 2, RGB("#f2e6d8")), (2, 3, 4, 2, C.paper),
            (5, 4, 8, 3, RGB("#c4573f")), (5, 4, 8, 1, RGB("#dc7a5c")), (5, 4, 1, 3, RGB("#f2e6d8")),
            (0, 0, 2, 1, woodLight), (13, 3, 2, 1, woodLight),
        ]
        for (dx, dy, w, h, _) in parts { canvas.fill(x + dx - 1, y + dy - 1, w + 2, h + 2, C.outline) }
        for (dx, dy, w, h, colour) in parts { canvas.fill(x + dx, y + dy, w, h, colour) }
    }

    static func tinyHiveBox(_ canvas: PixelCanvas, x ix: Int, y iy: Int, dim: Bool) {
        let x = Double(ix), y = Double(iy)
        let shade: (String) -> RGB = { dim ? RGB($0).mixed(with: C.buttonOff, 0.6) : RGB($0) }
        canvas.fill(x, y, 10, 2, shade("#c4573f")); canvas.fill(x, y, 10, 1, shade("#dc7a5c"))
        canvas.fill(x + 1, y + 2, 8, 7, shade("#dba660")); canvas.fill(x + 8, y + 2, 1, 7, shade("#bb8643"))
        canvas.fill(x + 1, y + 5, 8, 1, shade("#bb8643"))
        canvas.fill(x + 3, y + 7, 4, 1, shade("#3b2416"))
        canvas.fill(x + 1, y + 9, 1, 1, shade("#8a5a2b")); canvas.fill(x + 7, y + 9, 1, 1, shade("#8a5a2b"))
    }

    static func shedIcon(_ canvas: PixelCanvas, count: Int) {
        let r = shedRect, x = Double(r.x + 1), y = Double(r.y + 3)
        canvas.fill(x, y + 4, 14, 9, RGB("#9c6a34")); canvas.fill(x, y + 4, 14, 1, RGB("#b88446"))
        for i in stride(from: 0, to: 14, by: 3) { canvas.fill(x + Double(i), y + 5, 1, 8, RGB("#7e5228")) }
        canvas.fill(x - 1, y + 1, 16, 3, RGB("#c4573f")); canvas.fill(x + 1, y, 12, 1, RGB("#c4573f")); canvas.fill(x - 1, y + 3, 16, 1, RGB("#963d2d"))
        canvas.fill(x + 5, y + 8, 4, 5, RGB("#4a2c14"))
        guard count > 0 else { return }
        let label = "\(count)"
        let w = PixelFont.width(label) + 4
        canvas.fill(x + 11, y - 3, w, 8, C.outline)
        canvas.fill(x + 12, y - 2, w - 2, 6, C.buttonBright)
        PixelFont.draw(label, on: canvas, x: Int(x) + 13, y: Int(y) - 2, colour: C.buttonText)
    }
}
