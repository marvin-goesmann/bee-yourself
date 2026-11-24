#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

final class Game {
    enum Scene: Equatable {
        case garden
        case hive(Int)
        case pantry
        case book
        case valley(Valley)
        case stall
        case picker(Valley, Int)
        case helpers
        case region
        case factory
    }

    private enum Item: Equatable { case hive(Int), helper(Int) }

    private struct Drag {
        let item: Item
        let start: (x: Double, y: Double)
        let offset: (x: Double, y: Double)
        var moved = false
        var at: (x: Int, y: Int)
    }

    private static let dragThreshold = 2.0

    var onChange: (() -> Void)?
    private(set) var currentGarden: Int
    private(set) var scene = Scene.garden

    let world: World
    private let gardenView = GardenRenderer()
    private let hiveView = HiveRenderer()
    private let pantry = PantryRenderer()
    private let book = BookRenderer()
    private let valley = ValleyRenderer()
    private let stall = StallRenderer()
    private let region = RegionRenderer()
    private let factory = FactoryRenderer()
    private var time = 0.0
    var mouse: (x: Double, y: Double)?
    private enum Placing: Equatable { case emptyBox, hive(Int), helper(Int) }
    private var placing: Placing?
    private var drag: Drag?
    private var note: (lines: [String], age: Double)?
    private var shedOpen = false
    private var stallReturnsToGarden = false
    private var stallValley = Valley.home
    private var confirmingFactory = false
    private var demolition: Double?
    private var sleep: (age: Double, slept: Bool)?
    private static let sleepFadeIn = 1.2, sleepHold = 2.2, sleepFadeOut = 4.2
    private var canSleep: Bool { sleep == nil && Clock.canSleep(Clock.minute(at: Date())) }
    private static let maxShedRows = 5

    enum ShedAction { case emptyBox, hive(Int), helper(Int), stall, close }

    func shedLayout() -> (panel: PixelRect, rows: [(rect: PixelRect, label: String, enabled: Bool, action: ShedAction)]) {
        let room = world.hasRoom(in: currentGarden), helperRoom = world.helper(in: currentGarden) == nil
        var items: [(String, Bool, ShedAction)] = []
        for helper in world.storedHelpers { items.append((helper.kind.title, helperRoom, .helper(helper.id))) }
        if world.spareBoxes > 0 { items.append((world.spareBoxes == 1 ? "Hive box" : "Hive box x\(world.spareBoxes)", room, .emptyBox)) }
        for hive in world.packedHives {
            items.append(("\(hive.name) · \(world.beeCount(hive: hive.id)) bees", room, .hive(hive.id)))
        }
        items = Array(items.prefix(Game.maxShedRows))
        let h = 26 + max(1, items.count) * 16 + 32
        let panel: PixelRect = (44, max(22, (Layout.height - h) / 2), 152, h)
        var rows: [(PixelRect, String, Bool, ShedAction)] = items.enumerated().map { i, item in
            ((panel.x + 12, panel.y + 22 + i * 16, panel.w - 24, 12), item.0, item.1, item.2)
        }
        let bottom = panel.y + panel.h - 20
        rows.append(((panel.x + 12, bottom, 60, 12), "To stall", true, .stall))
        rows.append(((panel.x + panel.w - 72, bottom, 60, 12), "Close", true, .close))
        return (panel, rows)
    }

    init(world: World, currentGarden: Int) {
        self.world = world
        self.currentGarden = currentGarden
        if world.garden(currentGarden) == nil && world.hasFactory { scene = .region }
    }

    private var garden: Garden? { world.garden(currentGarden) }

    var isAsleep: Bool { sleep != nil }

    @discardableResult
    func click(_ p: (x: Double, y: Double)) -> Bool {
        guard sleep == nil, demolition == nil else { return true }
        switch scene {
        case .garden:
            if shedOpen {
                let layout = shedLayout()
                guard Widgets.contains(layout.panel, p) else { shedOpen = false; return true }
                guard let row = layout.rows.first(where: { Widgets.contains($0.rect, p) }), row.enabled else { return true }
                shedOpen = false
                switch row.action {
                case .emptyBox: placing = .emptyBox
                case .hive(let id): placing = .hive(id)
                case .helper(let id): placing = .helper(id)
                case .stall: stallReturnsToGarden = true; stallValley = garden?.valley ?? .home; go(to: .stall)
                case .close: break
                }
                return true
            }
            if placing != nil { place(at: p); return true }
            if Widgets.contains(Widgets.mapRect, p), let garden { go(to: .valley(garden.valley)); return true }
            if Widgets.contains(Widgets.pantryRect, p) { go(to: .pantry); return true }
            if Widgets.contains(Widgets.shedRect, p) { shedOpen = true; return true }
            if canSleep && Widgets.contains(Widgets.bedRect, p) { sleep = (0, false); return true }
            if let helper = helperAt(p) {
                drag = Drag(item: .helper(helper.id), start: p, offset: (p.x - helper.x, p.y - helper.y), at: (Int(helper.x), Int(helper.y)))
                return true
            }
            if let hive = hiveAt(p) {
                drag = Drag(item: .hive(hive.id), start: p, offset: (p.x - Double(hive.x), p.y - Double(hive.y)), at: (hive.x, hive.y))
                return true
            }
        case .hive(let id):
            if Widgets.contains(Widgets.backRect, p) { go(to: .garden); return true }
            if Widgets.contains(HiveRenderer.collectRect, p), let jar = world.collect(hive: id, at: Date()) {
                hiveView.showCollected(jar.honey)
                onChange?()
                return true
            }
            if Widgets.contains(HiveRenderer.splitRect, p), let source = world.hive(id), world.readyToSplit(source), let target = world.split(hive: id) {
                currentGarden = source.garden
                go(to: .garden)
                if target.garden != source.garden, let destination = world.garden(target.garden) {
                    show(["Moving to \(target.name)", "in the \(destination.kind.title.lowercased())"])
                }
                onChange?()
                return true
            }
        case .pantry:
            if Widgets.contains(Widgets.backRect, p) { go(to: .garden); return true }
            if Widgets.contains(PantryRenderer.bookRect, p) { go(to: .book); return true }
        case .book:
            if Widgets.contains(Widgets.backRect, p) { go(to: .pantry); return true }
        case .valley(let valley):
            if confirmingFactory {
                if Widgets.contains(ValleyRenderer.buildRect, p) { buildFactory() }
                else if Widgets.contains(ValleyRenderer.cancelRect, p) || !Widgets.contains(ValleyRenderer.confirmPanel, p) { confirmingFactory = false }
                return true
            }
            if Widgets.contains(Widgets.backRect, p) { go(to: world.hasFactory ? .region : .garden); return true }
            if Widgets.contains(ValleyRenderer.stallRect, p) { stallValley = valley; go(to: .stall); return true }
            if valley == .home && world.canBuildFactory && Widgets.contains(ValleyRenderer.factoryRect, p) { confirmingFactory = true; return true }
            if let plot = ValleyRenderer.plot(at: p) {
                if let owned = world.garden(in: valley, plot: plot) { currentGarden = owned.id; go(to: .garden) }
                else { go(to: .picker(valley, plot)) }
                return true
            }
        case .stall:
            if Widgets.contains(Widgets.backRect, p) { go(to: stallReturnsToGarden ? .garden : .valley(stallValley)); return true }
            if Widgets.contains(StallRenderer.tradeRect, p) {
                if world.buyHiveBox(in: stallValley) { stall.show("+1 hive box in your shed"); onChange?() }
                else { stall.show("need \(world.hiveBoxPrice(in: stallValley)) jars") }
                return true
            }
            if Widgets.contains(StallRenderer.hireRect, p), world.canHireHelper { go(to: .helpers); return true }
            if Widgets.contains(StallRenderer.valleyRect, p) { go(to: .valley(stallValley)); return true }
        case .helpers:
            if Widgets.contains(Widgets.backRect, p) { go(to: .stall); return true }
            for (i, kind) in HelperKind.allCases.enumerated() where Widgets.contains(StallRenderer.helperRect(i), p) {
                if world.hireHelper(kind, in: stallValley) != nil {
                    go(to: .stall)
                    stall.show("\(kind.title) is in your shed")
                    onChange?()
                } else { stall.show("need \(world.helperPrice(in: stallValley)) jars") }
                return true
            }
        case .picker(let valley, let plot):
            if Widgets.contains(Widgets.backRect, p) { go(to: .valley(valley)); return true }
            for (i, kind) in GardenKind.allCases.enumerated() where Widgets.contains(StallRenderer.pickerRect(i), p) {
                let hadColony = world.hasColony
                if let garden = world.buyGarden(kind: kind, plot: plot, in: valley) {
                    currentGarden = garden.id
                    go(to: .garden)
                    if !hadColony { show(["A wild swarm", "has moved in"]) }
                    onChange?()
                } else { stall.show("need \(world.gardenPrice(in: valley)) jars") }
                return true
            }
        case .region:
            if garden != nil && Widgets.contains(Widgets.backRect, p) { go(to: .garden); return true }
            if let valley = RegionRenderer.valley(at: p, world: world) {
                if valley == .home { go(to: .factory) }
                else if world.isOpen(valley) { go(to: .valley(valley)) }
                else { show(["Not yet", "put a garden in every", "valley of the ring inside"]) }
                return true
            }
        case .factory:
            if Widgets.contains(Widgets.backRect, p) { go(to: .region); return true }
            if let helper = homelessHelperAt(p) { helper.pet(); return true }
        }
        return false
    }

    private func buildFactory() {
        confirmingFactory = false
        valley.render(world, valley: .home, minute: Clock.minute(at: Date()), time: time, current: currentGarden, hover: nil)
        factory.capture(valley.canvas)
        guard world.buildFactory() else { return }
        demolition = 0
        onChange?()
    }

    func dragged(to p: (x: Double, y: Double)) {
        mouse = p
        guard var d = drag else { return }
        if !d.moved && hypot(p.x - d.start.x, p.y - d.start.y) < Game.dragThreshold { return }
        d.moved = true
        d.at = (Int((p.x - d.offset.x).rounded()), Int((p.y - d.offset.y).rounded()))
        drag = d
    }

    func release(_ p: (x: Double, y: Double)) {
        guard let d = drag else { return }
        drag = nil
        switch d.item {
        case .helper(let id):
            guard d.moved else { world.helper(id)?.pet(); return }
            if overShed(p) { world.storeHelper(id); onChange?() }
            else if world.moveHelper(id, x: d.at.x, y: d.at.y) { onChange?() }
        case .hive(let id):
            if d.moved {
                if overShed(p) {
                    if world.pack(hive: id) == .packing, let hive = world.hive(id) { show(["\(hive.name) is packing up"]); onChange?() }
                    else { show(["Not right now", "the bees are busy"]) }
                } else if world.move(hive: id, x: d.at.x, y: d.at.y) { onChange?() }
            } else {
                go(to: .hive(id))
            }
        }
    }

    func hover(_ p: (x: Double, y: Double)?) { mouse = p }

    func scroll(by delta: Int) {
        switch scene {
        case .pantry: pantry.scroll(by: delta, world: world)
        case .book: book.scroll(by: delta, world: world)
        default: break
        }
    }

    func escape() {
        guard demolition == nil else { return }
        if placing != nil { placing = nil; return }
        if shedOpen { shedOpen = false; return }
        if confirmingFactory { confirmingFactory = false; return }
        switch scene {
        case .garden: break
        case .hive, .pantry: go(to: .garden)
        case .valley: go(to: world.hasFactory ? .region : .garden)
        case .book: go(to: .pantry)
        case .stall: go(to: stallReturnsToGarden ? .garden : .valley(stallValley))
        case .picker(let valley, _): go(to: .valley(valley))
        case .helpers: go(to: .stall)
        case .region: if garden != nil { go(to: .garden) }
        case .factory: go(to: .region)
        }
    }

    private func go(to next: Scene) {
        switch next {
        case .hive(let id): hiveView.open(hive: id, world: world)
        case .pantry: pantry.open(world: world)
        case .book: book.open()
        default: break
        }
        placing = nil
        drag = nil
        shedOpen = false
        confirmingFactory = false
        if case .valley = next { stallReturnsToGarden = false }
        scene = next
    }

    private func overShed(_ p: (x: Double, y: Double)) -> Bool {
        let r = Widgets.shedRect
        return Widgets.contains((r.x - 4, r.y - 6, r.w + 8, r.h + 8), p)
    }

    private func place(at p: (x: Double, y: Double)) {
        let spot = ghostSpot(p)
        let placed: Bool
        switch placing {
        case .emptyBox: placed = world.placeBox(x: spot.x, y: spot.y, in: currentGarden)
        case .hive(let id): placed = world.unpack(hive: id, x: spot.x, y: spot.y, in: currentGarden)
        case .helper(let id):
            let feet = helperSpot(p)
            placed = world.placeHelper(id, x: feet.x, y: feet.y, in: currentGarden)
        case nil: placed = false
        }
        if placed { placing = nil; onChange?() }
    }

    private func ghostSpot(_ p: (x: Double, y: Double)) -> (x: Int, y: Int) {
        (Int((p.x - 9).rounded()), Int((p.y + 12).rounded()))
    }

    private func helperSpot(_ p: (x: Double, y: Double)) -> (x: Int, y: Int) {
        (Int(p.x.rounded()), Int((p.y + 7).rounded()))
    }

    private func show(_ lines: [String]) { note = (lines, 0) }

    func isInteractive(_ p: (x: Double, y: Double)) -> Bool {
        guard demolition == nil else { return false }
        switch scene {
        case .garden:
            if shedOpen { return shedLayout().rows.contains { $0.enabled && Widgets.contains($0.rect, p) } }
            return placing != nil || helperAt(p) != nil || hiveAt(p) != nil || [Widgets.mapRect, Widgets.pantryRect, Widgets.shedRect].contains { Widgets.contains($0, p) }
                || (canSleep && Widgets.contains(Widgets.bedRect, p))
        case .hive(let id):
            guard let hive = world.hive(id) else { return false }
            return Widgets.contains(Widgets.backRect, p) || (Widgets.contains(HiveRenderer.collectRect, p) && hive.isFull)
                || (Widgets.contains(HiveRenderer.splitRect, p) && world.readyToSplit(hive) && world.splitTarget(for: hive) != nil)
        case .pantry: return Widgets.contains(Widgets.backRect, p) || Widgets.contains(PantryRenderer.bookRect, p)
        case .book: return Widgets.contains(Widgets.backRect, p)
        case .valley(let valley):
            if confirmingFactory { return Widgets.contains(ValleyRenderer.buildRect, p) || Widgets.contains(ValleyRenderer.cancelRect, p) }
            return Widgets.contains(Widgets.backRect, p) || Widgets.contains(ValleyRenderer.stallRect, p) || ValleyRenderer.plot(at: p) != nil
                || (valley == .home && world.canBuildFactory && Widgets.contains(ValleyRenderer.factoryRect, p))
        case .stall: return [Widgets.backRect, StallRenderer.tradeRect, StallRenderer.valleyRect].contains { Widgets.contains($0, p) }
            || (world.canHireHelper && Widgets.contains(StallRenderer.hireRect, p))
        case .helpers: return Widgets.contains(Widgets.backRect, p) || (0..<HelperKind.allCases.count).contains { Widgets.contains(StallRenderer.helperRect($0), p) }
        case .picker: return Widgets.contains(Widgets.backRect, p) || (0..<GardenKind.allCases.count).contains { Widgets.contains(StallRenderer.pickerRect($0), p) }
        case .region:
            if garden != nil && Widgets.contains(Widgets.backRect, p) { return true }
            return RegionRenderer.valley(at: p, world: world).map { $0 == .home || world.isOpen($0) } ?? false
        case .factory: return Widgets.contains(Widgets.backRect, p) || homelessHelperAt(p) != nil
        }
    }

    private func homelessHelperAt(_ p: (x: Double, y: Double)) -> Helper? {
        world.homelessHelpers.first { abs(p.x - $0.x) <= 6 && p.y >= $0.y - 14 && p.y <= $0.y + 1 }
    }

    private func helperAt(_ p: (x: Double, y: Double)) -> Helper? {
        guard let helper = world.helper(in: currentGarden) else { return nil }
        return abs(p.x - helper.x) <= 6 && p.y >= helper.y - 14 && p.y <= helper.y + 1 ? helper : nil
    }

    private func hiveAt(_ p: (x: Double, y: Double)) -> Hive? {
        world.hives(in: currentGarden).sorted { $0.y > $1.y }.first {
            p.x >= Double($0.x - 2) && p.x < Double($0.x + 20) && p.y >= Double($0.y - 28) && p.y < Double($0.y)
        }
    }

    func wake() { sleep = (Self.sleepHold, true) }

    func step(dt: Double, minute: Double, time: Double) -> PixelCanvas? {
        self.time = time
        advance(by: dt, visible: true, minute: minute)
        if scene == .garden && garden == nil && world.hasFactory { scene = .region }
        Widgets.backHovered = scene != .garden && (mouse.map { Widgets.contains(Widgets.backRect, $0) } ?? false)
        if let age = demolition {
            Widgets.backHovered = false
            if age + dt < FactoryRenderer.duration {
                demolition = age + dt
                factory.renderDemolition(world, age: age + dt, minute: minute, time: time)
                return factory.canvas
            }
            demolition = nil
            go(to: .region)
            show(["The factory is humming", "eight new valleys await"])
        }
        let canvas: PixelCanvas
        switch scene {
        case .garden:
            guard let garden else { return nil }
            var ghost: GardenRenderer.Ghost?
            var helperGhost: (kind: HelperKind, x: Int, y: Int, valid: Bool)?
            var hidingHelper: Int?
            let packing = mouse.map(overShed) ?? false
            if let d = drag, d.moved {
                switch d.item {
                case .hive(let id):
                    ghost = .init(x: d.at.x, y: d.at.y, valid: packing || world.canPlace(x: d.at.x, y: d.at.y, in: currentGarden, ignoring: id), hiding: id)
                case .helper(let id):
                    hidingHelper = id
                    if let helper = world.helper(id) { helperGhost = (helper.kind, d.at.x, d.at.y, packing || world.canPlaceHelper(x: d.at.x, y: d.at.y)) }
                }
            } else if let m = mouse {
                switch placing {
                case .helper(let id):
                    let feet = helperSpot(m)
                    if let helper = world.helper(id) { helperGhost = (helper.kind, feet.x, feet.y, world.canPlaceHelper(x: feet.x, y: feet.y)) }
                case .emptyBox, .hive:
                    let spot = ghostSpot(m)
                    ghost = .init(x: spot.x, y: spot.y, valid: world.canPlace(x: spot.x, y: spot.y, in: currentGarden), hiding: nil)
                case nil: break
                }
            }
            let hover = mouse.flatMap { hiveAt($0)?.id }
            gardenView.render(world, garden: garden, minute: minute, time: time, ghost: ghost, hover: drag == nil && placing == nil && !shedOpen ? hover : nil, hidingHelper: hidingHelper)
            canvas = gardenView.canvas
            if let g = helperGhost {
                HelperSprite.draw(g.kind, on: canvas, x: g.x - 8, y: g.y - 16, pose: .walk, frame: Int(time * 6), dim: g.valid ? 0 : 0.6)
            }
            if canSleep { Widgets.bedIcon(canvas, lifted: !shedOpen && placing == nil && (mouse.map { Widgets.contains(Widgets.bedRect, $0) } ?? false)) }
            if let d = drag, d.moved, let m = mouse, overShed(m) { highlightShed(canvas) }
            if shedOpen { drawShedPanel(canvas) }
        case .hive:
            hiveView.render(world, minute: minute, time: time, dt: dt, mouse: mouse)
            canvas = hiveView.canvas
        case .pantry:
            pantry.render(world, time: time, dt: dt, mouse: mouse)
            canvas = pantry.canvas
        case .book:
            book.render(world)
            canvas = book.canvas
        case .valley(let v):
            valley.render(world, valley: v, minute: minute, time: time, current: currentGarden, hover: mouse, confirming: confirmingFactory)
            canvas = valley.canvas
        case .stall:
            stall.renderStall(world, valley: stallValley, time: time, dt: dt)
            canvas = stall.canvas
        case .picker(let v, _):
            stall.renderPicker(world, valley: v, time: time, dt: dt, hover: mouse)
            canvas = stall.canvas
        case .helpers:
            stall.renderHelpers(world, valley: stallValley, time: time, dt: dt, hover: mouse)
            canvas = stall.canvas
        case .region:
            region.render(world, minute: minute, time: time, current: garden?.valley, hover: mouse, back: garden != nil)
            canvas = region.canvas
        case .factory:
            factory.render(world, minute: minute, time: time, hover: mouse)
            canvas = factory.canvas
        }
        if var n = note {
            n.age += dt
            note = n.age > 2.6 ? nil : n
            Widgets.note(canvas, lines: n.lines, x: (Layout.width - (n.lines.map(PixelFont.width).max() ?? 0) - 10) / 2, y: 70)
        }
        if sleep != nil { drawSleep(canvas, dt: dt) }
        return canvas
    }

    private func drawSleep(_ canvas: PixelCanvas, dt: Double) {
        guard var s = sleep else { return }
        s.age += dt
        if s.age >= Self.sleepFadeIn && !s.slept { sleepUntilMorning(); s.slept = true }
        sleep = s.age > Self.sleepFadeOut ? nil : s
        let fade = s.age < Self.sleepFadeIn ? Clock.smooth(0, Self.sleepFadeIn, s.age)
            : s.age < Self.sleepHold ? 1 : 1 - Clock.smooth(Self.sleepHold, Self.sleepFadeOut, s.age)
        canvas.tint = .white
        canvas.fill(0, 0, Layout.width, Layout.height, RGB("#0e0f22"), alpha: fade)
        let zees = RGB("#c8c4e8")
        for k in 0..<3 {
            let t = s.age - 0.4 - Double(k) * 0.45
            guard t > 0, t < 1.8 else { continue }
            let a = fade * min(1, t * 3) * (1 - Clock.smooth(1.2, 1.8, t))
            PixelFont.draw("z", on: canvas, x: 112 + k * 6 + Int(sin(t * 3) * 2), y: 92 - k * 5 - Int(t * 8), colour: RGB("#0e0f22").mixed(with: zees, a))
        }
    }

    private func sleepUntilMorning() {
        let skip = Clock.secondsUntilMorning(from: Clock.minute(at: Date()))
        let step = max(0.5, skip / 4000), start = Date(), time = self.time
        var elapsed = 0.0
        while elapsed < skip {
            world.tick(step, minute: Clock.minute(at: start.addingTimeInterval(elapsed)), time: time + elapsed, visibleGarden: nil)
            elapsed += step
        }
        world.puffs.removeAll()
        Clock.offset += skip
        onChange?()
    }

    private func highlightShed(_ canvas: PixelCanvas) {
        let r = Widgets.shedRect, c = RGB("#fff2c0")
        canvas.fill(Double(r.x - 2), Double(r.y - 2), r.w + 4, 1, c); canvas.fill(Double(r.x - 2), Double(r.y + r.h + 1), r.w + 4, 1, c)
        canvas.fill(Double(r.x - 2), Double(r.y - 2), 1, r.h + 4, c); canvas.fill(Double(r.x + r.w + 1), Double(r.y - 2), 1, r.h + 4, c)
    }

    private func drawShedPanel(_ canvas: PixelCanvas) {
        let layout = shedLayout(), r = layout.panel
        canvas.tint = .white
        canvas.fill(0, 0, Layout.width, Layout.height, RGB("#1c1108"), alpha: 0.35)
        canvas.fill(Double(r.x + 2), Double(r.y + 2), r.w, r.h, RGB("#1c1108"), alpha: 0.3)
        canvas.fill(Double(r.x - 1), Double(r.y - 1), r.w + 2, r.h + 2, Widgets.C.outline)
        canvas.fill(Double(r.x), Double(r.y), r.w, r.h, Widgets.C.paper)
        PixelFont.draw("Your shed", on: canvas, x: r.x + 12, y: r.y + 9, colour: Widgets.C.buttonText)
        let hint = world.hasRoom(in: currentGarden) ? "" : "this garden is full"
        if layout.rows.count == 2 { PixelFont.draw("empty", on: canvas, x: r.x + 12, y: r.y + 26, colour: Widgets.C.ink) }
        for row in layout.rows {
            switch row.action {
            case .helper(let id):
                Widgets.button(canvas, row.rect, label: "", enabled: row.enabled)
                if let helper = world.helper(id) { HelperSprite.portrait(helper.kind, on: canvas, x: row.rect.x + 1, y: row.rect.y + 1, dim: !row.enabled) }
                PixelFont.draw(row.label, on: canvas, x: row.rect.x + 20, y: row.rect.y + 4, colour: row.enabled ? Widgets.C.buttonText : Widgets.C.buttonOffText)
            case .emptyBox, .hive:
                Widgets.button(canvas, row.rect, label: "", enabled: row.enabled)
                Widgets.tinyHiveBox(canvas, x: row.rect.x + 5, y: row.rect.y + 1, dim: !row.enabled)
                PixelFont.draw(row.label, on: canvas, x: row.rect.x + 20, y: row.rect.y + 4, colour: row.enabled ? Widgets.C.buttonText : Widgets.C.buttonOffText)
            case .stall, .close:
                Widgets.button(canvas, row.rect, label: row.label, enabled: row.enabled)
            }
        }
        PixelFont.draw(hint, on: canvas, x: r.x + (r.w - PixelFont.width(hint)) / 2, y: r.y + r.h - 31, colour: Widgets.C.ink)
    }

    func advance(by dt: Double, visible: Bool, minute: Double = Clock.minute(at: Date())) {
        if !visible { time += dt }
        let gardenOnScreen = visible && scene == .garden ? currentGarden : nil
        world.tick(dt, minute: minute, time: time, visibleGarden: gardenOnScreen)
        world.agePuffs(dt)
    }
}
