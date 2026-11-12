#if canImport(AppKit)
import AppKit

enum Snapshot {
    private static let scale = 3

    static func write(to path: String, minute: Double, scene: String) {
        Clock.fixedMinute = minute
        let world = demoWorld()
        let dt = 1.0 / 30
        for i in 0..<900 { world.tick(dt, minute: minute, time: Double(i) * dt, visibleGarden: nil) }
        let canvas: PixelCanvas
        if scene.hasPrefix("garden-"), let kind = GardenKind(rawValue: String(scene.dropFirst(7))) {
            let garden = world.gardens.first { $0.kind == kind } ?? world.gardens[0]
            let renderer = GardenRenderer()
            renderer.render(world, garden: garden, minute: minute, time: 30, ghost: nil, hover: nil)
            canvas = renderer.canvas
            if Clock.canSleep(minute) { Widgets.bedIcon(canvas, lifted: false) }
        } else {
            switch scene {
            case "hive":
                world.hives[0].honey = 1
                let hive = HiveRenderer()
                hive.open(hive: 0, world: world)
                for i in 0..<300 {
                    world.tick(dt, minute: minute, time: 30 + Double(i) * dt, visibleGarden: nil)
                    hive.render(world, minute: minute, time: 30 + Double(i) * dt, dt: dt)
                }
                canvas = hive.canvas
            case "pantry":
                let pantry = PantryRenderer()
                pantry.open(world: world)
                for _ in 0..<20 { pantry.render(world, time: 1, dt: dt, mouse: (40, 140)) }
                canvas = pantry.canvas
            case "book":
                let book = BookRenderer()
                book.render(world)
                canvas = book.canvas
            case "valley":
                let valley = ValleyRenderer()
                valley.render(world, minute: minute, time: 3, current: 0, hover: nil)
                canvas = valley.canvas
            case "stall":
                let stall = StallRenderer()
                stall.renderStall(world, time: 1, dt: dt)
                canvas = stall.canvas
            case "picker":
                let stall = StallRenderer()
                stall.renderPicker(world, time: 1, dt: dt, hover: (50, 60))
                canvas = stall.canvas
            default:
                world.hives[1].honey = 1
                let renderer = GardenRenderer()
                renderer.render(world, garden: world.gardens[0], minute: minute, time: 30, ghost: nil, hover: nil)
                canvas = renderer.canvas
            }
        }
        guard let image = canvas.makeImage() else { return }
        let w = Layout.width * scale, h = Layout.height * scale
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func demoWorld() -> World {
        let world = World.fresh()
        world.hornetsEnabled = false
        let honeys = GardenKind.allCases.map(\.honeyName)
        world.jars = (0..<120).map { i in Jar(honey: honeys[(i * 7 + 2) % honeys.count], hiveName: "Pip", collectedAt: Date().addingTimeInterval(Double(i - 120) * 3000)) }
        world.harvests = world.jars
        for kind in GardenKind.allCases.dropFirst() {
            if let garden = world.buyGarden(kind: kind, plot: world.freePlots()[0]) {
                world.spareBoxes += 1
                _ = world.placeBox(x: 30, y: 150, in: garden.id)
            }
        }
        return world
    }

    static func calibrate() {
        Clock.fixedMinute = 30
        let world = World.fresh()
        world.hornetsEnabled = false
        let dt = 0.1, warm = 600, measured = 6000
        for i in 0..<warm { world.tick(dt, minute: 30, time: Double(i) * dt, visibleGarden: nil) }
        world.completedTrips = 0
        let start = world.hives.map(\.honey)
        for i in 0..<measured { world.tick(dt, minute: 30, time: Double(i) * dt, visibleGarden: nil) }
        let minutes = Double(measured) * dt / 60
        let foragers = Double(world.bees.filter { $0.role == .forager }.count)
        print(String(format: "trips per forager-minute: %.2f", Double(world.completedTrips) / foragers / minutes))
        for (hive, before) in zip(world.hives, start) {
            let rate = (hive.honey - before) / minutes
            print(String(format: "%@: %.1f foraging minutes to fill", hive.name, rate > 0 ? 1 / rate : .infinity))
        }
    }

    static func bench() {
        let dt = 1.0 / 30
        Clock.fixedMinute = 30
        let world = demoWorld()
        let renderer = GardenRenderer()
        for _ in 0..<5 { for g in world.gardens { for _ in 0..<3 { world.spareBoxes += 1; _ = world.placeBox(x: 4 + Int.random(in: 0...90), y: 130 + Int.random(in: 0...40), in: g.id) } } }
        print("hives: \(world.hives.count), bees: \(world.bees.count)")
        var start = CFAbsoluteTimeGetCurrent()
        for i in 0..<300 { world.tick(dt, minute: 30, time: Double(i) * dt, visibleGarden: 0) }
        print(String(format: "tick: %.3f ms", (CFAbsoluteTimeGetCurrent() - start) / 300 * 1000))
        start = CFAbsoluteTimeGetCurrent()
        for i in 0..<300 { renderer.render(world, garden: world.gardens[0], minute: 30 + Double(i) / 300, time: Double(i) * dt, ghost: nil, hover: nil); _ = renderer.canvas.makeImage() }
        print(String(format: "garden render: %.3f ms", (CFAbsoluteTimeGetCurrent() - start) / 300 * 1000))
    }
}
#endif
