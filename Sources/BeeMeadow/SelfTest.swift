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
        return ok
    }
}
#endif
