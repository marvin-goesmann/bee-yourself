#if canImport(AppKit)
import AppKit

@MainActor
enum Recorder {
    private typealias P = (x: Double, y: Double)

    private enum Step {
        case wait(Double)
        case move(Double, () -> P)
        case click
        case release
        case day(Double)
    }

    private static let fps = 30.0
    private static let dt = 1 / fps

    nonisolated(unsafe) private static var minuteKeys: [(t: Double, minute: Double)] = [(0, 5)]

    static func run(to directory: String) {
        try? FileManager.default.removeItem(atPath: directory)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        Widgets.inset = 0
        Clock.fixedMinute = minute(at: 0)
        let world = demoWorld()
        let view = Game(world: world, currentGarden: 0)
        let steps = script(world: world, view: view)
        minuteKeys = keys(for: steps)
        view.wake()

        var cursor: P = (120, 90)
        var index = 0, stepTime = 0.0, frame = 0, clickAge = 9.0, hovering = false
        var time = 40.0
        while index < steps.count {
            let t = Double(frame) * dt
            Clock.fixedMinute = minute(at: t)
            switch steps[index] {
            case .wait(let d):
                stepTime += dt
                if stepTime >= d { index += 1; stepTime = 0 }
            case .move(let d, let target):
                stepTime += dt
                if stepTime >= d { cursor = target(); hovering = true; index += 1; stepTime = 0 }
            case .click:
                view.click(cursor)
                clickAge = 0
                index += 1
                continue
            case .release:
                view.release(cursor)
                index += 1
                continue
            case .day:
                index += 1
                continue
            }
            if clickAge > 0.25 && clickAge < 0.25 + dt * 1.5 { hovering = false }
            view.mouse = hovering ? cursor : nil
            guard let canvas = view.step(dt: dt, minute: Clock.fixedMinute ?? 30, time: time) else { break }
            drawRipple(canvas, at: cursor, clickAge: clickAge)
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

    private static func script(world: World, view: Game) -> [Step] {
        let hive = world.hives[1]
        let hiveSpot: P = (Double(hive.x + 9), Double(hive.y - 14))
        func centre(_ r: PixelRect) -> P { (Double(r.x) + Double(r.w) / 2, Double(r.y) + Double(r.h) / 2) }
        let back = centre((0, 2, 40, 14))
        let newPlot = world.freePlots().first { $0 != 4 } ?? 0
        return [
            .day(5),
            .wait(9.0), .day(14),
            .move(0.5, { hiveSpot }), .wait(0.4), .click, .release,
            .wait(1.6),
            .move(0.5, { centre(HiveRenderer.collectRect) }), .wait(0.5), .click,
            .wait(2.0),
            .move(0.5, { back }), .wait(0.5), .click,
            .wait(3.2),
            .move(0.5, { centre(Widgets.pantryRect) }), .wait(0.5), .click,
            .wait(0.6), .move(0.5, { (70, 80) }), .wait(0.6), .move(0.5, { (150, 110) }), .wait(1.0),
            .move(0.5, { back }), .wait(0.5), .click,
            .wait(2.8),
            .move(0.5, { centre(Widgets.mapRect) }), .wait(0.5), .click, .day(26),
            .wait(1.0), .move(0.5, { centre(ValleyRenderer.stallRect) }), .wait(0.4), .click,
            .wait(0.8), .move(0.5, { centre(StallRenderer.tradeRect) }), .wait(0.5), .click,
            .wait(1.8),
            .move(0.5, { centre(StallRenderer.valleyRect) }), .wait(0.5), .click,
            .wait(0.6), .move(0.5, { centre(ValleyRenderer.plotRect(newPlot)) }), .wait(0.4), .click,
            .wait(0.6), .move(0.5, { centre(StallRenderer.pickerRect(1)) }), .wait(0.5), .move(0.5, { centre(StallRenderer.pickerRect(3)) }), .wait(0.5), .click, .day(38),
            .wait(4.4),
            .move(0.5, { centre(Widgets.shedRect) }), .wait(0.5), .click,
            .wait(0.8), .move(0.5, { centre(view.shedLayout().rows[0].rect) }), .wait(0.4), .click,
            .move(0.5, { (70, 150) }), .wait(0.4), .click,
            .wait(6.0), .day(54),
            .move(0.5, { centre(Widgets.mapRect) }), .wait(0.5), .click,
            .wait(0.6), .move(0.5, { centre(ValleyRenderer.plotRect(4)) }), .wait(0.4), .click, .day(60),
            .wait(8.0),
            .move(0.5, { centre(Widgets.bedRect) }), .wait(0.5), .click,
            .wait(1.6), .day(65),
        ]
    }

    private static func keys(for steps: [Step]) -> [(t: Double, minute: Double)] {
        var t = 0.0, keys: [(t: Double, minute: Double)] = []
        for step in steps {
            switch step {
            case .wait(let d), .move(let d, _): t += d
            case .day(let m): keys.append((t, m))
            case .click, .release: break
            }
        }
        return keys
    }

    private static func minute(at t: Double) -> Double {
        guard let next = minuteKeys.firstIndex(where: { $0.t > t }) else { return minuteKeys.last?.minute ?? 30 }
        guard next > 0 else { return minuteKeys[0].minute }
        let a = minuteKeys[next - 1], b = minuteKeys[next]
        return a.minute + (b.minute - a.minute) * (t - a.t) / (b.t - a.t)
    }

    private static func demoWorld() -> World {
        let world = World.classic()
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

    private static func drawRipple(_ canvas: PixelCanvas, at p: P, clickAge: Double) {
        guard clickAge < 0.35 else { return }
        canvas.tint = .white
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        let r = 2 + clickAge * 16, ring = RGB("#fff2c0")
        for k in 0..<14 {
            let a = Double(k) / 14 * 2 * .pi
            canvas.pixel(x + Int((cos(a) * r).rounded()), y + Int((sin(a) * r).rounded()), ring, alpha: 1 - clickAge / 0.35)
        }
    }
}
#endif
