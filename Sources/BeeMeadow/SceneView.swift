#if canImport(AppKit)
import AppKit
import QuartzCore

final class SceneView: NSView {
    private static let hiddenTickInterval = 0.5

    let game: Game
    private var link: CADisplayLink?
    private var hiddenTimer: Timer?
    private var lastTimestamp: CFTimeInterval?
    private let startTime = CACurrentMediaTime()

    init(game: Game) {
        self.game = game
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

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        if !game.click(pixelPoint(event)) { window?.performDrag(with: event) }
        updateCursor()
    }

    override func mouseDragged(with event: NSEvent) { game.dragged(to: pixelPoint(event)) }

    override func mouseUp(with event: NSEvent) {
        game.release(pixelPoint(event))
        updateCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        game.hover(pixelPoint(event))
        updateCursor()
    }

    override func mouseExited(with event: NSEvent) {
        game.hover(nil)
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 2 else { return }
        game.scroll(by: event.scrollingDeltaY > 0 ? -1 : 1)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else { super.keyDown(with: event); return }
        game.escape()
    }

    private func updateCursor() {
        let interactive = game.mouse.map(game.isInteractive) ?? false
        (interactive ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    private func pixelPoint(_ event: NSEvent) -> (x: Double, y: Double) {
        let local = convert(event.locationInWindow, from: nil)
        return (local.x / bounds.width * Double(Layout.width), (bounds.height - local.y) / bounds.height * Double(Layout.height))
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
            MainActor.assumeIsolated { self?.game.advance(by: Self.hiddenTickInterval, visible: false) }
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
        layer?.contents = game.step(dt: dt, minute: Clock.minute(at: Date()), time: CACurrentMediaTime() - startTime)?.makeImage()
    }
}
#endif
