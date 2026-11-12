#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

final class HiveRenderer {
    static let collectRect: PixelRect = (170, 162, 62, 13)
    static let splitRect: PixelRect = (8, 162, 34, 13)

    private enum C {
        static let wall = RGB("#3f2816"), plankLine = RGB("#36220f"), strip = RGB("#2e1c0e"), stripLine = RGB("#5a3a1e")
        static let bar = RGB("#c99050"), barLight = RGB("#e0ab6a"), barShade = RGB("#9c6a34"), side = RGB("#a8743a")
        static let wax = RGB("#e3b062"), empty = RGB("#7a4e22"), honey = RGB("#e8961e"), honeyHi = RGB("#ffc24a")
        static let capped = RGB("#f3d68a"), cappedShade = RGB("#e2bd68"), brood = RGB("#c48a4e"), broodDot = RGB("#b07a42")
        static let larva = RGB("#f6efe2"), pollen = [RGB("#e8b13a"), RGB("#d9733a"), RGB("#c9c24a"), RGB("#e39a4a")]
        static let bee = RGB("#f2c040"), beeDark = RGB("#3b2a1a"), wing = RGB("#fff4dc"), queen = RGB("#e0a050"), crown = RGB("#ffe066")
        static let sleepy = RGB("#ffe08a"), glow = RGB("#ffb860"), zee = RGB("#fff0c8"), slot = RGB("#140b05")
        static let name = RGB("#f6dfa6"), stats = RGB("#e7c98c"), textShadow = RGB("#1c1108")
        static let button = RGB("#e8b04a"), buttonBright = RGB("#f6c55c"), buttonLight = RGB("#f7d58a"), buttonShade = RGB("#b97f2a")
        static let buttonText = RGB("#4a2c14"), buttonOff = RGB("#a88a62"), buttonOffText = RGB("#6b5236"), outline = RGB("#4a2c14")
        static let toast = RGB("#f4e6c8")
        static let nightTint = RGB("#b8a2c6")
    }

    private enum Kind { case honey, pollen, brood, larva, empty }

    private struct Cell {
        let cx: Int, cy: Int, frame: Int, kind: Kind, pollen: RGB, order: Double
    }

    private struct Frame { let x: Int, y: Int, w: Int, h: Int }

    private enum Mode {
        case walking, entering, leaving, resting
        case emerging(Double)
        case dancing(Double)
        case toBed(Int)
        case sleeping(Int)
    }

    private struct InteriorBee {
        var x: Double, y: Double, tx: Double, ty: Double, pause: Double, frame: Int, mode: Mode, breath: Double
        var dir = 1.0
    }

    private struct Zee { var x: Double, y: Double, age: Double, phase: Double, big: Bool }

    let canvas = PixelCanvas(width: Layout.width, height: Layout.height)
    private let comb = PixelCanvas(width: Layout.width, height: Layout.height)
    private let frames = [12, 92, 172].map { Frame(x: $0, y: 24, w: 56, h: 128) }
    private let entrance = (x: 120.0, y: 157.0)
    private var cells: [Cell] = []
    private var honeyOrder: [Int] = []
    private var combKey = (hive: -1, filled: -1, capped: -1, empty: false)
    private var hiveIndex = -1
    private var interior: [Int: InteriorBee] = [:]
    private var firstSync = true
    private var displayedHoney = 0.0
    private var toast: (text: String, age: Double)?
    private var zees: [Zee] = []
    private var zeeTimer = 0.0
    private var random = SeededRandom(seed: 31337)
    private var queenTarget = (x: 0.0, y: 0.0)

    private func makeCells(seed: Int) {
        var r = SeededRandom(seed: 1000 + seed * 77)
        cells = []
        for (fi, f) in frames.enumerated() {
            let honeyRows = fi == 1 ? 10 : 20
            var row = 0
            while f.y + 5 + row * 3 + 3 <= f.y + f.h - 1 {
                let cy = f.y + 5 + row * 3
                var k = 0
                while f.x + 3 + k * 5 + (row % 2 == 1 ? 2 : 0) + 4 <= f.x + f.w - 2 {
                    let cx = f.x + 3 + k * 5 + (row % 2 == 1 ? 2 : 0)
                    let kind: Kind
                    if row < honeyRows { kind = .honey }
                    else if row < honeyRows + 3 { kind = r.next() < 0.8 ? .pollen : .empty }
                    else if row < 35 { kind = r.next() < 0.82 ? .brood : (r.next() < 0.5 ? .larva : .empty) }
                    else { kind = r.next() < 0.5 ? .pollen : .empty }
                    cells.append(Cell(cx: cx, cy: cy, frame: fi, kind: kind, pollen: C.pollen[r.int(4)], order: Double(row) + r.next() * 6))
                    k += 1
                }
                row += 1
            }
        }
        honeyOrder = cells.indices.filter { cells[$0].kind == .honey }.sorted { cells[$0].order < cells[$1].order }
    }

    func open(hive: Int, world: World) {
        hiveIndex = hive
        makeCells(seed: hive)
        combKey.hive = -1
        interior = [:]
        firstSync = true
        displayedHoney = world.hive(hive)?.honey ?? 0
        toast = nil
        zees = []
        let middle = frames[1]
        queenTarget = (Double(middle.x + 28), Double(middle.y + 80))
    }

    func showCollected(_ honey: String) {
        toast = ("+1 jar of \(honey) honey", 0)
    }

    func showNote(_ text: String) {
        toast = (text, 0)
    }

    func render(_ world: World, minute: Double, time: Double, dt: Double, mouse: (x: Double, y: Double)? = nil) {
        guard let hive = world.hive(hiveIndex) else { return }
        let emptyBox = world.isEmptyBox(hive)
        let dark = Clock.light(at: minute).darkness
        let night = dark > 0.5
        displayedHoney = hive.honey < displayedHoney ? max(hive.honey, displayedHoney - dt * 0.7) : hive.honey

        sync(world, night: night)
        move(dt: dt, time: time, night: night)
        updateZees(dt: dt, night: night)

        drawComb(empty: emptyBox)
        canvas.copy(from: comb)
        canvas.tint = .white
        if world.readyToSplit(hive) { drawQueenCells([(30, 120), (36, 124), (196, 118)]) }
        if hive.queenEmergesIn != nil { drawQueenCells([(118, 112)]) }
        for bee in interior.values {
            switch bee.mode {
            case .sleeping: continue
            case .emerging(let t):
                if let cell = nearestCell(bee) { hex(cells[cell].cx, cells[cell].cy, C.empty) }
                if t > 0.8 { drawBee(bee.x + (sin(time * 30) > 0 ? 0.5 : -0.5), bee.y, dir: bee.dir, resting: false, time: time) }
            default:
                drawBee(bee.x, bee.y, dir: bee.dir, resting: night, time: time)
            }
        }
        drawQueen(world, time: time)

        if dark > 0.02 { applyNight(dark: dark, time: time) }
        for bee in interior.values {
            if case .sleeping(let cell) = bee.mode { drawSleeper(cells[cell], time: time, phase: bee.breath) }
        }
        drawZees()
        drawHeader(world, hive: hive, emptyBox: emptyBox)
        drawButton(ready: hive.isFull && displayedHoney >= 1, time: time)
        if world.readyToSplit(hive) {
            let target = world.splitTarget(for: hive) != nil
            let invite = target && world.atFullStrength(hive)
            Widgets.button(canvas, HiveRenderer.splitRect, label: "Split", enabled: target, pulse: invite ? 0.5 + 0.5 * sin(time * 3.9) : 0)
            if invite { Widgets.ring(canvas, HiveRenderer.splitRect, time: time) }
            if !target, let mouse, Widgets.contains(HiveRenderer.splitRect, mouse) {
                Widgets.note(canvas, lines: ["Needs an empty hive box"], x: HiveRenderer.splitRect.x - 2, y: HiveRenderer.splitRect.y - 19)
            }
        }
        drawToast(dt: dt)
    }

    private func sync(_ world: World, night: Bool) {
        let inside = world.bees.filter { bee in
            guard bee.hive == hiveIndex, bee.role != .queen else { return false }
            if case .relocating(_, let stage, _) = bee.state { return stage == 0 }
            return !bee.isOutside
        }
        var present = Set<Int>()
        for bee in inside {
            present.insert(bee.id)
            guard interior[bee.id] == nil else { continue }
            let frame = random.int(frames.count)
            if let hatched = bee.hatchedAt, world.clock - hatched < 20, let cell = randomCell(frame: frame, kinds: [.brood]) {
                let c = cells[cell]
                interior[bee.id] = InteriorBee(x: Double(c.cx + 1), y: Double(c.cy + 1), tx: Double(c.cx + 1), ty: Double(c.cy + 1), pause: 0, frame: frame, mode: .emerging(0), breath: random.next() * 6)
            } else if firstSync {
                let p = randomSpot(frame: frame)
                interior[bee.id] = InteriorBee(x: p.x, y: p.y, tx: p.x, ty: p.y, pause: random.next() * 2, frame: frame, mode: .walking, breath: random.next() * 6)
            } else {
                let p = randomSpot(frame: frame)
                let dance = bee.role == .forager && random.next() < 0.25 && !night
                interior[bee.id] = InteriorBee(x: entrance.x, y: entrance.y, tx: p.x, ty: dance ? Double(frames[1].y + 50) : p.y, pause: 0, frame: dance ? 1 : frame, mode: dance ? .dancing(-1) : .entering, breath: random.next() * 6)
            }
        }
        let alive = Set(world.bees.map(\.id))
        for (id, bee) in interior where !present.contains(id) {
            if !alive.contains(id) { interior[id] = nil; continue }
            if case .leaving = bee.mode { continue }
            interior[id]?.mode = .leaving
            interior[id]?.tx = entrance.x
            interior[id]?.ty = entrance.y
        }
        firstSync = false
    }

    private func move(dt: Double, time: Double, night: Bool) {
        for (id, var b) in interior {
            switch b.mode {
            case .emerging(let t):
                b.mode = t + dt > 2.2 ? .walking : .emerging(t + dt)
            case .leaving:
                if walk(&b, speed: 12, dt: dt) { interior[id] = nil; continue }
            case .entering:
                if walk(&b, speed: 10, dt: dt) { b.mode = .walking }
            case .dancing(let t):
                if t < 0 {
                    if walk(&b, speed: 10, dt: dt) { b.mode = .dancing(0) }
                } else {
                    let cx = Double(frames[1].x + 22), cy = Double(frames[1].y + 50), cycle = t.truncatingRemainder(dividingBy: 4) / 4
                    if cycle < 0.5 { b.x = cx + cycle * 2 * 12 + sin(time * 40) * 0.8; b.y = cy - cycle * 8 }
                    else {
                        let p = (cycle - 0.5) * 2, side: Double = Int(t / 4) % 2 == 0 ? 1 : -1
                        b.x = cx + 12 - p * 12; b.y = cy - 4 + side * sin(p * .pi) * 5 + p * 4
                    }
                    b.mode = t + dt > 8 ? .walking : .dancing(t + dt)
                }
            case .walking, .resting:
                if night {
                    if b.breath.truncatingRemainder(dividingBy: 1) < 0.6, let cell = randomCell(frame: b.frame, kinds: [.empty, .brood]) {
                        let c = cells[cell]
                        b.tx = Double(c.cx + 1); b.ty = Double(c.cy + 1); b.mode = .toBed(cell)
                    } else { b.mode = .resting }
                    break
                }
                b.mode = .walking
                if b.pause > 0 { b.pause -= dt; break }
                if walk(&b, speed: 4, dt: dt) {
                    let f = frames[b.frame]
                    b.tx = min(Double(f.x + f.w - 6), max(Double(f.x + 3), b.x + (random.next() - 0.5) * 18))
                    b.ty = min(Double(f.y + f.h - 4), max(Double(f.y + 5), b.y + (random.next() - 0.5) * 14))
                    b.pause = random.next() < 0.5 ? 0.5 + random.next() * 2.5 : 0
                }
            case .toBed(let cell):
                if !night { b.mode = .walking; break }
                if walk(&b, speed: 5, dt: dt) { b.mode = .sleeping(cell) }
            case .sleeping:
                if !night { b.mode = .walking; b.pause = random.next() * 3 }
            }
            interior[id] = b
        }
        let middle = frames[1]
        if !night, hypot(queenTarget.x - queenPos.x, queenTarget.y - queenPos.y) < 0.5 {
            queenTarget = (Double(middle.x + 12) + random.next() * 30, Double(middle.y + 60) + random.next() * 40)
        }
        if !night {
            let d = max(0.001, hypot(queenTarget.x - queenPos.x, queenTarget.y - queenPos.y)), step = min(d, 1.5 * dt)
            queenPos.x += (queenTarget.x - queenPos.x) / d * step
            queenPos.y += (queenTarget.y - queenPos.y) / d * step
        }
    }

    private var queenPos = (x: 120.0, y: 104.0)

    private func walk(_ b: inout InteriorBee, speed: Double, dt: Double) -> Bool {
        let d = hypot(b.tx - b.x, b.ty - b.y)
        if d < 0.5 { return true }
        let step = min(d, speed * dt)
        if abs(b.tx - b.x) > 0.3 { b.dir = b.tx > b.x ? 1 : -1 }
        b.x += (b.tx - b.x) / d * step
        b.y += (b.ty - b.y) / d * step
        return false
    }

    private func updateZees(dt: Double, night: Bool) {
        for i in zees.indices { zees[i].age += dt; zees[i].y -= dt * 3 }
        zees.removeAll { $0.age > 3.2 }
        guard night else { return }
        zeeTimer -= dt
        guard zeeTimer <= 0 else { return }
        zeeTimer = 0.7 + random.next() * 0.8
        let sleepers = interior.values.filter { if case .sleeping = $0.mode { return true }; return false }
        guard let b = sleepers.randomElement() else { return }
        zees.append(Zee(x: b.x + 1, y: b.y - 3, age: 0, phase: random.next() * 6, big: random.next() < 0.4))
    }

    private func randomSpot(frame: Int) -> (x: Double, y: Double) {
        let f = frames[frame]
        return (Double(f.x + 4) + random.next() * Double(f.w - 10), Double(f.y + 6) + random.next() * Double(f.h - 12))
    }

    private func randomCell(frame: Int, kinds: Set<Kind>) -> Int? {
        guard !cells.isEmpty else { return nil }
        for _ in 0..<30 {
            let i = random.int(cells.count)
            if cells[i].frame == frame && kinds.contains(cells[i].kind) { return i }
        }
        return nil
    }

    private func nearestCell(_ b: InteriorBee) -> Int? {
        cells.firstIndex { Double($0.cx + 1) == b.tx && Double($0.cy + 1) == b.ty }
    }

    private func drawComb(empty: Bool) {
        let order = honeyOrder
        let filled = Int(displayedHoney * Double(order.count))
        let capped = displayedHoney >= 1 ? filled : Int(Double(filled) * max(0, (displayedHoney - 0.3) / 0.7) * 0.85)
        guard combKey != (hiveIndex, filled, capped, empty) else { return }
        combKey = (hiveIndex, filled, capped, empty)
        let c = comb
        c.tint = .white
        c.fill(0, 0, Layout.width, Layout.height, C.wall)
        var x = 0
        while x < Layout.width { c.fill(Double(x), 18, 1, 138, C.plankLine); x += 10 }
        c.fill(0, 0, Layout.width, 18, C.strip); c.fill(0, 18, Layout.width, 1, C.stripLine)
        c.fill(0, 156, Layout.width, 24, C.strip); c.fill(0, 155, Layout.width, 1, C.stripLine)
        c.fill(104, 157, 32, 3, C.slot)
        for f in frames {
            let fx = Double(f.x), fy = Double(f.y)
            c.fill(fx - 2, fy - 2, f.w + 4, 3, C.bar); c.fill(fx - 2, fy - 2, f.w + 4, 1, C.barLight); c.fill(fx - 2, fy + 1, f.w + 4, 1, C.barShade)
            c.fill(fx, fy + 1, 2, f.h, C.side); c.fill(fx + Double(f.w - 2), fy + 1, 2, f.h, C.side); c.fill(fx, fy + Double(f.h), f.w, 2, C.side)
            c.fill(fx + 2, fy + 2, f.w - 4, f.h - 2, C.wax)
        }
        var state = [Int: Int]()
        for (rank, cell) in order.enumerated() { state[cell] = rank < capped ? 2 : rank < filled ? 1 : 0 }
        for (i, cell) in cells.enumerated() {
            if empty && cell.kind != .honey { hex(cell.cx, cell.cy, C.empty, on: c); continue }
            switch cell.kind {
            case .honey:
                switch state[i] ?? 0 {
                case 2: hex(cell.cx, cell.cy, C.capped, on: c); c.pixel(cell.cx + 2, cell.cy + 2, C.cappedShade)
                case 1: hex(cell.cx, cell.cy, C.honey, on: c); c.pixel(cell.cx + 1, cell.cy, C.honeyHi)
                default: hex(cell.cx, cell.cy, C.empty, on: c)
                }
            case .brood: hex(cell.cx, cell.cy, C.brood, on: c); c.fill(Double(cell.cx + 1), Double(cell.cy + 1), 2, 1, C.broodDot)
            case .larva: hex(cell.cx, cell.cy, C.empty, on: c); c.fill(Double(cell.cx + 1), Double(cell.cy + 1), 2, 1, C.larva)
            case .pollen: hex(cell.cx, cell.cy, cell.pollen, on: c)
            case .empty: hex(cell.cx, cell.cy, C.empty, on: c)
            }
        }
    }

    private func hex(_ cx: Int, _ cy: Int, _ colour: RGB, on c: PixelCanvas? = nil) {
        let c = c ?? canvas, x = Double(cx), y = Double(cy)
        c.fill(x + 1, y, 2, 1, colour); c.fill(x, y + 1, 4, 1, colour); c.fill(x + 1, y + 2, 2, 1, colour)
    }

    private func drawBee(_ x: Double, _ y: Double, dir: Double, resting: Bool, time: Double) {
        let x = x.rounded(), y = y.rounded()
        func px(_ dx: Double, _ dy: Double, _ c: RGB, _ a: Double = 1) { canvas.fill(x + dx * dir, y + dy, 1, 1, c, alpha: a) }
        px(-2, 0, C.beeDark); px(-1, 0, C.bee); px(0, 0, C.beeDark); px(1, 0, C.bee); px(2, 0, C.beeDark)
        px(-1, 1, C.bee); px(0, 1, C.beeDark); px(1, 1, C.bee)
        let flutter = !resting && Int(time * 12 + x) % 2 == 0
        px(-1, -1, C.wing, 0.85); px(0, flutter ? -2 : -1, C.wing, 0.85)
    }

    private func drawQueenCells(_ spots: [(Int, Int)]) {
        for (x, y) in spots {
            let fx = Double(x), fy = Double(y)
            canvas.fill(fx, fy, 3, 1, RGB("#b07a42")); canvas.fill(fx - 1, fy + 1, 5, 5, RGB("#c99050"))
            canvas.fill(fx, fy + 6, 3, 1, RGB("#c99050")); canvas.fill(fx + 1, fy + 7, 1, 1, RGB("#b07a42"))
            canvas.fill(fx, fy + 2, 1, 1, RGB("#a8743a")); canvas.fill(fx + 2, fy + 4, 1, 1, RGB("#a8743a")); canvas.fill(fx - 1, fy + 1, 1, 2, RGB("#e0ab6a"))
        }
    }

    private func drawQueen(_ world: World, time: Double) {
        guard world.hasQueen(hive: hiveIndex) else { return }
        let x = queenPos.x.rounded(), y = queenPos.y.rounded()
        func px(_ dx: Double, _ dy: Double, _ c: RGB, _ a: Double = 1) { canvas.fill(x + dx, y + dy, 1, 1, c, alpha: a) }
        px(-3, 0, C.beeDark); px(-2, 0, C.queen); px(-1, 0, C.beeDark); px(0, 0, C.queen); px(1, 0, C.queen); px(2, 0, C.beeDark)
        px(-3, 1, C.queen); px(-2, 1, C.beeDark); px(-1, 1, C.queen); px(0, 1, C.beeDark); px(1, 1, C.queen)
        px(-1, -1, C.wing, 0.85); px(0, -1, C.wing, 0.85)
        px(1, -2, C.crown); px(2, -2, C.crown); px(3, -2, C.crown); px(1, -3, C.crown); px(3, -3, C.crown)
    }

    private func drawSleeper(_ cell: Cell, time: Double, phase: Double) {
        hex(cell.cx, cell.cy, C.bee)
        canvas.fill(Double(cell.cx), Double(cell.cy + 1), 4, 1, C.beeDark)
        if sin(time * 1.1 + phase) > 0.2 { canvas.fill(Double(cell.cx + 1), Double(cell.cy + 2), 2, 1, C.sleepy) }
    }

    private func applyNight(dark: Double, time: Double) {
        canvas.multiplyAll(by: RGB.white.mixed(with: C.nightTint, dark))
        canvas.fill(0, 0, Layout.width, Layout.height, C.glow, alpha: 0.10 * dark)
        let gx = Double(frames[1].x + 28), gy = Double(frames[1].y + 84), breathe = 0.85 + 0.15 * sin(time * 0.6)
        for y in -48...48 {
            for x in -84...84 {
                let d = Double(x * x) / 7056 + Double(y * y) / 2304
                guard d <= 1, d <= 0.55 || (x + y) % 2 == 0 else { continue }
                canvas.fill(gx + Double(x), gy + Double(y), 1, 1, C.glow, alpha: (1 - d) * 0.28 * breathe * dark)
            }
        }
    }

    private func drawZees() {
        for z in zees {
            let a = min(1, z.age * 2) * max(0, 1 - z.age / 3.2)
            let x = (z.x + sin(z.age * 2 + z.phase) * 1.5).rounded(), y = z.y.rounded()
            if z.big {
                canvas.fill(x, y, 3, 1, C.zee, alpha: a); canvas.fill(x + 1, y + 1, 1, 1, C.zee, alpha: a); canvas.fill(x, y + 2, 3, 1, C.zee, alpha: a)
            } else {
                canvas.fill(x, y, 2, 1, C.zee, alpha: a); canvas.fill(x, y + 1, 2, 1, C.zee, alpha: a)
            }
        }
    }

    private func drawHeader(_ world: World, hive: Hive, emptyBox: Bool) {
        Widgets.backArrow(canvas)
        PixelFont.draw(hive.name, on: canvas, x: Widgets.titleX, y: 7, colour: Widgets.titleColour, shadow: C.textShadow)
        let stats = emptyBox ? "empty box" : "\(world.beeCount(hive: hiveIndex)) bees · honey \(Int(displayedHoney * 100))%"
        PixelFont.draw(stats, on: canvas, x: Layout.width - 8 - PixelFont.width(stats), y: 7, colour: C.stats, shadow: C.textShadow)
    }

    private func drawButton(ready: Bool, time: Double) {
        let r = HiveRenderer.collectRect, x = Double(r.x), y = Double(r.y)
        let face = ready ? C.button.mixed(with: C.buttonBright, 0.5 + 0.5 * sin(time * 3.9)) : C.buttonOff
        canvas.fill(x - 1, y - 1, r.w + 2, r.h + 2, C.outline)
        canvas.fill(x, y, r.w, r.h, face)
        canvas.fill(x, y, r.w, 1, ready ? C.buttonLight : face.mixed(with: .white, 0.15))
        canvas.fill(x, y + Double(r.h - 1), r.w, 1, ready ? C.buttonShade : face.mixed(with: C.outline, 0.25))
        let label = "Collect honey"
        PixelFont.draw(label, on: canvas, x: r.x + (r.w - PixelFont.width(label)) / 2, y: r.y + 4, colour: ready ? C.buttonText : C.buttonOffText)
    }

    private func drawToast(dt: Double) {
        guard var t = toast else { return }
        t.age += dt
        toast = t.age > 2.4 ? nil : t
        let alpha = min(1, t.age * 4) * min(1, max(0, (2.4 - t.age) * 3))
        let w = PixelFont.width(t.text) + 12, x = Double((Layout.width - w) / 2), y = 76 - min(1, t.age) * 6
        canvas.fill(x - 1, y - 1, w + 2, 15, C.outline, alpha: alpha)
        canvas.fill(x, y, w, 13, C.toast, alpha: alpha)
        if alpha > 0.5 { PixelFont.draw(t.text, on: canvas, x: Int(x) + 6, y: Int(y.rounded()) + 4, colour: C.buttonText) }
    }
}
