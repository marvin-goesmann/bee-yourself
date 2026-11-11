import AppKit
import QuartzCore

final class SceneView: NSView {
    private enum Scene: Equatable {
        case garden
        case hive(Int)
        case pantry
        case book
        case valley
        case stall
        case picker(Int)
    }

    private struct Drag {
        let hive: Int
        let start: (x: Double, y: Double)
        let offset: (x: Double, y: Double)
        var moved = false
        var at: (x: Int, y: Int)
    }

    private static let hiddenTickInterval = 0.5
    private static let dragThreshold = 2.0

    var onChange: (() -> Void)?
    private(set) var currentGarden: Int

    private let world: World
    private let gardenView = GardenRenderer()
    private let hiveView = HiveRenderer()
    private let pantry = PantryRenderer()
    private let book = BookRenderer()
    private let valley = ValleyRenderer()
    private let stall = StallRenderer()
    private var scene = Scene.garden
    private var link: CADisplayLink?
    private var hiddenTimer: Timer?
    private var lastTimestamp: CFTimeInterval?
    private let startTime = CACurrentMediaTime()
    var mouse: (x: Double, y: Double)?
    private enum Placing: Equatable { case emptyBox, hive(Int) }
    private var placing: Placing?
    private var drag: Drag?
    private var note: (lines: [String], age: Double)?
    private var shedOpen = false
    private var stallReturnsToGarden = false
    private var sleep: (age: Double, slept: Bool)?
    private static let sleepFadeIn = 1.2, sleepHold = 2.2, sleepFadeOut = 4.2
    private var canSleep: Bool { sleep == nil && Clock.canSleep(Clock.minute(at: Date())) }
    private static let maxShedRows = 5

    enum ShedAction { case emptyBox, hive(Int), stall, close }

    func shedLayout() -> (panel: PixelRect, rows: [(rect: PixelRect, label: String, enabled: Bool, action: ShedAction)]) {
        let room = world.hasRoom(in: currentGarden)
        var items: [(String, ShedAction)] = []
        if world.spareBoxes > 0 { items.append((world.spareBoxes == 1 ? "Hive box" : "Hive box x\(world.spareBoxes)", .emptyBox)) }
        for hive in world.packedHives.prefix(SceneView.maxShedRows - items.count) {
            items.append(("\(hive.name) · \(world.beeCount(hive: hive.id)) bees", .hive(hive.id)))
        }
        let h = 26 + max(1, items.count) * 16 + 32
        let panel: PixelRect = (44, max(22, (Layout.height - h) / 2), 152, h)
        var rows: [(PixelRect, String, Bool, ShedAction)] = items.enumerated().map { i, item in
            ((panel.x + 12, panel.y + 22 + i * 16, panel.w - 24, 12), item.0, room, item.1)
        }
        let bottom = panel.y + panel.h - 20
        rows.append(((panel.x + 12, bottom, 60, 12), "To stall", true, .stall))
        rows.append(((panel.x + panel.w - 72, bottom, 60, 12), "Close", true, .close))
        return (panel, rows)
    }

    init(world: World, currentGarden: Int) {
        self.world = world
        self.currentGarden = currentGarden
        super.init(frame: .zero)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { stopAll(); return }
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
        window.makeFirstResponder(self)
        startRendering()
    }

    private var garden: Garden? { world.garden(currentGarden) }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        guard sleep == nil else { return }
        if !click(pixelPoint(event)) { window?.performDrag(with: event) }
    }

    @discardableResult
    func click(_ p: (x: Double, y: Double)) -> Bool {
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
                case .stall: stallReturnsToGarden = true; go(to: .stall)
                case .close: break
                }
                return true
            }
            if placing != nil { place(at: p); return true }
            if Widgets.contains(Widgets.mapRect, p) { go(to: .valley); return true }
            if Widgets.contains(Widgets.pantryRect, p) { go(to: .pantry); return true }
            if Widgets.contains(Widgets.shedRect, p) { shedOpen = true; return true }
            if canSleep && Widgets.contains(Widgets.bedRect, p) { sleep = (0, false); return true }
            if let hive = hiveAt(p) {
                drag = Drag(hive: hive.id, start: p, offset: (p.x - Double(hive.x), p.y - Double(hive.y)), at: (hive.x, hive.y))
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
        case .valley:
            if Widgets.contains(Widgets.backRect, p) { go(to: .garden); return true }
            if Widgets.contains(ValleyRenderer.stallRect, p) { go(to: .stall); return true }
            if let plot = ValleyRenderer.plot(at: p) {
                if let owned = world.gardens.first(where: { $0.plot == plot }) { currentGarden = owned.id; go(to: .garden) }
                else { go(to: .picker(plot)) }
                return true
            }
        case .stall:
            if Widgets.contains(Widgets.backRect, p) { go(to: stallReturnsToGarden ? .garden : .valley); return true }
            if Widgets.contains(StallRenderer.tradeRect, p) {
                if world.buyHiveBox() { stall.show("+1 hive box in your shed"); onChange?() }
                else { stall.show("need \(World.hiveBoxPrice) jars") }
                return true
            }
            if Widgets.contains(StallRenderer.valleyRect, p) { go(to: .valley); return true }
        case .picker(let plot):
            if Widgets.contains(Widgets.backRect, p) { go(to: .valley); return true }
            for (i, kind) in GardenKind.allCases.enumerated() where Widgets.contains(StallRenderer.pickerRect(i), p) {
                if let garden = world.buyGarden(kind: kind, plot: plot) {
                    currentGarden = garden.id
                    go(to: .garden)
                    onChange?()
                } else { stall.show("need \(world.gardenPrice()) jars") }
                return true
            }
        }
        return false
    }

    override func mouseDragged(with event: NSEvent) {
        guard var d = drag else { return }
        let p = pixelPoint(event)
        mouse = p
        if !d.moved && hypot(p.x - d.start.x, p.y - d.start.y) < SceneView.dragThreshold { return }
        d.moved = true
        d.at = (Int((p.x - d.offset.x).rounded()), Int((p.y - d.offset.y).rounded()))
        drag = d
    }

    override func mouseUp(with event: NSEvent) { release(pixelPoint(event)) }

    func release(_ p: (x: Double, y: Double)) {
        guard let d = drag else { return }
        drag = nil
        if d.moved {
            if overShed(p) {
                if world.pack(hive: d.hive) == .packing, let hive = world.hive(d.hive) { show(["\(hive.name) is packing up"]); onChange?() }
                else { show(["Not right now", "the bees are busy"]) }
            } else if world.move(hive: d.hive, x: d.at.x, y: d.at.y) { onChange?() }
        } else {
            go(to: .hive(d.hive))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pixelPoint(event)
        mouse = p
        (isInteractive(p) ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 2 else { return }
        let delta = event.scrollingDeltaY > 0 ? -1 : 1
        switch scene {
        case .pantry: pantry.scroll(by: delta, world: world)
        case .book: book.scroll(by: delta, world: world)
        default: break
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else { super.keyDown(with: event); return }
        if placing != nil { placing = nil; return }
        if shedOpen { shedOpen = false; return }
        switch scene {
        case .garden: break
        case .hive, .pantry, .valley: go(to: .garden)
        case .book: go(to: .pantry)
        case .stall: go(to: stallReturnsToGarden ? .garden : .valley)
        case .picker: go(to: .valley)
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
        if next == .valley { stallReturnsToGarden = false }
        scene = next
        NSCursor.arrow.set()
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
        case nil: placed = false
        }
        if placed { placing = nil; onChange?() }
    }

    private func ghostSpot(_ p: (x: Double, y: Double)) -> (x: Int, y: Int) {
        (Int((p.x - 9).rounded()), Int((p.y + 12).rounded()))
    }

    private func show(_ lines: [String]) { note = (lines, 0) }

    private func isInteractive(_ p: (x: Double, y: Double)) -> Bool {
        switch scene {
        case .garden:
            if shedOpen { return shedLayout().rows.contains { $0.enabled && Widgets.contains($0.rect, p) } }
            return placing != nil || hiveAt(p) != nil || [Widgets.mapRect, Widgets.pantryRect, Widgets.shedRect].contains { Widgets.contains($0, p) }
                || (canSleep && Widgets.contains(Widgets.bedRect, p))
        case .hive(let id):
            guard let hive = world.hive(id) else { return false }
            return Widgets.contains(Widgets.backRect, p) || (Widgets.contains(HiveRenderer.collectRect, p) && hive.isFull)
                || (Widgets.contains(HiveRenderer.splitRect, p) && world.readyToSplit(hive) && world.splitTarget(for: hive) != nil)
        case .pantry: return Widgets.contains(Widgets.backRect, p) || Widgets.contains(PantryRenderer.bookRect, p)
        case .book: return Widgets.contains(Widgets.backRect, p)
        case .valley: return Widgets.contains(Widgets.backRect, p) || Widgets.contains(ValleyRenderer.stallRect, p) || ValleyRenderer.plot(at: p) != nil
        case .stall: return [Widgets.backRect, StallRenderer.tradeRect, StallRenderer.valleyRect].contains { Widgets.contains($0, p) }
        case .picker: return Widgets.contains(Widgets.backRect, p) || (0..<GardenKind.allCases.count).contains { Widgets.contains(StallRenderer.pickerRect($0), p) }
        }
    }

    private func pixelPoint(_ event: NSEvent) -> (x: Double, y: Double) {
        let local = convert(event.locationInWindow, from: nil)
        return (local.x / bounds.width * Double(Layout.width), (bounds.height - local.y) / bounds.height * Double(Layout.height))
    }

    private func hiveAt(_ p: (x: Double, y: Double)) -> Hive? {
        world.hives(in: currentGarden).sorted { $0.y > $1.y }.first {
            p.x >= Double($0.x - 2) && p.x < Double($0.x + 20) && p.y >= Double($0.y - 28) && p.y < Double($0.y)
        }
    }

    // MARK: Loop

    @objc private func occlusionChanged() {
        if window?.occlusionState.contains(.visible) == true { startRendering() } else { startHiddenTicking() }
    }

    private func startRendering() {
        hiddenTimer?.invalidate()
        hiddenTimer = nil
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = nil
    }

    private func startHiddenTicking() {
        link?.invalidate()
        link = nil
        guard hiddenTimer == nil else { return }
        let timer = Timer(timeInterval: Self.hiddenTickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance(by: Self.hiddenTickInterval, visible: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        hiddenTimer = timer
    }

    private func stopAll() {
        link?.invalidate(); link = nil
        hiddenTimer?.invalidate(); hiddenTimer = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        let dt = lastTimestamp.map { min(0.1, link.timestamp - $0) } ?? 1.0 / 30
        lastTimestamp = link.timestamp
        Widgets.updateInset(viewWidth: bounds.width)
        layer?.contents = step(dt: dt, minute: Clock.minute(at: Date()), time: CACurrentMediaTime() - startTime)?.makeImage()
    }

    func wake() { sleep = (Self.sleepHold, true) }

    func step(dt: Double, minute: Double, time: Double) -> PixelCanvas? {
        advance(by: dt, visible: true, minute: minute, time: time)
        Widgets.backHovered = scene != .garden && (mouse.map { Widgets.contains(Widgets.backRect, $0) } ?? false)
        let canvas: PixelCanvas
        switch scene {
        case .garden:
            guard let garden else { return nil }
            var ghost: GardenRenderer.Ghost?
            if let d = drag, d.moved {
                let packing = mouse.map(overShed) ?? false
                ghost = .init(x: d.at.x, y: d.at.y, valid: packing || world.canPlace(x: d.at.x, y: d.at.y, in: currentGarden, ignoring: d.hive), hiding: d.hive)
            } else if placing != nil, let m = mouse {
                let spot = ghostSpot(m)
                ghost = .init(x: spot.x, y: spot.y, valid: world.canPlace(x: spot.x, y: spot.y, in: currentGarden), hiding: nil)
            }
            let hover = mouse.flatMap { hiveAt($0)?.id }
            gardenView.render(world, garden: garden, minute: minute, time: time, ghost: ghost, hover: drag == nil && placing == nil && !shedOpen ? hover : nil)
            canvas = gardenView.canvas
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
        case .valley:
            valley.render(world, minute: minute, time: time, current: currentGarden, hover: mouse)
            canvas = valley.canvas
        case .stall:
            stall.renderStall(world, time: time, dt: dt)
            canvas = stall.canvas
        case .picker:
            stall.renderPicker(world, time: time, dt: dt, hover: mouse)
            canvas = stall.canvas
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
        let step = max(0.5, skip / 4000), start = Date(), time = CACurrentMediaTime() - startTime
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
            case .emptyBox, .hive:
                Widgets.button(canvas, row.rect, label: "", enabled: row.enabled)
                Widgets.tinyHiveBox(canvas, x: row.rect.x + 4, y: row.rect.y + 1, dim: !row.enabled)
                PixelFont.draw(row.label, on: canvas, x: row.rect.x + 17, y: row.rect.y + 4, colour: row.enabled ? Widgets.C.buttonText : Widgets.C.buttonOffText)
            case .stall, .close:
                Widgets.button(canvas, row.rect, label: row.label, enabled: row.enabled)
            }
        }
        PixelFont.draw(hint, on: canvas, x: r.x + (r.w - PixelFont.width(hint)) / 2, y: r.y + r.h - 31, colour: Widgets.C.ink)
    }

    private func advance(by dt: Double, visible: Bool, minute: Double = Clock.minute(at: Date()), time: Double? = nil) {
        let gardenOnScreen = visible && scene == .garden ? currentGarden : nil
        world.tick(dt, minute: minute, time: time ?? CACurrentMediaTime() - startTime, visibleGarden: gardenOnScreen)
        world.agePuffs(dt)
    }
}
