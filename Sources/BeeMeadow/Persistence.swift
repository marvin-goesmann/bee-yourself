import Foundation

private struct SaveV2: Codable {
    struct SavedGarden: Codable {
        let id: Int
        let kind: GardenKind
        let plot: Int
        let nextHornetIn: Double?
    }

    struct SavedBee: Codable {
        let id: Int
        let role: Bee.Role
    }

    struct SavedHive: Codable {
        let id: Int
        let name: String
        let garden: Int
        let x: Int
        let y: Int
        let honey: Double
        let queenEmergesIn: Double?
        let bees: [SavedBee]
    }

    let version: Int
    let savedAt: Date
    let gardens: [SavedGarden]
    let hives: [SavedHive]
    let jars: [Jar]
    let harvests: [Jar]
    let spareBoxes: Int
    let nextBeeID: Int
    let nextHiveID: Int
    let nextGardenID: Int
    let currentGarden: Int?
    let clockOffset: Double?
}

private struct SaveV1: Codable {
    struct SavedHive: Codable {
        let honey: Double
        let beeIDs: [Int]
        let roles: [Bee.Role]?
    }

    let savedAt: Date
    let hives: [SavedHive]
    let nextBeeID: Int
    let jars: [Jar]?
}

enum Persistence {
    nonisolated(unsafe) static var testFileURL: URL?

    static var fileURL: URL {
        if let testFileURL { return testFileURL }
        if let override = ProcessInfo.processInfo.environment["BEE_STATE_FILE"] { return URL(fileURLWithPath: override) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BeeMeadow", isDirectory: true).appendingPathComponent("state.json")
    }

    static func load(now: Date) -> (world: World, currentGarden: Int) {
        guard let data = try? Data(contentsOf: fileURL) else { return (World.fresh(), 0) }
        if let save = try? JSONDecoder.iso.decode(SaveV2.self, from: data), save.version == 2 {
            Clock.offset = save.clockOffset ?? 0
            let world = restore(save)
            world.catchUp(from: save.savedAt, to: now)
            let current = save.currentGarden.flatMap { id in world.garden(id)?.id } ?? world.gardens[0].id
            return (world, current)
        }
        if let save = try? JSONDecoder.iso.decode(SaveV1.self, from: data) {
            let world = migrate(save)
            world.catchUp(from: save.savedAt, to: now)
            return (world, 0)
        }
        return (World.fresh(), 0)
    }

    static func save(_ world: World, currentGarden: Int, now: Date) {
        let save = SaveV2(
            version: 2,
            savedAt: now,
            gardens: world.gardens.map { SaveV2.SavedGarden(id: $0.id, kind: $0.kind, plot: $0.plot, nextHornetIn: $0.nextHornetIn) },
            hives: world.hives.map { hive in
                SaveV2.SavedHive(
                    id: hive.id, name: hive.name, garden: hive.garden, x: hive.x, y: hive.y, honey: hive.honey, queenEmergesIn: hive.queenEmergesIn,
                    bees: world.bees.filter { $0.hive == hive.id }.map { SaveV2.SavedBee(id: $0.id, role: $0.role) }
                )
            },
            jars: world.jars, harvests: world.harvests, spareBoxes: world.spareBoxes,
            nextBeeID: world.nextBeeID, nextHiveID: world.nextHiveID, nextGardenID: world.nextGardenID, currentGarden: currentGarden, clockOffset: Clock.offset
        )
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.iso.encode(save).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("BeeMeadow: failed to save state: \(error)")
        }
    }

    private static func restore(_ save: SaveV2) -> World {
        let gardens = save.gardens.map { Garden(id: $0.id, kind: $0.kind, plot: $0.plot, nextHornetIn: $0.nextHornetIn ?? World.hornetMeanSeconds) }
        let hives = save.hives.map { Hive(id: $0.id, name: $0.name, garden: $0.garden, x: $0.x, y: $0.y, honey: $0.honey, queenEmergesIn: $0.queenEmergesIn) }
        let bees = save.hives.flatMap { hive in hive.bees.map { Bee(id: $0.id, hive: hive.id, role: $0.role) } }
        return World(
            gardens: gardens, hives: hives, bees: bees, jars: save.jars, harvests: save.harvests, spareBoxes: save.spareBoxes,
            nextBeeID: save.nextBeeID, nextHiveID: save.nextHiveID, nextGardenID: save.nextGardenID
        )
    }

    private static func migrate(_ save: SaveV1) -> World {
        let garden = Garden(id: 0, kind: .clover, plot: 4, nextHornetIn: World.hornetMeanSeconds)
        var hives: [Hive] = []
        var bees: [Bee] = []
        for (i, old) in save.hives.prefix(Layout.startingHiveSpots.count).enumerated() {
            let spot = Layout.startingHiveSpots[i]
            hives.append(Hive(id: i, name: World.names[i], garden: 0, x: spot.x, y: spot.y, honey: old.honey))
            for (k, id) in old.beeIDs.enumerated() {
                bees.append(Bee(id: id, hive: i, role: old.roles?[safe: k] ?? World.defaultRole(position: k)))
            }
        }
        let jars = save.jars ?? []
        return World(gardens: [garden], hives: hives, bees: bees, jars: jars, harvests: jars, spareBoxes: 0, nextBeeID: save.nextBeeID, nextHiveID: hives.count, nextGardenID: 1)
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
