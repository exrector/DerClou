import Testing
@testable import HeistCore

@Suite("Dynamic navigation world")
struct NavigationWorldTests {
    @Test("Moving bodies use a local mask without rebuilding static clearance")
    func transientBodyMaskIsLocal() throws {
        let geometry = LevelGeometryBuilder.build(.office01)
        let world = NavigationWorld(geometry: geometry, budget: .standard)
        let bodyPosition = LevelMetrics.standard.worldPoint(CellPoint(12, 8))
        let body = WorldBox(
            center: WorldPoint(x: bodyPosition.x, y: 0.875, z: bodyPosition.z),
            width: 0.6,
            height: 1.75,
            depth: 0.6,
            surface: .fabric,
            sourceID: "actor.body"
        )

        let bodyCell = world.grid.cell(at: bodyPosition)
        #expect(world.grid.isWalkable(bodyCell))
        let masked = world.grid.blockingTransientObstacles(
            [body],
            characterRadius: NavigationBudget.standard.characterRadius,
            characterHeight: NavigationBudget.standard.characterHeight
        )

        #expect(!masked.isWalkable(bodyCell))
        #expect(world.grid.isWalkable(bodyCell))
        #expect(masked.clearance == world.grid.clearance)
        #expect(masked.cellCount == world.grid.cellCount)
    }

    @Test("A runtime cube advances revision and invalidates its occupied cells")
    func dynamicObstacleRebuildsGrid() {
        let geometry = LevelGeometryBuilder.build(.office01)
        let budget = NavigationBudget.standard
        var world = NavigationWorld(geometry: geometry, budget: budget)
        let point = LevelMetrics.standard.worldPoint(CellPoint(12, 8))

        #expect(world.grid.isWalkable(world.grid.cell(at: point)))
        #expect(world.revision == 0)

        let cube = WorldBox(
            center: WorldPoint(x: point.x, y: 0.45, z: point.z),
            width: 0.9,
            height: 0.9,
            depth: 0.9,
            surface: .metal,
            sourceID: "test.cube"
        )
        let inserted = world.upsertObstacle(id: "test.cube", box: cube)
        #expect(inserted)
        #expect(world.revision == 1)
        #expect(!world.grid.isWalkable(world.grid.cell(at: point)))
        let duplicate = world.upsertObstacle(id: "test.cube", box: cube)
        #expect(!duplicate)
        #expect(world.revision == 1)

        let removed = world.removeObstacle(id: "test.cube")
        #expect(removed)
        #expect(world.revision == 2)
        #expect(world.grid.isWalkable(world.grid.cell(at: point)))
    }
}
