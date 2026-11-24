#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum HelperKind: String, Codable, CaseIterable {
    case bear, badger, hedgehog, mouse

    var title: String {
        switch self {
        case .bear: return "Bear"
        case .badger: return "Badger"
        case .hedgehog: return "Hedgehog"
        case .mouse: return "Mouse"
        }
    }

    var worksAtNight: Bool { self == .mouse }

    func isAwake(activity: Double) -> Bool { worksAtNight || activity > 0.1 }
}

final class Helper {
    enum Task {
        case idle(wait: Double)
        case toHive(Int)
        case collecting(Int, wait: Double)
        case home
        case stroll(x: Double, y: Double)
        case nap(wait: Double)
    }

    let id: Int
    let kind: HelperKind
    var garden: Int
    var x: Double
    var y: Double
    var home: (x: Int, y: Int)
    var facing = 1.0
    var task = Task.idle(wait: 1)
    var carrying = false
    var asleep = false
    var walked = 0.0
    var heart = 0.0

    static let shed = -1
    static let homeless = -2

    var isStored: Bool { garden == Helper.shed }
    var isHomeless: Bool { garden == Helper.homeless }

    var isWalking: Bool {
        switch task {
        case .toHive, .home, .stroll: return true
        default: return false
        }
    }

    var isNapping: Bool {
        if case .nap = task { return true }
        return false
    }

    func pet() {
        heart = 1.2
        if isNapping { task = .idle(wait: 1.5) }
    }

    init(id: Int, kind: HelperKind, garden: Int, x: Int, y: Int) {
        self.id = id
        self.kind = kind
        self.garden = garden
        self.x = Double(x)
        self.y = Double(y)
        home = (x, y)
    }

    func settle(at x: Int, _ y: Int) {
        home = (x, y)
        self.x = Double(x)
        self.y = Double(y)
        task = .idle(wait: 1)
        carrying = false
    }
}

enum HelperSprite {
    enum Pose { case idle, blink, walk, carry, sleep }

    static let size = 16

    private struct Spec {
        let body: [String]
        let stand: [String], a: [String], b: [String]
        let eyes: [(Int, Int)]
        let fur: Character
        var closed: Character?
        let jar: (Int, Int)
        let paws: [(Int, Int)]
        let z: (Int, Int)
        var side = false
        var lantern: (Int, Int)?
    }

    private static let palette: [Character: RGB] = [
        "k": RGB("#3b2416"), "t": RGB("#f0cf72"), "T": RGB("#c99a44"), "w": RGB("#fff6dc"),
        "b": RGB("#a8683a"), "B": RGB("#7a4a2a"), "l": RGB("#e6b884"), "n": RGB("#2a1a10"),
        "d": RGB("#3a3434"), "D": RGB("#24201f"), "u": RGB("#5a7ab0"), "U": RGB("#3f5a88"), "s": RGB("#ffc24a"), "e": RGB("#fff6dc"), "p": RGB("#e8a0a8"),
        "S": RGB("#6b4a2e"), "x": RGB("#a07850"), "f": RGB("#ecd3a4"), "F": RGB("#c8a070"),
        "m": RGB("#b0a4a0"), "M": RGB("#8a7e7a"), "r": RGB("#c4573f"),
        "j": RGB("#e8961e"), "J": RGB("#ffc24a"), "g": RGB("#c4573f"), "Y": RGB("#fff6d2"), "L": RGB("#ffd68c"), "z": RGB("#fff6dc"),
    ]

    private static let jar = [".kkkk.", "kggggk", "kJjjjk", "kJjjjk", "kjjjjk", ".kkkk."]
    private static let lantern = ["..k..", ".kkk.", "kYYYk", "kLYLk", "kLLLk", ".kkk."]
    private static let zee = ["zzzz", "..z.", ".z..", "zzzz"]

    private static let specs: [HelperKind: Spec] = [
        .bear: Spec(
            body: [
                "................",
                "......kkkk......",
                ".....kttttk.....",
                ".....krrrrk.....",
                ".kTTTTTTTTTTTTk.",
                ".kbkkkkkkkkkkbk.",
                "..kbbnbbbbnbbk..",
                "..kbbbllllbbbk..",
                "..kbbblnnlbbbk..",
                "...kbbbbbbbbk...",
                "..kBbbbbbbbbBk..",
                ".kBbbllllllbbBk.",
                ".kBbllllllllbBk.",
                "..kBbllllllbBk..",
            ],
            stand: ["...kBBk..kBBk...", "...kkkk..kkkk..."],
            a: ["...kkkk..kBBk...", ".........kkkk..."],
            b: ["...kBBk..kkkk...", "...kkkk........."],
            eyes: [(5, 6), (10, 6)], fur: "b", jar: (5, 9), paws: [(4, 12), (11, 12)], z: (13, 1)),
        .badger: Spec(
            body: [
                "................",
                "................",
                "....kk....kk....",
                "...kdDkkkkDdk...",
                "...kwwwwwwwwk...",
                "..kwwwwwwwwwwk..",
                "..kdddwwwwdddk..",
                "..kddeddddeddk..",
                "..kddddppddddk..",
                "...kddddddddk...",
                "..kdUddddddUdk..",
                ".kddUsuuuusUddk.",
                ".kdduuuuuuuuddk.",
                "..kkuuuuuuuukk..",
            ],
            stand: ["...kUUk..kUUk...", "...kDDk..kDDk..."],
            a: ["...kDDk..kUUk...", "...kkk...kDDk..."],
            b: ["...kUUk..kDDk...", "...kDDk...kkk..."],
            eyes: [(5, 7), (10, 7)], fur: "d", closed: "D", jar: (5, 9), paws: [(4, 12), (11, 12)], z: (13, 1)),
        .hedgehog: Spec(
            body: [
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "....kkkkkk.w....",
                "...kSxSxSxwsw...",
                "..kSxSxSxSxw....",
                ".kSxSxSxSxSfk...",
                ".kxSxSxSxSfkfk..",
                ".kSxSxSxSffffnk.",
                "..kSxSxSffffk...",
                "...kkkkkkkkk....",
            ],
            stand: ["....kFk..kFk....", "....kk...kk....."],
            a: ["...kFk...kFk....", "...kk.....kk...."],
            b: [".....kFkkFk.....", ".....kk.kk......"],
            eyes: [(11, 10)], fur: "f", jar: (3, 4), paws: [], z: (12, 2), side: true),
        .mouse: Spec(
            body: [
                "................",
                "................",
                "..kkk....kkk....",
                ".kMppk..kppMk...",
                ".kMppkkkkppMk...",
                "..kkmmmmmmkk....",
                "...kmmmmmmk.....",
                "...kmkmmkmk.....",
                "...kmmppmmk.....",
                "....kmmmmk......",
                "...krrrrrrk.....",
                "..kmrwwwwrmk....",
                "..kmwwwwwwmk..k.",
                "...kwwwwwwkkkmk.",
            ],
            stand: ["...kmk..kmk.....", "...kkk..kkk....."],
            a: ["...kkk..kmk.....", "........kkk....."],
            b: ["...kmk..kkk.....", "...kkk.........."],
            eyes: [(5, 7), (8, 7)], fur: "m", jar: (4, 8), paws: [(3, 11), (10, 11)], z: (12, 0), lantern: (11, 7)),
    ]

    static func draw(_ kind: HelperKind, on canvas: PixelCanvas, x: Int, y: Int, pose: Pose, frame: Int, flip: Bool = false, lantern: Bool = false, dim: Double = 0, scale: Int = 1, rows: Range<Int> = 0..<size) {
        let grid = compose(kind, pose: pose, frame: frame, lantern: lantern)
        for (j, row) in grid.enumerated() where rows.contains(j) {
            for (i, ch) in row.enumerated() {
                guard let ch, var colour = palette[ch] else { continue }
                if dim > 0 { colour = colour.mixed(with: Widgets.C.buttonOff, dim) }
                let px = flip ? size - 1 - i : i
                canvas.fill(Double(x + px * scale), Double(y + (j - rows.lowerBound) * scale), scale, scale, colour)
            }
        }
    }

    static func portrait(_ kind: HelperKind, on canvas: PixelCanvas, x: Int, y: Int, dim: Bool) {
        let top: Int
        switch kind {
        case .bear: top = 1
        case .badger, .mouse: top = 2
        case .hedgehog: top = 5
        }
        draw(kind, on: canvas, x: x, y: y, pose: .idle, frame: 0, dim: dim ? 0.6 : 0, rows: top..<top + 10)
    }

    static func lanternPoint(_ kind: HelperKind, pose: Pose, frame: Int) -> (x: Int, y: Int)? {
        guard let spot = specs[kind]?.lantern, pose != .sleep else { return nil }
        return (spot.0 + 2, spot.1 + 3 - hop(pose: pose, frame: frame))
    }

    private static func hop(pose: Pose, frame: Int) -> Int {
        (pose == .walk || pose == .carry) && frame % 2 == 0 ? 1 : 0
    }

    private static func compose(_ kind: HelperKind, pose: Pose, frame: Int, lantern showLantern: Bool) -> [[Character?]] {
        guard let spec = specs[kind] else { return [] }
        var grid = [[Character?]](repeating: [Character?](repeating: nil, count: size), count: size)
        func stamp(_ art: [String], _ ox: Int, _ oy: Int) {
            for (j, row) in art.enumerated() {
                for (i, ch) in row.enumerated() where ch != "." {
                    let x = ox + i, y = oy + j
                    if x >= 0, x < size, y >= 0, y < size { grid[y][x] = ch }
                }
            }
        }
        var body = spec.body.map { Array($0) }
        if pose == .blink || pose == .sleep {
            for (n, (x, y)) in spec.eyes.enumerated() {
                if let closed = spec.closed { body[y][x] = closed; continue }
                body[y][x] = "k"
                body[y][x + (n == 0 && !spec.side ? -1 : 1)] = "k"
            }
        }
        let rows = body.map { String($0) }
        let sitting = pose == .sleep
        let lift = hop(pose: pose, frame: frame)
        let dy = sitting ? 2 : -lift
        if sitting {
            stamp(rows, 0, 2)
        } else {
            stamp(rows, 0, -lift)
            let walking = pose == .walk || pose == .carry
            let feet = !walking || frame % 2 == 1 ? spec.stand : frame % 4 == 0 ? spec.a : spec.b
            stamp(feet, 0, rows.count - lift)
        }
        if pose == .carry {
            stamp(jar, spec.jar.0, spec.jar.1 + dy)
            for (x, y) in spec.paws where y + dy >= 0 && y + dy < size { grid[y + dy][x] = spec.fur }
        }
        if showLantern, let spot = spec.lantern, !sitting {
            stamp(lantern, spot.0, spot.1 + dy)
            grid[11 + dy][11] = "m"
            grid[10 + dy][12] = "k"
        }
        if sitting { stamp(zee, spec.z.0, spec.z.1 + (frame % 2 == 0 ? 1 : 0)) }
        return grid
    }
}

extension HelperSprite {
    private static func pose(_ h: Helper, time: Double) -> (pose: HelperSprite.Pose, frame: Int) {
        if h.isWalking { return (h.carrying ? .carry : .walk, Int(h.walked * 8)) }
        if h.asleep || h.isNapping { return (.sleep, Int(time * 1.2)) }
        let blink = (time + Double(h.id) * 1.7).truncatingRemainder(dividingBy: 3.6) < 0.15
        return (blink ? .blink : .idle, 0)
    }

    static func drawInScene(_ h: Helper, on canvas: PixelCanvas, time: Double, dark: Double) {
        let (pose, frame) = pose(h, time: time)
        let x = Int(h.x.rounded()), y = Int(h.y.rounded())
        canvas.fill(Double(x - 5), Double(y + 1), 10, 1, RGB("#000000"), alpha: 0.18)
        draw(h.kind, on: canvas, x: x - 8, y: y - 15, pose: pose, frame: frame, flip: h.facing < 0, lantern: h.kind == .mouse && dark > 0.3)
    }

    static func drawGlow(_ h: Helper, on canvas: PixelCanvas, time: Double, dark: Double) {
        guard h.kind == .mouse, dark > 0.3 else { return }
        let (pose, frame) = pose(h, time: time)
        guard let p = HelperSprite.lanternPoint(h.kind, pose: pose, frame: frame) else { return }
        let lx = Double(h.facing < 0 ? Int(h.x.rounded()) - 8 + 15 - p.x : Int(h.x.rounded()) - 8 + p.x), ly = Double(Int(h.y.rounded()) - 15 + p.y)
        let k = dark * (0.9 + 0.1 * sin(time * 6))
        for y in -9...9 { for x in -9...9 where x * x + y * y <= 81 { canvas.fill(lx + Double(x), ly + Double(y), 1, 1, RGB("#ffd68c"), alpha: 0.08 * k) } }
    }

    static func drawHeart(_ h: Helper, on canvas: PixelCanvas) {
        guard h.heart > 0 else { return }
        let rows = [".rr.rr.", "rwrrrrr", "rrrrrrr", ".rrrrr.", "..rrr..", "...r..."]
        let rise = (1.2 - h.heart) * 8, alpha = min(1, h.heart / 0.4)
        let ox = Int(h.x.rounded()) - 3, oy = Int((h.y - 24 - rise).rounded())
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() where ch != "." {
                canvas.fill(Double(ox + i), Double(oy + j), 1, 1, ch == "w" ? RGB("#ffb3bd") : RGB("#e0485a"), alpha: alpha)
            }
        }
    }
}
