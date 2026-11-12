#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

enum GardenKind: String, Codable, CaseIterable {
    case clover, heather, bramble, lavender, yellowBox, orangeBlossom

    var title: String {
        switch self {
        case .clover: "Clover meadow"
        case .heather: "Heather moor"
        case .bramble: "Bramble hedgerow"
        case .lavender: "Lavender rows"
        case .yellowBox: "Yellow box grove"
        case .orangeBlossom: "Orange orchard"
        }
    }

    var honeyName: String {
        switch self {
        case .clover: "Clover"
        case .heather: "Heather"
        case .bramble: "Bramble"
        case .lavender: "Lavender"
        case .yellowBox: "Yellow box"
        case .orangeBlossom: "Orange blossom"
        }
    }

    static func forHoney(_ name: String) -> GardenKind? { allCases.first { $0.honeyName == name } }
}

struct HoneyColour {
    let body: RGB
    let hi: RGB
    let deep: RGB

    static func of(_ honey: String) -> HoneyColour {
        switch GardenKind.forHoney(honey) ?? .clover {
        case .clover: HoneyColour(body: RGB("#f0b93a"), hi: RGB("#ffdd7a"), deep: RGB("#d89a22"))
        case .heather: HoneyColour(body: RGB("#d9801c"), hi: RGB("#f2a548"), deep: RGB("#b4600f"))
        case .bramble: HoneyColour(body: RGB("#9a4a14"), hi: RGB("#c26d2a"), deep: RGB("#73330a"))
        case .lavender: HoneyColour(body: RGB("#f2cc6a"), hi: RGB("#fff0a8"), deep: RGB("#d8ac44"))
        case .yellowBox: HoneyColour(body: RGB("#e8a828"), hi: RGB("#ffd25e"), deep: RGB("#c4861a"))
        case .orangeBlossom: HoneyColour(body: RGB("#e9a43a"), hi: RGB("#ffcf7a"), deep: RGB("#c9832a"))
        }
    }
}

struct GroundPalette {
    let hills: [RGB]
    let ground: RGB
    let groundDark: RGB
    let groundLight: RGB
    let grass: RGB
    let shadow: RGB

    static func of(_ kind: GardenKind) -> GroundPalette {
        switch kind {
        case .clover:
            GroundPalette(hills: [RGB("#b3c27e"), RGB("#98b066")], ground: RGB("#7f9c47"), groundDark: RGB("#6c8b3c"), groundLight: RGB("#95ae56"), grass: RGB("#5f7f34"), shadow: RGB("#62813a"))
        case .heather:
            GroundPalette(hills: [RGB("#a99bb6"), RGB("#8c8aa0")], ground: RGB("#6f8a4c"), groundDark: RGB("#5e7a42"), groundLight: RGB("#869c5c"), grass: RGB("#4f6a3a"), shadow: RGB("#566f3c"))
        case .bramble:
            GroundPalette(hills: [RGB("#9fb070"), RGB("#7f9858")], ground: RGB("#6e8c40"), groundDark: RGB("#5c7a36"), groundLight: RGB("#84a04e"), grass: RGB("#4d6a2e"), shadow: RGB("#557234"))
        case .lavender:
            GroundPalette(hills: [RGB("#c4c890"), RGB("#aab47a")], ground: RGB("#a2ac68"), groundDark: RGB("#8e9a5a"), groundLight: RGB("#b6bd7c"), grass: RGB("#7c8a4a"), shadow: RGB("#88945a"))
        case .yellowBox:
            GroundPalette(hills: [RGB("#c8b47a"), RGB("#a89c68")], ground: RGB("#b0a05c"), groundDark: RGB("#9a8a4c"), groundLight: RGB("#c4b46e"), grass: RGB("#8a7a40"), shadow: RGB("#968650"))
        case .orangeBlossom:
            GroundPalette(hills: [RGB("#b6c27a"), RGB("#9cb062")], ground: RGB("#86a04a"), groundDark: RGB("#738e3e"), groundLight: RGB("#9ab45a"), grass: RGB("#647e36"), shadow: RGB("#6c8840"))
        }
    }
}

struct Flower {
    let x: Int
    let y: Int
    let height: Int
    let petal: RGB
    let centre: RGB
    let phase: Double

    var head: Point { Point(x: Double(x + 1), y: Double(y - height - 4)) }

    static func bed(for kind: GardenKind, seed: Int) -> [Flower] {
        var r = SeededRandom(seed: seed)
        let palette: [(String, String)]
        let count: Int
        let heights: ClosedRange<Int>
        switch kind {
        case .clover: palette = [("#f6f2e6", "#f2c94c"), ("#e8a0b4", "#f6e3a0"), ("#c592d8", "#f6e3a0"), ("#f6f2e6", "#e8a0b4")]; count = 26; heights = 5...10
        case .heather: palette = [("#a46cc0", "#c896d8"), ("#8e5aa8", "#b47ccc"), ("#c08ad0", "#e0b8e8")]; count = 30; heights = 2...4
        case .bramble: palette = [("#f6f0e8", "#f2d27a"), ("#f6f0e8", "#f2d27a"), ("#5a2a4a", "#3a1a30")]; count = 24; heights = 6...11
        case .lavender: palette = [("#8a6cc8", "#b49ce0"), ("#7a5cb8", "#a48cd8")]; count = 28; heights = 7...11
        case .yellowBox: palette = [("#f4ecc8", "#e8d48a"), ("#f8f2d8", "#ecd890")]; count = 20; heights = 8...13
        case .orangeBlossom: palette = [("#fbf6ee", "#f2b84a"), ("#fbf6ee", "#f08a2a"), ("#fbf6ee", "#f2b84a")]; count = 18; heights = 7...12
        }
        let span = Layout.height - Layout.horizon - 24
        return (0..<count).map { i in
            let colours = palette[i % palette.count]
            return Flower(
                x: Layout.flowerMinX + r.int(Layout.width - Layout.flowerMinX - 8), y: Layout.horizon + 18 + r.int(span),
                height: heights.lowerBound + r.int(heights.count), petal: RGB(colours.0), centre: RGB(colours.1), phase: r.next() * 6.28
            )
        }.sorted { $0.y < $1.y }
    }
}

final class Garden {
    let id: Int
    let kind: GardenKind
    let plot: Int
    let flowers: [Flower]
    var hornet: Hornet?
    var nextHornetIn: Double

    init(id: Int, kind: GardenKind, plot: Int, nextHornetIn: Double) {
        self.id = id
        self.kind = kind
        self.plot = plot
        self.nextHornetIn = nextHornetIn
        flowers = Flower.bed(for: kind, seed: 4242 + id * 131)
    }
}

final class Hive {
    let id: Int
    let name: String
    var garden: Int
    var x: Int
    var y: Int
    var honey: Double
    var hatchTimer = 0.0
    var queenEmergesIn: Double?
    var packing = false

    var isPacked: Bool { garden < 0 }

    init(id: Int, name: String, garden: Int, x: Int, y: Int, honey: Double, queenEmergesIn: Double? = nil) {
        self.id = id
        self.name = name
        self.garden = garden
        self.x = x
        self.y = y
        self.honey = honey
        self.queenEmergesIn = queenEmergesIn
    }

    var entrance: Point { Point(x: Double(x + 9), y: Double(y - 6)) }
    var isFull: Bool { honey >= 1 }
}

struct Jar: Codable {
    let honey: String
    let hiveName: String?
    let collectedAt: Date

    init(honey: String, hiveName: String?, collectedAt: Date) {
        self.honey = honey
        self.hiveName = hiveName
        self.collectedAt = collectedAt
    }

    private enum CodingKeys: String, CodingKey { case honey, hiveName, collectedAt, hive }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        honey = try c.decodeIfPresent(String.self, forKey: .honey) ?? c.decode(String.self, forKey: .hive)
        hiveName = try c.decodeIfPresent(String.self, forKey: .hiveName)
        collectedAt = try c.decode(Date.self, forKey: .collectedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(honey, forKey: .honey)
        try c.encodeIfPresent(hiveName, forKey: .hiveName)
        try c.encode(collectedAt, forKey: .collectedAt)
    }
}
