#if canImport(AppKit)
import Foundation

enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ condition: Bool, _ label: String) {
            print((condition ? "PASS " : "FAIL ") + label)
            ok = ok && condition
        }
        Persistence.testFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("beemeadow-selftest-\(UUID().uuidString).json")
        defer { Persistence.testFileURL.map { try? FileManager.default.removeItem(at: $0) } }
        Clock.fixedMinute = 30
        let world = World.classic()
        world.hornetsEnabled = false
        let dt = 0.1
        func run(seconds: Double, visible: Int? = nil) {
            for i in 0..<Int(seconds / dt) { world.tick(dt, minute: 30, time: Double(i) * dt, visibleGarden: visible); world.agePuffs(dt) }
        }
        run(seconds: 60)

        world.jars = (0..<20).map { _ in Jar(honey: "Clover", hiveName: "Pip", collectedAt: Date()) }
        check(world.buyHiveBox() && world.spareBoxes == 1 && world.jars.count == 17, "trade 3 jars for a hive box")
        check(!world.placeBox(x: 20, y: 146, in: 0), "cannot place on top of a hive")
        check(world.placeBox(x: 40, y: 172, in: 0), "place a box in the clover meadow")
        let box = world.hives.last!
        check(world.isEmptyBox(box), "new box is empty")
        check(!world.placeBox(x: 30, y: 172, in: 0), "no spare boxes left")

        let source = world.hives[0]
        while world.beeCount(hive: source.id) < World.colonyStrength {
            world.bees.append(Bee(id: world.nextBeeID, hive: source.id, role: .house))
            world.nextBeeID += 1
        }
        check(world.readyToSplit(source), "full strength hive is ready to split")
        check(world.splitTarget(for: source)?.id == box.id, "split targets the empty box in the same garden")
        let before = world.beeCount(hive: source.id)
        check(world.split(hive: source.id)?.id == box.id, "split starts")
        run(seconds: 40)
        let moved = world.beeCount(hive: box.id)
        check(moved >= before / 2 - 2 && moved <= before / 2 + 1, "about half the bees arrive (\(moved) of \(before))")
        check(world.beeCount(hive: source.id) + moved == before, "no bees lost in transit")
        check(world.hasQueen(hive: source.id) && !world.hasQueen(hive: box.id), "old hive keeps the queen, new hive waits")
        run(seconds: World.queenSeconds + 5)
        check(world.hasQueen(hive: box.id), "new queen emerges")

        let garden = world.buyGarden(kind: .lavender, plot: 0)
        check(garden != nil && world.jars.count == 17 - 10, "buy a lavender garden for 10 jars")
        world.spareBoxes += 1
        check(world.placeBox(x: 40, y: 150, in: garden!.id), "place a box in the new garden")
        let far = world.hives.last!
        let hazel = world.hives[1]
        while world.beeCount(hive: hazel.id) < World.colonyStrength {
            world.bees.append(Bee(id: world.nextBeeID, hive: hazel.id, role: .house))
            world.nextBeeID += 1
        }
        let hazelBefore = world.beeCount(hive: hazel.id)
        check(world.split(hive: hazel.id)?.id == far.id, "cross-garden split targets the lavender box")
        run(seconds: 50)
        check(world.beeCount(hive: far.id) + world.beeCount(hive: hazel.id) == hazelBefore && world.beeCount(hive: far.id) > 10, "bees arrive in the other garden")

        let honeyBefore = world.hives[2].honey
        run(seconds: 120)
        check(world.hives[2].honey > honeyBefore, "honey keeps filling from trips")
        world.hives[2].honey = 1
        let jarsBefore = world.jars.count, harvestsBefore = world.harvests.count
        check(world.collect(hive: world.hives[2].id, at: Date())?.honey == "Clover", "collect a jar of clover honey")
        check(world.jars.count == jarsBefore + 1 && world.harvests.count == harvestsBefore + 1, "jar lands in pantry and harvest book")
        check(world.move(hive: box.id, x: 44, y: 170), "move a hive")

        let juniper = world.hives[2]
        let juniperBees = world.beeCount(hive: juniper.id), juniperHoney = juniper.honey
        check(world.pack(hive: juniper.id) == .packing, "start packing a hive")
        run(seconds: 5)
        check(juniper.isPacked && world.packedHives.count == 1, "hive packed into the shed")
        check(world.beeCount(hive: juniper.id) == juniperBees && juniper.honey == juniperHoney, "bees and honey kept while packed")
        run(seconds: 60)
        check(juniper.honey == juniperHoney && world.beeCount(hive: juniper.id) == juniperBees, "nothing changes while packed")
        check(world.unpack(hive: juniper.id, x: 80, y: 128, in: garden!.id), "unpack into the lavender garden")
        run(seconds: 30)
        check(world.bees.contains { $0.hive == juniper.id && $0.isOutside }, "unpacked bees forage in their new garden")
        world.spareBoxes += 1
        check(world.placeBox(x: 90, y: 172, in: garden!.id), "place another empty box")
        let spare = world.hives.last!
        _ = world.pack(hive: spare.id)
        run(seconds: 1)
        check(world.hive(spare.id) == nil && world.spareBoxes == 1, "packing an empty box returns it to the shed")

        world.hornetsEnabled = true
        world.gardens[0].nextHornetIn = 0
        let idsBefore = Set(world.bees.map(\.id))
        run(seconds: 50, visible: 0)
        check(world.gardens[0].hornet == nil, "hornet visit finishes")
        let lost = idsBefore.subtracting(world.bees.map(\.id)).count
        check(lost >= 0 && lost <= 3, "hornet took \(lost) bees (at most 3)")
        check(!world.bees.contains { if case .defending = $0.state { return true }; return false }, "guards all went home")

        Persistence.save(world, currentGarden: garden!.id, now: Date())
        let loaded = Persistence.load(now: Date())
        check(loaded.world.bees.count == world.bees.count && loaded.world.hives.count == world.hives.count && loaded.world.gardens.count == 2, "save and load round trip")
        check(loaded.currentGarden == garden!.id, "remembers current garden")

        let start = World.fresh()
        check(start.gardens.count == 2 && start.hives.count == 2 && start.spareBoxes == 1, "new game: two gardens, one hive each, a free box")
        check(Set(start.hives.map(\.garden)).count == 2 && start.gardenPrice() == 10, "one hive per garden, next garden still 10 jars")
        let pip = start.hives[0]
        while start.beeCount(hive: pip.id) >= World.colonyStrength / 2, let i = start.bees.firstIndex(where: { $0.hive == pip.id && $0.role != .queen }) {
            start.bees.remove(at: i)
        }
        check(!start.readyToSplit(pip), "split waits for half strength")
        while start.beeCount(hive: pip.id) < World.colonyStrength / 2 {
            start.bees.append(Bee(id: start.nextBeeID, hive: pip.id, role: .house))
            start.nextBeeID += 1
        }
        check(start.readyToSplit(pip) && !start.atFullStrength(pip), "half strength hive can split")
        check(start.placeBox(x: 100, y: 160, in: pip.garden) && start.split(hive: pip.id) != nil, "first split into the free box")

        let helped = World.fresh()
        helped.hornetsEnabled = false
        helped.jars = (0..<45).map { _ in Jar(honey: "Clover", hiveName: "Pip", collectedAt: Date()) }
        let bear = helped.hireHelper(.bear)
        check(bear != nil && helped.jars.count == 25 && bear!.isStored, "hire a bear for 20 jars into the shed")
        check(helped.hireHelper(.mouse) != nil && helped.hireHelper(.badger) == nil, "one helper per garden")
        check(helped.placeHelper(bear!.id, x: 70, y: 160, in: 0), "place the bear in the clover garden")
        let mouse = helped.storedHelpers[0]
        check(!helped.placeHelper(mouse.id, x: 80, y: 160, in: 0), "a garden only takes one helper")
        let clover = helped.hives(in: 0)[0]
        clover.honey = 1
        let jarsAtStart = helped.jars.count
        for i in 0..<300 { helped.tick(0.1, minute: 30, time: Double(i) * 0.1, visibleGarden: 0) }
        check(helped.jars.count == jarsAtStart + 1 && clover.honey < 0.1, "bear collects a full hive")
        check(abs(bear!.x - 70) <= 20 && !bear!.carrying, "bear walks home after collecting")
        bear!.task = .nap(wait: 5)
        bear!.pet()
        check(bear!.heart > 0 && !bear!.isNapping, "petting a napping bear wakes it with a heart")
        helped.storeHelper(bear!.id)
        check(bear!.isStored && helped.helper(in: 0) == nil, "drag the bear back into the shed")
        check(helped.placeHelper(mouse.id, x: 70, y: 160, in: 1) && helped.placeHelper(bear!.id, x: 60, y: 150, in: 0), "swap helpers between gardens")
        let away = helped.jars.count
        helped.catchUp(from: Date().addingTimeInterval(-6 * 3600), to: Date())
        check(helped.jars.count > away + 2, "helpers keep collecting while away (\(helped.jars.count - away) jars)")
        let data = try? Persistence.encode(helped, currentGarden: 0, now: Date())
        let restored = data.map { Persistence.decode($0, now: Date()).world }
        check(restored?.helpers.count == 2 && restored?.helper(in: 0)?.kind == .bear && restored?.helper(in: 1)?.kind == .mouse, "helpers survive save and load")

        func jars(_ n: Int) -> [Jar] { (0..<n).map { _ in Jar(honey: "Clover", hiveName: "Pip", collectedAt: Date()) } }
        let factory = World.fresh()
        factory.hornetsEnabled = false
        factory.jars = jars(40)
        let badger = factory.hireHelper(.badger)!
        check(factory.placeHelper(badger.id, x: 70, y: 160, in: 0), "badger works the clover garden")
        let mole = factory.hireHelper(.mouse)
        factory.jars = jars(999)
        check(factory.hireHelper(.hedgehog) == nil && !factory.canBuildFactory && !factory.buildFactory(), "factory needs 1000 jars")
        factory.jars += jars(1)
        let boxes = factory.spareBoxes
        check(factory.buildFactory() && factory.hasFactory && factory.jars.isEmpty, "build the factory for 1000 jars")
        check(factory.gardens.isEmpty && factory.hives.isEmpty && factory.bees.isEmpty, "factory swallows the valley's gardens, hives and bees")
        check(factory.homelessHelpers.count == 2 && badger.isHomeless && mole?.isHomeless == true && factory.storedHelpers.isEmpty, "every helper becomes homeless")
        check(factory.spareBoxes == boxes, "shed boxes are kept")
        factory.storeHelper(badger.id)
        check(badger.isHomeless && !factory.moveHelper(badger.id, x: 70, y: 160), "homeless helpers stay at the camp")
        let east = Valley(x: 1, y: 0), outer = Valley(x: 2, y: 0)
        check(factory.openRing == 1 && factory.isOpen(east) && !factory.isOpen(outer) && !factory.isOpen(.home), "eight valleys open around the factory")
        check(World.valleys(inRing: 1).count == 8 && World.valleys(inRing: 2).count == 16, "rings of 8 then 16 valleys")
        check(factory.gardenPrice(in: east) == 100 && factory.hiveBoxPrice(in: east) == 30 && factory.helperPrice(in: east) == 200, "first ring costs 10x")
        factory.jars = jars(5000)
        check(factory.buyGarden(kind: .heather, plot: 0, in: outer) == nil, "second ring stays shut")
        for (i, valley) in World.valleys(inRing: 1).enumerated() {
            check(factory.openRing == 1, "ring 2 still shut with \(i) of 8 valleys claimed")
            _ = factory.buyGarden(kind: .heather, plot: 4, in: valley)
        }
        check(factory.gardens.count == 8 && factory.jars.count == 5000 - 800, "each first ring valley starts at 100 jars")
        let swarm = factory.hives.first
        check(factory.hives.count == 1 && swarm?.garden == factory.gardens[0].id && factory.hasColony, "a wild swarm moves into the first new garden")
        check(swarm.map { factory.readyToSplit($0) } == true, "the swarm can split into new boxes")
        check(factory.openRing == 2 && factory.isOpen(outer) && factory.gardenPrice(in: outer) == 1000, "filling the ring opens the next at 100x")
        check(factory.canHireHelper && factory.hireHelper(.bear, in: outer) != nil && factory.jars.count == 4200 - 2000, "hire at 100x, homeless helpers don't count")
        let beforeFactory = factory.jars.count
        for i in 0..<600 { factory.tick(0.1, minute: 30, time: Double(i) * 0.1, visibleGarden: nil) }
        let made = factory.jars.count - beforeFactory
        check(made >= 2 && made <= 4, "factory makes about 3.5 jars a minute by day (\(made))")
        let beforeNight = factory.jars.count
        for i in 0..<600 { factory.tick(0.1, minute: 66, time: Double(i) * 0.1, visibleGarden: nil) }
        check(Clock.activity(66) == 0 && (2...4).contains(factory.jars.count - beforeNight), "factory keeps going through the night (\(factory.jars.count - beforeNight))")
        check(factory.jars.last?.honey == World.factoryHoneyName && factory.jars.last?.hiveName == "Factory", "factory jars are blended honey")
        check(!factory.harvests.contains { $0.hiveName == "Factory" }, "factory jars stay out of the harvest book")
        let beforeAway = factory.jars.count
        factory.catchUp(from: Date().addingTimeInterval(-3600), to: Date())
        check(factory.jars.count > beforeAway + 10, "factory keeps making honey while away (\(factory.jars.count - beforeAway))")
        let saved = (try? Persistence.encode(factory, currentGarden: -1, now: Date())).map { Persistence.decode($0, now: Date()) }
        check(saved?.world.hasFactory == true && saved?.world.openRing == 2 && saved?.world.homelessHelpers.count == 2, "factory, valleys and camp survive save and load")
        let factoryJars = factory.jars.filter(\.isFromFactory).count
        let encoded = (try? Persistence.encode(factory, currentGarden: -1, now: Date())).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(factoryJars > 100 && !encoded.contains("\"Blended\"") && saved?.world.jars.count == factory.jars.count, "factory jars save as a count (\(factoryJars) jars)")
        check(saved?.world.garden(in: east, plot: 4) != nil && saved?.currentGarden == saved?.world.gardens.first?.id, "gardens remember their valley")

        let meadow = World.classic()
        let hive = meadow.hives[0]
        meadow.bees = (0..<World.colonyStrength).map { i in
            Bee(id: i, hive: hive.id, role: i == 0 ? .queen : i <= World.fullStrengthForagers ? .forager : .house)
        }
        hive.honey = 0
        meadow.catchUp(from: Date().addingTimeInterval(-600), to: Date())
        let valleyRate = hive.honey / 10 * Double(World.fullValleyHives)
        check(abs(World.factoryJarsPerMinute - 2 * valleyRate) < 0.01, "factory makes twice a full valley (\(World.factoryJarsPerMinute) vs \(valleyRate) jars a minute)")

        let played = World.fresh()
        played.hornetsEnabled = false
        played.jars = jars(1150)
        let game = Game(world: played, currentGarden: 0)
        func tap(_ r: PixelRect) { game.click((Double(r.x) + Double(r.w) / 2, Double(r.y) + Double(r.h) / 2)) }
        tap(Widgets.mapRect)
        tap(ValleyRenderer.factoryRect)
        tap(ValleyRenderer.cancelRect)
        check(game.scene == .valley(.home) && !played.hasFactory, "factory sign asks before building")
        tap(ValleyRenderer.factoryRect)
        tap(ValleyRenderer.buildRect)
        check(played.hasFactory && !game.isInteractive((120, 90)), "building starts the demolition")
        for i in 0..<Int(FactoryRenderer.duration * 30) + 2 { _ = game.step(dt: 1.0 / 30, minute: 30, time: Double(i) / 30) }
        check(game.scene == .region, "demolition ends on the map")
        tap(RegionRenderer.tileRect(Valley(x: 0, y: -2), world: played))
        check(game.scene == .region, "locked valleys can't be visited")
        tap(RegionRenderer.tileRect(.home, world: played))
        check(game.scene == .factory && game.step(dt: 0.1, minute: 30, time: 10) != nil, "visit the factory")
        tap(Widgets.backRect)
        tap(RegionRenderer.tileRect(Valley(x: 1, y: 0), world: played))
        tap(ValleyRenderer.plotRect(4))
        check(game.scene == .picker(Valley(x: 1, y: 0), 4), "pick a plot in a new valley")
        tap(StallRenderer.pickerRect(2))
        check(game.scene == .garden && played.garden(game.currentGarden)?.valley == Valley(x: 1, y: 0) && played.jars.count == 50, "buy a garden there for 100 jars")
        tap(Widgets.mapRect)
        tap(ValleyRenderer.stallRect)
        tap(StallRenderer.tradeRect)
        check(played.spareBoxes == 2 && played.jars.count == 20, "hive boxes cost 30 jars out here")
        game.escape(); game.escape()
        check(game.scene == .region, "valleys sit under the map")
        game.escape()
        check(game.scene == .garden, "map goes back to the garden")
        return ok
    }
}
#endif
