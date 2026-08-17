import Testing
@testable import HeistCore

@Suite("Level geometry")
struct LevelGeometryTests {
    let geometry = LevelGeometryBuilder.build(.office01)

    @Test("Building the same blueprint twice yields identical geometry")
    func deterministic() {
        #expect(LevelGeometryBuilder.build(.office01) == LevelGeometryBuilder.build(.office01))
    }

    @Test("The floor slab sits just below the walking surface")
    func floorPlacement() {
        let floor = try! #require(geometry.floors.first)
        #expect(floor.width == 24)
        #expect(floor.depth == 10)
        #expect(floor.center.y < 0)
        #expect(floor.center.y + floor.height / 2 == 0)
    }

    @Test("The corridor wall is emitted as solid runs plus one lintel per doorway")
    func corridorWall() {
        let pieces = geometry.walls.filter { $0.sourceID.hasPrefix("office01.wall.corridor") }
        // Three doorways: four solid runs between and around them, plus three
        // lintels over the openings.
        #expect(pieces.count == 7)

        let lintels = pieces.filter { $0.center.y > LevelMetrics.standard.doorwayHeight }
        #expect(lintels.count == 3)
    }

    @Test("Walls are yawed onto their own axis")
    func wallOrientation() {
        let north = try! #require(geometry.walls.first { $0.sourceID.hasPrefix("office01.wall.north") })
        let west = try! #require(geometry.walls.first { $0.sourceID.hasPrefix("office01.wall.west") })

        #expect(north.yaw == 0)
        #expect(west.yaw == -90)
    }

    @Test("Wall-mounted props are lifted to their mount height")
    func mountedProps() {
        let panel = try! #require(geometry.props.first { $0.id == "office01.panel.corridor" })
        let camera = try! #require(geometry.props.first { $0.id == "office01.camera.corridor" })
        let desk = try! #require(geometry.props.first { $0.id == "office01.desk.a" })

        #expect(panel.box.center.y > 1.3)
        #expect(camera.box.center.y > 2.4)
        // Floor-standing furniture is centred on half its own height.
        #expect(desk.box.center.y == desk.prototype.height / 2)
    }

    @Test("Only blocking props become navigation obstacles")
    func obstacleSelection() {
        let obstacleIDs = Set(geometry.obstacleBoxes.map(\.sourceID))

        #expect(obstacleIDs.contains("office01.desk.a"))
        #expect(obstacleIDs.contains("office01.cabinet.a"))
        // Doors, cameras, panels and loot must not block the mesh.
        #expect(!obstacleIDs.contains("office01.door.a"))
        #expect(!obstacleIDs.contains("office01.camera.corridor"))
        #expect(!obstacleIDs.contains("office01.loot.desk"))
    }

    @Test("Both actors are placed standing on the floor")
    func actorPlacement() {
        #expect(geometry.actors.count == 2)
        for actor in geometry.actors {
            #expect(actor.box.center.y == actor.prototype.height / 2)
        }
    }

    @Test("The thief's profile comes from its prototype, not a hard-coded constant")
    func characterProfile() {
        let thief = try! #require(geometry.actors.first { $0.id == "office01.thief.01" })

        #expect(thief.character.walkSpeed == 1.4)
        #expect(thief.character.height == 1.75)
        #expect(thief.character.radius == 0.3)
        // Timing is derived, never written down twice.
        #expect(thief.character.duration(forDistance: 14) == 10)
    }
}
