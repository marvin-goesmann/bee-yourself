#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#endif

enum Layout {
    static let width = 240
    static let height = 180
    static let horizon = 106
    static let flowerMinX = 124
    static let lantern = (x: 112, y: 142)
    static let startingHiveSpots = [(x: 20, y: 146), (x: 54, y: 130), (x: 88, y: 158)]
    static let hiveArea = (minX: 4, maxX: 100, minY: 126, maxY: 172)
    static let plots = 9
}

struct Point {
    var x: Double
    var y: Double
}

struct SeededRandom {
    private var seed: Int64

    init(seed: Int) { self.seed = max(1, Int64(seed)) }

    mutating func next() -> Double {
        seed = (seed * 16807) % 2_147_483_647
        return Double(seed - 1) / 2_147_483_646
    }

    mutating func int(_ upper: Int) -> Int { Int(next() * Double(upper)) }
}

struct Bee {
    enum Role: String, Codable {
        case queen, house, forager
    }

    enum State {
        case inside(wait: Double)
        case flyingOut
        case feeding(wait: Double)
        case flyingHome
        case returning
        case relocating(target: Int, stage: Int, wait: Double)
        case defending
    }

    let id: Int
    var hive: Int
    let role: Role
    var hatchedAt: Double?
    var state: State = .inside(wait: 0)
    var flower = 0
    var trip = (a: Point(x: 0, y: 0), c: Point(x: 0, y: 0), z: Point(x: 0, y: 0))
    var progress = 0.0
    var duration = 1.0
    var position = Point(x: 0, y: 0)
    var facing = 1.0
    var wobble = 0.0

    var isOutside: Bool {
        switch state {
        case .inside: return false
        case .relocating(_, let stage, _): return stage >= 2
        default: return true
        }
    }

    var isCarrying: Bool {
        if case .flyingHome = state { return true }
        return false
    }
}

struct Hornet {
    enum Phase { case approach, hover, balled, flee }

    var x: Double
    var y: Double
    var facing = -1.0
    var phase = Phase.approach
    var t = 0.0
    let hive: Int
    var catches = 0
    let maxCatches: Int
    var cooldown = 1.5
    var prey: Int?
    var defenders: [Int] = []
    var ballAngle = 0.0
}

final class World {
    static let colonyStrength = 36
    static let foragerShare = 0.6
    static let hatchSeconds = 150.0
    static let queenSeconds = 300.0
    static let flightSpeed = 24.0
    static let tripYield = 1.0 / 1550
    static let tripsPerForagerMinute = 3.5
    static let hivesPerGarden = 4
    static let hiveBoxPrice = 3
    static let helperPrice = 20
    static let helperSpeed = 16.0
    static let helperArea = (minX: 8, maxX: 232, minY: Layout.horizon + 14, maxY: 174)
    static let hornetMeanSeconds = 7200.0
    static let factoryPrice = 1000
    static let factoryHoneyName = "Blended"
    static let factoryName = "Factory"
    static let ringPriceMultiplier = 10
    static let fullValleyHives = Layout.plots * hivesPerGarden
    static let fullStrengthForagers = Int((Double(colonyStrength) * foragerShare).rounded(.up))
    static let factoryJarsPerMinute = 2 * Double(fullValleyHives * fullStrengthForagers) * tripsPerForagerMinute * tripYield
    static let campArea = (minX: 10, maxX: 64, minY: 150, maxY: 172)
    static let names = [
        "Pip", "Hazel", "Juniper", "Willow", "Fern", "Maple", "Poppy", "Sorrel", "Wren", "Acorn", "Pebble", "Thistle", "Marigold",
        "Sage", "Rowan", "Nutmeg", "Biscuit", "Moss", "Dandelion", "Button", "Clove", "Tansy", "Ember", "Olive", "Cobble",
        "Basil", "Linden", "Bracken", "Sparrow", "Daisy", "Elm", "Bumble", "Clementine", "Truffle", "Barley", "Saffron",
    ]

    var gardens: [Garden]
    var hives: [Hive]
    var bees: [Bee]
    var jars: [Jar]
    var harvests: [Jar]
    var spareBoxes: Int
    var helpers: [Helper]
    var nextBeeID: Int
    var nextHiveID: Int
    var nextGardenID: Int
    var hasFactory: Bool
    var factoryHoney: Double
    var completedTrips = 0
    var hornetsEnabled = true
    private(set) var clock = 0.0
    private var hiveByID: [Int: Hive] = [:]
    private var random = SeededRandom(seed: Int(Date().timeIntervalSince1970) % 100_000 + 1)

    init(gardens: [Garden], hives: [Hive], bees: [Bee], jars: [Jar], harvests: [Jar], spareBoxes: Int, nextBeeID: Int, nextHiveID: Int, nextGardenID: Int, helpers: [Helper] = [], hasFactory: Bool = false, factoryHoney: Double = 0) {
        self.gardens = gardens
        self.hives = hives
        self.bees = bees
        self.jars = jars
        self.harvests = harvests
        self.spareBoxes = spareBoxes
        self.helpers = helpers
        self.nextBeeID = nextBeeID
        self.nextHiveID = nextHiveID
        self.nextGardenID = nextGardenID
        self.hasFactory = hasFactory
        self.factoryHoney = factoryHoney
        reindex()
        for i in self.bees.indices {
            self.bees[i].wobble = random.next() * 6.28
            self.bees[i].state = .inside(wait: random.next() * 6)
        }
    }

    static func fresh() -> World {
        let gardens = [
            Garden(id: 0, kind: .clover, plot: 4, nextHornetIn: hornetMeanSeconds),
            Garden(id: 1, kind: .lavender, plot: 5, nextHornetIn: hornetMeanSeconds),
        ]
        let spot = Layout.startingHiveSpots[1]
        let hives = gardens.enumerated().map { i, garden in
            Hive(id: i, name: names[i], garden: garden.id, x: spot.x, y: spot.y, honey: [0.55, 0.3][i])
        }
        let bees = startingBees(for: hives)
        return World(gardens: gardens, hives: hives, bees: bees, jars: [], harvests: [], spareBoxes: 1, nextBeeID: bees.count, nextHiveID: hives.count, nextGardenID: gardens.count)
    }

    #if canImport(AppKit)
    static func classic() -> World {
        let garden = Garden(id: 0, kind: .clover, plot: 4, nextHornetIn: hornetMeanSeconds)
        let hives = Layout.startingHiveSpots.enumerated().map { i, spot in
            Hive(id: i, name: names[i], garden: 0, x: spot.x, y: spot.y, honey: [0.55, 0.3, 0.1][i])
        }
        let bees = startingBees(for: hives)
        return World(gardens: [garden], hives: hives, bees: bees, jars: [], harvests: [], spareBoxes: 0, nextBeeID: bees.count, nextHiveID: hives.count, nextGardenID: 1)
    }
    #endif

    private static func startingBees(for hives: [Hive]) -> [Bee] {
        var bees: [Bee] = []
        for hive in hives {
            for position in 0..<34 { bees.append(Bee(id: bees.count, hive: hive.id, role: defaultRole(position: position))) }
        }
        return bees
    }

    static func defaultRole(position: Int) -> Bee.Role {
        if position == 0 { return .queen }
        return position <= 13 ? .house : .forager
    }

    // MARK: Lookups

    func hive(_ id: Int) -> Hive? { hiveByID[id] }

    func garden(_ id: Int) -> Garden? { gardens.first { $0.id == id } }

    func hives(in garden: Int) -> [Hive] { hives.filter { $0.garden == garden } }

    var packedHives: [Hive] { hives.filter(\.isPacked) }

    var storedHelpers: [Helper] { helpers.filter(\.isStored) }

    var canHireHelper: Bool { helpers.filter { !$0.isHomeless }.count < gardens.count }

    var homelessHelpers: [Helper] { helpers.filter(\.isHomeless) }

    func helper(in garden: Int) -> Helper? { helpers.first { $0.garden == garden } }

    func helper(_ id: Int) -> Helper? { helpers.first { $0.id == id } }

    func canPlaceHelper(x: Int, y: Int) -> Bool {
        let a = World.helperArea
        return x >= a.minX && x <= a.maxX && y >= a.minY && y <= a.maxY
    }

    func hasRoom(in garden: Int) -> Bool { hives(in: garden).count < World.hivesPerGarden }

    func beeCount(hive: Int) -> Int { bees.reduce(0) { $0 + ($1.hive == hive && !isLeaving($1) ? 1 : 0) } }

    func foragerCount(hive: Int) -> Int { bees.reduce(0) { $0 + ($1.hive == hive && $1.role == .forager ? 1 : 0) } }

    func hasQueen(hive: Int) -> Bool { bees.contains { $0.hive == hive && $0.role == .queen } }

    func isEmptyBox(_ hive: Hive) -> Bool { hive.queenEmergesIn == nil && !bees.contains { $0.hive == hive.id } && !bees.contains { isHeading(to: hive.id, $0) } }

    func readyToSplit(_ hive: Hive) -> Bool { hasQueen(hive: hive.id) && beeCount(hive: hive.id) >= World.colonyStrength / 2 }

    func atFullStrength(_ hive: Hive) -> Bool { beeCount(hive: hive.id) >= World.colonyStrength }

    func splitTarget(for source: Hive) -> Hive? {
        let empty = hives.filter { $0.id != source.id && !$0.isPacked && !$0.packing && isEmptyBox($0) }
        return empty.first { $0.garden == source.garden } ?? empty.first
    }

    func gardens(in valley: Valley) -> [Garden] { gardens.filter { $0.valley == valley } }

    func garden(in valley: Valley, plot: Int) -> Garden? { gardens.first { $0.valley == valley && $0.plot == plot } }

    func priceMultiplier(in valley: Valley) -> Int {
        (0..<valley.ring).reduce(1) { total, _ in total * World.ringPriceMultiplier }
    }

    func gardenPrice(in valley: Valley = .home) -> Int {
        let extra = max(0, gardens(in: valley).count - 2)
        return (10 + extra * (extra + 3)) * priceMultiplier(in: valley)
    }

    func hiveBoxPrice(in valley: Valley) -> Int { World.hiveBoxPrice * priceMultiplier(in: valley) }

    func helperPrice(in valley: Valley) -> Int { World.helperPrice * priceMultiplier(in: valley) }

    func freePlots(in valley: Valley = .home) -> [Int] { (0..<Layout.plots).filter { garden(in: valley, plot: $0) == nil } }

    var canBuildFactory: Bool { !hasFactory && jars.count >= World.factoryPrice }

    static func valleys(inRing ring: Int) -> [Valley] {
        guard ring > 0 else { return [.home] }
        return (-ring...ring).flatMap { y in (-ring...ring).map { x in Valley(x: x, y: y) } }.filter { $0.ring == ring }
    }

    var openRing: Int {
        guard hasFactory else { return 0 }
        var ring = 1
        while World.valleys(inRing: ring).allSatisfy({ !gardens(in: $0).isEmpty }) { ring += 1 }
        return ring
    }

    func isOpen(_ valley: Valley) -> Bool {
        hasFactory ? valley.ring >= 1 && valley.ring <= openRing : valley == .home
    }

    private func isLeaving(_ bee: Bee) -> Bool {
        if case .relocating(_, let stage, _) = bee.state { return stage >= 1 }
        return false
    }

    private func isHeading(to hive: Int, _ bee: Bee) -> Bool {
        if case .relocating(let target, _, _) = bee.state { return target == hive }
        return false
    }

    private func reindex() { hiveByID = Dictionary(uniqueKeysWithValues: hives.map { ($0.id, $0) }) }

    // MARK: Actions

    @discardableResult
    func collect(hive id: Int, at date: Date) -> Jar? {
        guard let hive = hive(id), hive.isFull, let garden = garden(hive.garden) else { return nil }
        hive.honey = 0
        let jar = Jar(honey: garden.kind.honeyName, hiveName: hive.name, collectedAt: date)
        jars.append(jar)
        harvests.append(jar)
        return jar
    }

    func buyHiveBox(in valley: Valley = .home) -> Bool {
        let price = hiveBoxPrice(in: valley)
        guard jars.count >= price else { return false }
        jars.removeFirst(price)
        spareBoxes += 1
        return true
    }

    func hireHelper(_ kind: HelperKind, in valley: Valley = .home) -> Helper? {
        let price = helperPrice(in: valley)
        guard jars.count >= price, canHireHelper else { return nil }
        jars.removeFirst(price)
        let helper = Helper(id: (helpers.map(\.id).max() ?? -1) + 1, kind: kind, garden: Helper.shed, x: 0, y: 0)
        helpers.append(helper)
        return helper
    }

    func placeHelper(_ id: Int, x: Int, y: Int, in garden: Int) -> Bool {
        guard let helper = helper(id), helper.isStored, self.helper(in: garden) == nil, canPlaceHelper(x: x, y: y) else { return false }
        helper.garden = garden
        helper.settle(at: x, y)
        return true
    }

    func moveHelper(_ id: Int, x: Int, y: Int) -> Bool {
        guard let helper = helper(id), !helper.isStored, !helper.isHomeless, canPlaceHelper(x: x, y: y) else { return false }
        helper.settle(at: x, y)
        return true
    }

    func storeHelper(_ id: Int) {
        guard let helper = helper(id), !helper.isHomeless else { return }
        helper.garden = Helper.shed
        helper.settle(at: 0, 0)
    }

    func buyGarden(kind: GardenKind, plot: Int, in valley: Valley = .home) -> Garden? {
        let price = gardenPrice(in: valley)
        guard jars.count >= price, isOpen(valley), freePlots(in: valley).contains(plot) else { return nil }
        jars.removeFirst(price)
        let garden = Garden(id: nextGardenID, kind: kind, valley: valley, plot: plot, nextHornetIn: World.hornetMeanSeconds)
        nextGardenID += 1
        gardens.append(garden)
        if !hasColony { addSwarm(to: garden) }
        return garden
    }

    var hasColony: Bool { bees.contains { $0.role == .queen } || hives.contains { $0.queenEmergesIn != nil } }

    private func addSwarm(to garden: Garden) {
        let spot = Layout.startingHiveSpots[1], used = Set(hives.map(\.name))
        let hive = Hive(id: nextHiveID, name: World.names.first { !used.contains($0) } ?? "Hive \(nextHiveID + 1)", garden: garden.id, x: spot.x, y: spot.y, honey: 0)
        nextHiveID += 1
        hives.append(hive)
        reindex()
        for position in 0..<World.colonyStrength / 2 {
            bees.append(Bee(id: nextBeeID, hive: hive.id, role: World.defaultRole(position: position), state: .inside(wait: random.next() * 6), wobble: random.next() * 6.28))
            nextBeeID += 1
        }
    }

    func canPlace(x: Int, y: Int, in garden: Int, ignoring: Int? = nil) -> Bool {
        let a = Layout.hiveArea
        guard x >= a.minX, x <= a.maxX, y >= a.minY, y <= a.maxY else { return false }
        return !hives(in: garden).contains { other in
            other.id != ignoring && abs(other.x - x) < 24 && abs(other.y - y) < 18
        }
    }

    func placeBox(x: Int, y: Int, in garden: Int) -> Bool {
        guard spareBoxes > 0, hasRoom(in: garden), canPlace(x: x, y: y, in: garden) else { return false }
        spareBoxes -= 1
        let used = Set(hives.map(\.name))
        let name = World.names.first { !used.contains($0) } ?? "Hive \(nextHiveID + 1)"
        hives.append(Hive(id: nextHiveID, name: name, garden: garden, x: x, y: y, honey: 0))
        nextHiveID += 1
        reindex()
        return true
    }

    func move(hive id: Int, x: Int, y: Int) -> Bool {
        guard let hive = hive(id), canPlace(x: x, y: y, in: hive.garden, ignoring: id) else { return false }
        hive.x = x
        hive.y = y
        for i in bees.indices where bees[i].hive == id {
            if case .flyingHome = bees[i].state { bees[i].trip.z = hive.entrance }
            if case .returning = bees[i].state { bees[i].trip.z = hive.entrance }
        }
        return true
    }

    enum PackResult { case packing, busy }

    func pack(hive id: Int) -> PackResult {
        guard let hive = hive(id), !hive.isPacked, !hive.packing else { return .busy }
        let moving = bees.contains { bee in
            guard case .relocating(let target, _, _) = bee.state else { return false }
            return bee.hive == id || target == id
        }
        if moving || hive.queenEmergesIn != nil && bees.contains(where: { isHeading(to: id, $0) }) { return .busy }
        if let garden = garden(hive.garden), garden.hornet?.hive == id { return .busy }
        hive.packing = true
        for i in bees.indices where bees[i].hive == id && bees[i].isOutside {
            setTrip(&bees[i], from: bees[i].position, to: hive.entrance, arc: 0.3)
            bees[i].duration = min(bees[i].duration, 1.2)
            bees[i].state = .returning
        }
        return .packing
    }

    func unpack(hive id: Int, x: Int, y: Int, in garden: Int) -> Bool {
        guard let hive = hive(id), hive.isPacked, hasRoom(in: garden), canPlace(x: x, y: y, in: garden) else { return false }
        hive.garden = garden
        hive.x = x
        hive.y = y
        for i in bees.indices where bees[i].hive == id { bees[i].state = .inside(wait: 1 + random.next() * 5) }
        return true
    }

    private func finishPacking() {
        for hive in hives where hive.packing && !bees.contains(where: { $0.hive == hive.id && $0.isOutside }) {
            hive.packing = false
            if bees.contains(where: { $0.hive == hive.id }) || hive.queenEmergesIn != nil {
                hive.garden = -1
            } else {
                hives.removeAll { $0.id == hive.id }
                spareBoxes += 1
                reindex()
            }
        }
    }

    func buildFactory() -> Bool {
        guard canBuildFactory else { return false }
        jars.removeFirst(World.factoryPrice)
        let absorbed = Set(gardens(in: .home).map(\.id))
        let lostHives = Set(hives.filter { absorbed.contains($0.garden) }.map(\.id))
        gardens.removeAll { absorbed.contains($0.id) }
        hives.removeAll { lostHives.contains($0.id) }
        bees.removeAll { lostHives.contains($0.hive) }
        reindex()
        let camp = World.campArea
        for (i, helper) in helpers.enumerated() {
            helper.garden = Helper.homeless
            helper.settle(at: camp.minX + 6 + (i * 19) % (camp.maxX - camp.minX - 6), camp.minY + 4 + (i * 9) % (camp.maxY - camp.minY - 4))
        }
        hasFactory = true
        return true
    }

    func split(hive id: Int) -> Hive? {
        guard let source = hive(id), readyToSplit(source), let target = splitTarget(for: source) else { return nil }
        target.queenEmergesIn = World.queenSeconds
        target.honey = 0
        let movers = bees.indices.filter { bees[$0].hive == id && bees[$0].role != .queen }.shuffled()
            .sorted { !bees[$0].isOutside && bees[$1].isOutside }
        for (n, i) in movers.prefix(movers.count / 2).enumerated() {
            bees[i].state = .relocating(target: target.id, stage: 0, wait: Double(n) * 0.6 + random.next() * 0.5)
        }
        return target
    }

    // MARK: Simulation

    func tick(_ dt: Double, minute: Double, time: Double, visibleGarden: Int?) {
        clock += dt
        let activity = Clock.activity(minute)
        for i in bees.indices { step(i, dt: dt, activity: activity, time: time) }
        bees.removeAll { $0.hive < 0 }
        var census: [Int: (bees: Int, queen: Bool)] = [:]
        for bee in bees where !isLeaving(bee) {
            let current = census[bee.hive] ?? (0, false)
            census[bee.hive] = (current.bees + 1, current.queen || bee.role == .queen)
        }
        for hive in hives where !hive.isPacked { grow(hive, dt: dt, census: census[hive.id] ?? (0, false)) }
        finishPacking()
        for helper in helpers where !helper.isStored { step(helper, dt: dt, activity: activity) }
        runFactory(seconds: dt, at: Date())
        if let visibleGarden, let garden = garden(visibleGarden) { updateHornet(garden, dt: dt, activity: activity, time: time) }
    }

    private func step(_ i: Int, dt: Double, activity: Double, time: Double) {
        var bee = bees[i]
        defer { bees[i] = bee }
        if case .relocating(let target, let stage, let wait) = bee.state {
            relocate(&bee, target: target, stage: stage, wait: wait, dt: dt, time: time)
            return
        }
        guard bee.role == .forager || isFlying(bee) else { return }
        if let hive = hive(bee.hive), hive.isPacked || (hive.packing && !isFlying(bee)) {
            if case .inside = bee.state { return }
            if case .returning = bee.state {} else { return }
        }
        switch bee.state {
        case .inside(let wait):
            let remaining = wait - dt
            if remaining > 0 { bee.state = .inside(wait: remaining); return }
            if random.next() < activity { startTrip(&bee, out: true) } else { bee.state = .inside(wait: 1 + random.next() * 3) }
        case .feeding(let wait):
            guard let flowers = flowers(of: bee) else { return }
            let remaining = wait - dt * (activity < 0.5 ? 3 : 1)
            let head = flowers[bee.flower % flowers.count].head
            bee.position = Point(x: head.x + (sin(time * 2 + bee.wobble) * 1.4).rounded(), y: head.y + (sin(time * 3.3 + bee.wobble) * 0.8).rounded() - 1)
            if remaining > 0 { bee.state = .feeding(wait: remaining) } else { startTrip(&bee, out: false) }
        case .flyingOut, .flyingHome, .returning:
            if advance(&bee, dt: dt, time: time) { arrive(&bee) }
        case .defending, .relocating:
            break
        }
    }

    private func isFlying(_ bee: Bee) -> Bool {
        switch bee.state {
        case .returning, .defending: return true
        default: return false
        }
    }

    private func flowers(of bee: Bee) -> [Flower]? {
        guard let hive = hive(bee.hive), let garden = garden(hive.garden), !garden.flowers.isEmpty else { return nil }
        return garden.flowers
    }

    private func advance(_ bee: inout Bee, dt: Double, time: Double) -> Bool {
        bee.progress += dt / bee.duration
        if bee.progress >= 1 { return true }
        let t = bee.progress
        let e = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        let u = 1 - e, (a, c, z) = bee.trip
        let nx = u * u * a.x + 2 * u * e * c.x + e * e * z.x
        let ny = u * u * a.y + 2 * u * e * c.y + e * e * z.y
        if nx != bee.position.x { bee.facing = nx > bee.position.x ? 1 : -1 }
        bee.position = Point(x: nx, y: ny + sin(time * 5 + bee.wobble) * 1.3 * sin(Double.pi * t))
        return false
    }

    private func arrive(_ bee: inout Bee) {
        switch bee.state {
        case .flyingOut:
            bee.state = .feeding(wait: 1.5 + random.next() * 3)
        case .flyingHome:
            bee.state = .inside(wait: 1.5 + random.next() * 4)
            completedTrips += 1
            if let hive = hive(bee.hive) { hive.honey = min(1, hive.honey + World.tripYield) }
        default:
            bee.state = .inside(wait: 1.5 + random.next() * 4)
        }
    }

    private func setTrip(_ bee: inout Bee, from a: Point, to z: Point, arc: Double = 1) {
        let dx = z.x - a.x, dy = z.y - a.y, dist = max(1, hypot(dx, dy))
        let bend = (random.next() - 0.5) * 50 * arc
        bee.trip = (a, Point(x: (a.x + z.x) / 2 - dy / dist * bend, y: (a.y + z.y) / 2 - (12 + random.next() * 22) * arc), z)
        bee.progress = 0
        bee.duration = dist / World.flightSpeed * (0.85 + random.next() * 0.4)
        bee.position = a
    }

    private func startTrip(_ bee: inout Bee, out: Bool) {
        guard let flowers = flowers(of: bee), let hive = hive(bee.hive) else { return }
        if out { bee.flower = random.int(flowers.count) }
        let head = flowers[bee.flower % flowers.count].head
        setTrip(&bee, from: out ? hive.entrance : head, to: out ? head : hive.entrance)
        bee.state = out ? .flyingOut : .flyingHome
    }

    private func relocate(_ bee: inout Bee, target: Int, stage: Int, wait: Double, dt: Double, time: Double) {
        guard let source = hive(bee.hive), let destination = hive(target) else { bee.state = .inside(wait: 1); return }
        switch stage {
        case 0:
            if wait > 0 { bee.state = .relocating(target: target, stage: 0, wait: wait - dt); return }
            let start = source.entrance
            if source.garden == destination.garden {
                setTrip(&bee, from: start, to: destination.entrance, arc: 0.6)
                bee.state = .relocating(target: target, stage: 3, wait: 0)
            } else {
                let edge = Point(x: source.entrance.x < Double(Layout.width / 2) ? -6 : Double(Layout.width + 6), y: 40 + random.next() * 30)
                setTrip(&bee, from: start, to: edge, arc: 0.4)
                bee.state = .relocating(target: target, stage: 2, wait: 0)
            }
        case 2:
            if advance(&bee, dt: dt, time: time) {
                bee.hive = target
                bee.state = .relocating(target: target, stage: 1, wait: 2 + random.next() * 2)
            }
        case 1:
            if wait > 0 { bee.state = .relocating(target: target, stage: 1, wait: wait - dt); return }
            let edge = Point(x: destination.entrance.x < Double(Layout.width / 2) ? -6 : Double(Layout.width + 6), y: 40 + random.next() * 30)
            setTrip(&bee, from: edge, to: destination.entrance, arc: 0.4)
            bee.state = .relocating(target: target, stage: 3, wait: 0)
        default:
            if advance(&bee, dt: dt, time: time) {
                bee.hive = target
                bee.state = .inside(wait: 2 + random.next() * 4)
            }
        }
    }

    private func step(_ helper: Helper, dt: Double, activity: Double) {
        helper.heart = max(0, helper.heart - dt)
        switch helper.task {
        case .idle(let wait):
            helper.asleep = !helper.kind.isAwake(activity: activity)
            guard !helper.asleep else { return }
            if goToFullHive(helper) { return }
            if wait > 0 { helper.task = .idle(wait: wait - dt); return }
            potter(helper)
        case .stroll(let x, let y):
            if goToFullHive(helper) { return }
            if walk(helper, to: (x, y), dt: dt, speed: World.helperSpeed * 0.5) { helper.task = .idle(wait: 1 + random.next() * 2) }
        case .nap(let wait):
            helper.task = wait > 0 ? .nap(wait: wait - dt) : .idle(wait: 1)
        case .toHive(let id):
            guard let hive = hive(id), hive.garden == helper.garden, hive.isFull else { helper.task = .home; return }
            let spot = helperSpot(hive)
            if walk(helper, to: spot, dt: dt) { helper.task = .collecting(id, wait: 1.2); helper.facing = -1 }
        case .collecting(let id, let wait):
            if wait > 0 { helper.task = .collecting(id, wait: wait - dt); return }
            helper.carrying = hive(id)?.garden == helper.garden && collect(hive: id, at: Date()) != nil
            helper.task = .home
        case .home:
            if walk(helper, to: (Double(helper.home.x), Double(helper.home.y)), dt: dt) {
                helper.carrying = false
                helper.task = .idle(wait: 1.5 + random.next() * 2)
            }
        }
    }

    private func runFactory(seconds: Double, at date: Date) {
        guard hasFactory else { return }
        factoryHoney += World.factoryJarsPerMinute * seconds / 60
        while factoryHoney >= 1 {
            factoryHoney -= 1
            jars.append(Jar.fromFactory(at: date))
        }
    }

    private func goToFullHive(_ helper: Helper) -> Bool {
        let full = hives(in: helper.garden).filter { $0.isFull && !$0.packing }
        guard let hive = full.min(by: { distance(helper, to: $0) < distance(helper, to: $1) }) else { return false }
        helper.task = .toHive(hive.id)
        return true
    }

    private func potter(_ helper: Helper) {
        let roll = random.next()
        if roll < 0.55 {
            let a = helper.isHomeless ? World.campArea : World.helperArea
            let x = min(Double(a.maxX), max(Double(a.minX), Double(helper.home.x) + (random.next() - 0.5) * 40))
            let y = min(Double(a.maxY), max(Double(a.minY), Double(helper.home.y) + (random.next() - 0.5) * 14))
            helper.task = .stroll(x: x, y: y)
        } else if roll < 0.75 {
            helper.task = .nap(wait: 3 + random.next() * 3)
        } else {
            helper.task = .idle(wait: 2 + random.next() * 2)
        }
    }

    private func helperSpot(_ hive: Hive) -> (x: Double, y: Double) {
        (Double(min(World.helperArea.maxX, hive.x + 26)), Double(min(World.helperArea.maxY, hive.y + 1)))
    }

    private func distance(_ helper: Helper, to hive: Hive) -> Double {
        let spot = helperSpot(hive)
        return hypot(spot.x - helper.x, spot.y - helper.y)
    }

    private func walk(_ helper: Helper, to target: (x: Double, y: Double), dt: Double, speed: Double = World.helperSpeed) -> Bool {
        let dx = target.x - helper.x, dy = target.y - helper.y, d = hypot(dx, dy)
        let step = speed * dt
        if abs(dx) > 0.5 { helper.facing = dx > 0 ? 1 : -1 }
        helper.walked += dt
        guard d > step else { helper.x = target.x; helper.y = target.y; return true }
        helper.x += dx / d * step
        helper.y += dy / d * step
        return false
    }

    private func grow(_ hive: Hive, dt: Double, census: (bees: Int, queen: Bool)) {
        if let remaining = hive.queenEmergesIn {
            let next = remaining - dt
            if next <= 0 {
                hive.queenEmergesIn = nil
                bees.append(Bee(id: nextBeeID, hive: hive.id, role: .queen, hatchedAt: clock, wobble: random.next() * 6.28))
                nextBeeID += 1
            } else { hive.queenEmergesIn = next }
            return
        }
        guard census.queen, census.bees < World.colonyStrength else { return }
        hive.hatchTimer += dt
        guard hive.hatchTimer >= World.hatchSeconds else { return }
        hive.hatchTimer = 0
        bees.append(Bee(id: nextBeeID, hive: hive.id, role: newRole(hive: hive.id), hatchedAt: clock, state: .inside(wait: 2), wobble: random.next() * 6.28))
        nextBeeID += 1
    }

    private func newRole(hive: Int) -> Bee.Role {
        Double(foragerCount(hive: hive)) < Double(World.colonyStrength) * World.foragerShare ? .forager : .house
    }

    // MARK: Hornets

    private func updateHornet(_ garden: Garden, dt: Double, activity: Double, time: Double) {
        guard var h = garden.hornet else {
            guard hornetsEnabled, activity > 0.5 else { return }
            garden.nextHornetIn -= dt
            guard garden.nextHornetIn <= 0 else { return }
            garden.nextHornetIn = World.hornetMeanSeconds * (0.5 + random.next())
            let candidates = hives(in: garden.id).filter { beeCount(hive: $0.id) > 10 }
            guard let target = candidates.randomElement() else { return }
            garden.hornet = Hornet(x: Double(Layout.width + 8), y: 40 + random.next() * 20, hive: target.id, maxCatches: 1 + random.int(3))
            return
        }
        var finished = false
        defer { garden.hornet = finished ? nil : h }
        guard let hive = hive(h.hive) else { finished = true; return }
        let home = Point(x: hive.entrance.x + 16, y: hive.entrance.y - 12)
        h.t += dt
        switch h.phase {
        case .approach:
            hornetMove(&h, to: Point(x: home.x, y: home.y + sin(h.t * 2.3) * 5), speed: 26, dt: dt)
            if hypot(h.x - home.x, h.y - home.y) < 5 { h.phase = .hover; h.t = 0 }
        case .hover:
            if let preyID = h.prey, let i = bees.firstIndex(where: { $0.id == preyID }), bees[i].isOutside {
                hornetMove(&h, to: bees[i].position, speed: 48, dt: dt)
                if hypot(h.x - bees[i].position.x, h.y - bees[i].position.y) < 2 {
                    puffs.append((bees[i].position, 0))
                    bees[i].hive = -1
                    h.prey = nil
                    h.catches += 1
                    h.cooldown = 1.6 + random.next()
                }
            } else {
                h.prey = nil
                hornetMove(&h, to: Point(x: home.x + sin(h.t * 1.3) * 9, y: home.y + sin(h.t * 2.6) * 3), speed: 14, dt: dt)
                h.cooldown -= dt
                if h.cooldown <= 0 && h.catches < h.maxCatches {
                    let near = bees.indices.filter { i in
                        guard let bh = self.hive(bees[i].hive), bh.garden == garden.id, bees[i].role == .forager else { return false }
                        switch bees[i].state { case .flyingOut, .flyingHome: return true; default: return false }
                    }.min { hypot(bees[$0].position.x - h.x, bees[$0].position.y - h.y) < hypot(bees[$1].position.x - h.x, bees[$1].position.y - h.y) }
                    if let near, hypot(bees[near].position.x - h.x, bees[near].position.y - h.y) < 50 { h.prey = bees[near].id } else { h.cooldown = 0.4 }
                }
                if h.t > 10 || (h.catches >= h.maxCatches && h.cooldown <= 0) {
                    h.phase = .balled
                    h.t = 0
                    let guards = bees.indices.filter { bees[$0].hive == hive.id && bees[$0].role == .house && !bees[$0].isOutside }.prefix(12)
                    for i in guards {
                        bees[i].state = .defending
                        bees[i].position = hive.entrance
                        h.defenders.append(bees[i].id)
                    }
                }
            }
        case .balled:
            h.x += sin(time * 31) * 0.25
            h.y += sin(time * 23) * 0.15
            moveDefenders(h, dt: dt, time: time, chase: false)
            if h.t > 3.2 { h.phase = .flee; h.t = 0 }
        case .flee:
            h.facing = 1
            h.x += 46 * dt
            h.y -= 22 * dt
            if h.t < 0.6 { moveDefenders(h, dt: dt, time: time, chase: true) }
            else if !h.defenders.isEmpty {
                for id in h.defenders {
                    guard let i = bees.firstIndex(where: { $0.id == id }) else { continue }
                    setTrip(&bees[i], from: bees[i].position, to: hive.entrance, arc: 0.3)
                    bees[i].state = .returning
                }
                h.defenders = []
            }
            if h.x > Double(Layout.width + 10) && h.t > 3 { finished = true }
        }
    }

    var puffs: [(position: Point, age: Double)] = []

    private func hornetMove(_ h: inout Hornet, to target: Point, speed: Double, dt: Double) {
        let d = max(0.001, hypot(target.x - h.x, target.y - h.y)), step = min(d, speed * dt)
        if abs(target.x - h.x) > 0.3 { h.facing = target.x > h.x ? 1 : -1 }
        h.x += (target.x - h.x) / d * step
        h.y += (target.y - h.y) / d * step
    }

    private func moveDefenders(_ h: Hornet, dt: Double, time: Double, chase: Bool) {
        for (k, id) in h.defenders.enumerated() {
            guard let i = bees.firstIndex(where: { $0.id == id }) else { continue }
            if chase {
                bees[i].position.x += 30 * dt
                bees[i].position.y -= 14 * dt
                continue
            }
            let a = Double(k) / Double(max(1, h.defenders.count)) * 6.28 + time * 7
            let tx = h.x + 4 + cos(a) * 5.5, ty = h.y + 1 + sin(a) * 4
            bees[i].position.x += (tx - bees[i].position.x) * min(1, dt * 5)
            bees[i].position.y += (ty - bees[i].position.y) * min(1, dt * 5)
            bees[i].facing = tx > bees[i].position.x ? 1 : -1
        }
    }

    func agePuffs(_ dt: Double) {
        for i in puffs.indices { puffs[i].age += dt }
        puffs.removeAll { $0.age > 0.7 }
    }

    // MARK: Away

    func catchUp(from start: Date, to end: Date) {
        let elapsed = min(end.timeIntervalSince(start), 7 * 24 * 3600)
        guard elapsed > 1 else { return }
        for helper in helpers where !helper.isStored { helper.settle(at: helper.home.x, helper.home.y) }
        var t = end.addingTimeInterval(-elapsed)
        while t < end {
            let step = min(60, end.timeIntervalSince(t))
            let activity = Clock.activity(Clock.minute(at: t))
            for hive in hives where !hive.isFull && !hive.isPacked {
                let trips = activity * Double(foragerCount(hive: hive.id)) * World.tripsPerForagerMinute * step / 60
                hive.honey = min(1, hive.honey + trips * World.tripYield)
            }
            for hive in hives where hive.isFull && !hive.isPacked {
                if let helper = helper(in: hive.garden), helper.kind.isAwake(activity: activity) { collect(hive: hive.id, at: t) }
            }
            runFactory(seconds: step, at: t)
            t = t.addingTimeInterval(step)
        }
        for hive in hives where !hive.isPacked {
            var budget = elapsed
            if let remaining = hive.queenEmergesIn {
                guard remaining <= budget else { hive.queenEmergesIn = remaining - budget; continue }
                budget -= remaining
                hive.queenEmergesIn = nil
                bees.append(Bee(id: nextBeeID, hive: hive.id, role: .queen, wobble: random.next() * 6.28))
                nextBeeID += 1
            }
            guard hasQueen(hive: hive.id) else { continue }
            let missing = World.colonyStrength - beeCount(hive: hive.id)
            for _ in 0..<min(max(0, missing), Int(budget / World.hatchSeconds)) {
                bees.append(Bee(id: nextBeeID, hive: hive.id, role: newRole(hive: hive.id), wobble: random.next() * 6.28))
                nextBeeID += 1
            }
        }
    }
}
