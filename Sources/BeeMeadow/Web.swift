#if os(WASI)
import FoundationEssentials
import WASILibc

private enum Web {
    nonisolated(unsafe) static var game: Game?
    nonisolated(unsafe) static var dirty = false
    nonisolated(unsafe) static var saved: [UInt8] = []
}

@_expose(wasm, "bee_alloc")
@_cdecl("bee_alloc")
func beeAlloc(_ count: Int32) -> UnsafeMutableRawPointer {
    .allocate(byteCount: Int(max(1, count)), alignment: 1)
}

@_expose(wasm, "bee_set_utc_offset")
@_cdecl("bee_set_utc_offset")
func beeSetUTCOffset(_ seconds: Int32) {
    LocalDate.secondsFromUTC = { _ in Int(seconds) }
}

@_expose(wasm, "bee_start")
@_cdecl("bee_start")
func beeStart(_ save: UnsafeMutablePointer<UInt8>?, _ count: Int32) {
    var loaded = (world: World.fresh(), currentGarden: 0)
    if let save, count > 0 {
        loaded = Persistence.decode(Data(bytes: save, count: Int(count)), now: Date())
        save.deallocate()
    }
    let minute = Clock.minute(at: Date())
    for i in 0..<600 { loaded.world.tick(0.1, minute: minute, time: Double(i) * 0.1, visibleGarden: nil) }
    let game = Game(world: loaded.world, currentGarden: loaded.currentGarden)
    game.onChange = { Web.dirty = true }
    Web.game = game
}

@_expose(wasm, "bee_frame")
@_cdecl("bee_frame")
func beeFrame(_ dt: Double, _ time: Double) -> UnsafeMutablePointer<UInt8>? {
    Web.game?.step(dt: dt, minute: Clock.minute(at: Date()), time: time)?.pixels
}

@_expose(wasm, "bee_hidden")
@_cdecl("bee_hidden")
func beeHidden(_ dt: Double) { Web.game?.advance(by: dt, visible: false) }

@_expose(wasm, "bee_catch_up")
@_cdecl("bee_catch_up")
func beeCatchUp(_ seconds: Double) {
    let now = Date()
    Web.game?.world.catchUp(from: now.addingTimeInterval(-seconds), to: now)
}

@_expose(wasm, "bee_down")
@_cdecl("bee_down")
func beeDown(_ x: Double, _ y: Double) { Web.game?.click((x, y)) }

@_expose(wasm, "bee_drag")
@_cdecl("bee_drag")
func beeDrag(_ x: Double, _ y: Double) { Web.game?.dragged(to: (x, y)) }

@_expose(wasm, "bee_up")
@_cdecl("bee_up")
func beeUp(_ x: Double, _ y: Double) { Web.game?.release((x, y)) }

@_expose(wasm, "bee_hover")
@_cdecl("bee_hover")
func beeHover(_ x: Double, _ y: Double) { Web.game?.hover((x, y)) }

@_expose(wasm, "bee_leave")
@_cdecl("bee_leave")
func beeLeave() { Web.game?.hover(nil) }

@_expose(wasm, "bee_scroll")
@_cdecl("bee_scroll")
func beeScroll(_ delta: Int32) { Web.game?.scroll(by: Int(delta)) }

@_expose(wasm, "bee_escape")
@_cdecl("bee_escape")
func beeEscape() { Web.game?.escape() }

@_expose(wasm, "bee_pointer")
@_cdecl("bee_pointer")
func beePointer() -> Int32 {
    guard let game = Web.game, let mouse = game.mouse else { return 0 }
    return game.isInteractive(mouse) ? 1 : 0
}

@_expose(wasm, "bee_dirty")
@_cdecl("bee_dirty")
func beeDirty() -> Int32 {
    defer { Web.dirty = false }
    return Web.dirty ? 1 : 0
}

@_expose(wasm, "bee_save")
@_cdecl("bee_save")
func beeSave() -> Int32 {
    guard let game = Web.game, let data = try? Persistence.encode(game.world, currentGarden: game.currentGarden, now: Date()) else { return 0 }
    Web.saved = Array(data)
    return Int32(Web.saved.count)
}

@_expose(wasm, "bee_saved")
@_cdecl("bee_saved")
func beeSaved() -> UnsafePointer<UInt8>? {
    Web.saved.withUnsafeBufferPointer { $0.baseAddress }
}
#endif
