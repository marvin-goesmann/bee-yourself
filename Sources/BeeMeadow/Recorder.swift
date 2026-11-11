import AppKit

@MainActor
enum Recorder {
    private typealias P = (x: Double, y: Double)

    private enum Step {
        case wait(Double)
        case move(Double, () -> P)
        case click
        case release
    }

    private static let fps = 30.0
    private static let dt = 1 / fps

    private static let minuteKeys: [(t: Double, minute: Double)] = [
        (0, 5), (6, 9), (20, 24), (34, 40), (44, 53), (50, 60), (60, 64),
    ]

    private static let arrow = [
        "X.......",
        "XX......",
        "XWX.....",
        "XWWX....",
        "XWWWX...",
        "XWWWWX..",
        "XWWWWWX.",
        "XWWWXXXX",
        "XWXWX...",
        "XX.XWX..",
        "X...XX..",
    ]

    static func run(to directory: String) {
        try? FileManager.default.removeItem(atPath: directory)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        Widgets.inset = 0
        Clock.fixedMinute = minute(at: 0)
        let world = demoWorld()
        let view = SceneView(world: world, currentGarden: 0)
        let steps = script(world: world, view: view)
        view.wake()

        var cursor: P = (250, 150)
        var index = 0, stepTime = 0.0, from = cursor, frame = 0, clickAge = 9.0
        var time = 40.0
        while index < steps.count {
            let t = Double(frame) * dt
            Clock.fixedMinute = minute(at: t)
            switch steps[index] {
            case .wait(let d):
                stepTime += dt
                if stepTime >= d { index += 1; stepTime = 0 }
            case .move(let d, let target):
                if stepTime == 0 { from = cursor }
                stepTime += dt
                let k = Clock.smooth(0, 1, min(1, stepTime / d)), to = target()
                cursor = (from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k)
                if stepTime >= d { index += 1; stepTime = 0 }
            case .click:
                view.click(cursor)
                clickAge = 0
                index += 1
                continue
            case .release:
                view.release(cursor)
                index += 1
                continue
            }
            view.mouse = cursor
            guard let canvas = view.step(dt: dt, minute: Clock.fixedMinute ?? 30, time: time) else { break }
            drawCursor(canvas, at: cursor, clickAge: clickAge)
            clickAge += dt
            time += dt
            if let image = canvas.makeImage() {
                let path = String(format: "%@/f%05d.png", directory, frame)
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            frame += 1
        }
        print("Wrote \(frame) frames (\(String(format: "%.1f", Double(frame) / fps))s)")
    }

    private static func script(world: World, view: SceneView) -> [Step] {
        let hive = world.hives[1]
        let hiveSpot: P = (Double(hive.x + 9), Double(hive.y - 14))
        func centre(_ r: PixelRect) -> P { (Double(r.x) + Double(r.w) / 2, Double(r.y) + Double(r.h) / 2) }
        let back = centre((0, 2, 40, 14))
        let newPlot = world.freePlots().first { $0 != 4 } ?? 0
        return [
            .wait(4.5),
            .move(1.3, { hiveSpot }), .wait(0.4), .click, .release,
            .wait(1.6),
            .move(1.0, { centre(HiveRenderer.collectRect) }), .wait(0.3), .click,
            .wait(2.0),
            .move(1.0, { back }), .wait(0.3), .click,
            .wait(1.6),
            .move(1.1, { centre(Widgets.pantryRect) }), .wait(0.3), .click,
            .wait(0.6), .move(1.2, { (70, 80) }), .wait(0.6), .move(1.2, { (150, 110) }), .wait(1.0),
            .move(1.1, { back }), .wait(0.3), .click,
            .wait(1.4),
            .move(1.0, { centre(Widgets.mapRect) }), .wait(0.3), .click,
            .wait(1.0), .move(1.2, { centre(ValleyRenderer.stallRect) }), .wait(0.4), .click,
            .wait(0.8), .move(1.0, { centre(StallRenderer.tradeRect) }), .wait(0.3), .click,
            .wait(1.8),
            .move(1.0, { centre(StallRenderer.valleyRect) }), .wait(0.3), .click,
            .wait(0.6), .move(1.2, { centre(ValleyRenderer.plotRect(newPlot)) }), .wait(0.4), .click,
            .wait(0.6), .move(1.0, { centre(StallRenderer.pickerRect(1)) }), .wait(0.5), .move(0.8, { centre(StallRenderer.pickerRect(3)) }), .wait(0.5), .click,
            .wait(2.2),
            .move(1.0, { centre(Widgets.shedRect) }), .wait(0.3), .click,
            .wait(0.8), .move(0.9, { centre(view.shedLayout().rows[0].rect) }), .wait(0.4), .click,
            .move(1.2, { (70, 150) }), .wait(0.4), .click,
            .wait(3.0),
            .move(1.0, { centre(Widgets.mapRect) }), .wait(0.3), .click,
            .wait(0.6), .move(1.1, { centre(ValleyRenderer.plotRect(4)) }), .wait(0.4), .click,
            .wait(4.0),
            .move(1.2, { centre(Widgets.bedRect) }), .wait(0.5), .click,
            .wait(1.6),
        ]
    }

    private static func minute(at t: Double) -> Double {
        guard let next = minuteKeys.firstIndex(where: { $0.t > t }) else { return minuteKeys.last?.minute ?? 30 }
        guard next > 0 else { return minuteKeys[0].minute }
        let a = minuteKeys[next - 1], b = minuteKeys[next]
        return a.minute + (b.minute - a.minute) * (t - a.t) / (b.t - a.t)
    }

    private static func demoWorld() -> World {
        let world = World.fresh()
        world.hornetsEnabled = false
        world.jars = (0..<34).map { i in
            Jar(honey: ["Clover", "Clover", "Heather"][i % 3], hiveName: "Pip", collectedAt: Date().addingTimeInterval(Double(i - 34) * 3000))
        }
        world.harvests = world.jars
        if let heather = world.buyGarden(kind: .heather, plot: 1) {
            world.spareBoxes += 2
            _ = world.placeBox(x: 24, y: 150, in: heather.id)
            _ = world.placeBox(x: 64, y: 136, in: heather.id)
        }
        world.jars += (0..<10).map { _ in Jar(honey: "Heather", hiveName: "Bo", collectedAt: Date()) }
        for i in 0..<1200 { world.tick(dt, minute: 20, time: Double(i) * dt, visibleGarden: 0) }
        world.hives[1].honey = 1
        world.puffs.removeAll()
        return world
    }

    private static func drawCursor(_ canvas: PixelCanvas, at p: P, clickAge: Double) {
        canvas.tint = .white
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        if clickAge < 0.3 {
            let r = 2 + clickAge * 14, ring = RGB("#fff2c0")
            for k in 0..<12 {
                let a = Double(k) / 12 * 2 * .pi
                canvas.pixel(x + Int((cos(a) * r).rounded()), y + Int((sin(a) * r).rounded()), ring)
            }
        }
        let outline = RGB("#3b2416"), fill = RGB("#fff8e6")
        for (row, line) in arrow.enumerated() {
            for (col, ch) in line.enumerated() {
                switch ch {
                case "X": canvas.pixel(x + col, y + row, outline)
                case "W": canvas.pixel(x + col, y + row, fill)
                default: break
                }
            }
        }
    }
}
