#if canImport(AppKit)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let floatKey = "floatOnTop"
    private static let saveInterval = 60.0
    private static let baseSize = NSSize(width: Layout.width, height: Layout.height)
    private static let minScale = 2.0

    private var window: NSWindow!
    private var world: World!
    private var sceneView: SceneView!
    private var saveTimer: Timer?
    private var floatItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.floatKey: false])
        let loaded = Persistence.load(now: Date())
        world = loaded.world
        warmUp()

        let size = NSSize(width: Self.baseSize.width * 3, height: Self.baseSize.height * 3)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Bee yourself"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = .black
        window.delegate = self
        sceneView = SceneView(game: Game(world: world, currentGarden: loaded.currentGarden))
        sceneView.game.onChange = { [weak self] in self?.save() }
        window.contentView = sceneView
        window.center()
        window.setFrameAutosaveName("BeeMeadowWindow")
        applyFloat(UserDefaults.standard.bool(forKey: Self.floatKey))
        buildMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        let timer = Timer(timeInterval: Self.saveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) { save() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let scale = max(Self.minScale, (frameSize.width / Self.baseSize.width).rounded())
        return NSSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
    }

    private func warmUp() {
        let minute = Clock.minute(at: Date())
        for i in 0..<600 { world.tick(0.1, minute: minute, time: Double(i) * 0.1, visibleGarden: nil) }
    }

    private func save() { Persistence.save(world, currentGarden: sceneView?.game.currentGarden ?? 0, now: Date()) }

    private func applyFloat(_ on: Bool) {
        window.level = on ? .floating : .normal
        window.collectionBehavior = on ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        floatItem?.state = on ? .on : .off
    }

    @objc private func toggleFloat() {
        let on = !UserDefaults.standard.bool(forKey: Self.floatKey)
        UserDefaults.standard.set(on, forKey: Self.floatKey)
        applyFloat(on)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        floatItem = NSMenuItem(title: "Float on Top", action: #selector(toggleFloat), keyEquivalent: "t")
        floatItem.target = self
        floatItem.state = UserDefaults.standard.bool(forKey: Self.floatKey) ? .on : .off
        appMenu.addItem(floatItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Bee yourself", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}
#endif
