import Testing
@testable import HeistCore

/// `ApproachPointSolver` picks where an actor stands to use a prop it cannot
/// walk into — tested here against both office01's real geometry and small
/// synthetic boxes, so a rotation bug shows up as a specific failing case
/// rather than "the door didn't work" three layers up.
@Suite("Approach point solving")
struct ApproachPointSolverTests {
    let geometry = LevelGeometryBuilder.build(.office01)

    var grid: NavGrid {
        NavGridBuilder.build(geometry: geometry)
    }

    func prop(_ id: String) -> PlacedProp {
        geometry.props.first { $0.id == id }!
    }

    // MARK: - Against a real level

    @Test("A door in the corridor wall resolves to a walkable point on the corridor side")
    func doorApproachIsWalkable() throws {
        let door = prop("office01.door.a")
        let approach = try #require(
            ApproachPointSolver.approachPoint(for: door.box, grid: grid)
        )
        #expect(grid.isWalkable(grid.cell(at: approach)))
    }

    @Test("The approach point sits outside the door's own footprint, not on top of it")
    func doorApproachClearsTheFootprint() throws {
        let door = prop("office01.door.a")
        let approach = try #require(
            ApproachPointSolver.approachPoint(for: door.box, grid: grid)
        )
        // The door is 0.06 m deep (a wall-mounted slab); anything within a
        // few centimetres of its centre on the depth axis would still be
        // inside the wall it is set into.
        #expect(approach.planarDistance(to: door.box.center) > 0.3)
    }

    @Test("A rotated prop's approach point still lands on its walkable side")
    func rotatedPropApproachIsWalkable() throws {
        // cabinet.a is placed with rotation 90 — this is the case that would
        // silently break if the local-to-world rotation in
        // ApproachPointSolver had its sign backwards, since an unrotated box
        // would still happen to pass most other tests by symmetry.
        let cabinet = prop("office01.cabinet.a")
        #expect(cabinet.box.yaw == 90)

        let approach = try #require(
            ApproachPointSolver.approachPoint(for: cabinet.box, grid: grid)
        )
        #expect(grid.isWalkable(grid.cell(at: approach)))
    }

    @Test("Given a choice of walkable sides, the nearest one to the actor wins")
    func picksTheNearestOpenSide() throws {
        // A desk in open floor has every side walkable, so this is a genuine
        // choice, not a case where only one side happens to be reachable.
        let desk = prop("office01.desk.a")
        let farSide = WorldPoint(
            x: desk.box.center.x, y: 0, z: desk.box.center.z + 5
        )
        let nearSide = WorldPoint(
            x: desk.box.center.x, y: 0, z: desk.box.center.z - 5
        )

        let approachFromFar = try #require(
            ApproachPointSolver.approachPoint(for: desk.box, grid: grid, from: farSide)
        )
        let approachFromNear = try #require(
            ApproachPointSolver.approachPoint(for: desk.box, grid: grid, from: nearSide)
        )

        // Asking from opposite sides of the same symmetric obstacle has to
        // produce two different answers, each closer to whoever asked.
        #expect(approachFromFar.z > desk.box.center.z)
        #expect(approachFromNear.z < desk.box.center.z)
    }

    // MARK: - Synthetic edge cases

    @Test("No walkable side at all resolves to nil, not a point inside a wall")
    func noWalkableSideIsNil() {
        // A tiny grid that is entirely unwalkable: nothing around the box
        // could ever be a valid place to stand.
        let emptyGrid = NavGrid(
            minX: -5, minZ: -5, cellSize: 0.5, columns: 20, rows: 20,
            walkable: [Bool](repeating: false, count: 400)
        )
        let box = WorldBox(
            center: WorldPoint(x: 0, y: 0, z: 0),
            width: 1, height: 1, depth: 1, surface: .wood, sourceID: "test.box"
        )
        #expect(ApproachPointSolver.approachPoint(for: box, grid: emptyGrid) == nil)
    }

    @Test("With no origin given, the first walkable side is used deterministically")
    func noOriginIsDeterministic() {
        // An all-walkable grid: every side qualifies, so this only proves the
        // result does not depend on iteration order or hidden randomness.
        let openGrid = NavGrid(
            minX: -5, minZ: -5, cellSize: 0.5, columns: 20, rows: 20,
            walkable: [Bool](repeating: true, count: 400)
        )
        let box = WorldBox(
            center: WorldPoint(x: 0, y: 0, z: 0),
            width: 1, height: 1, depth: 1, surface: .wood, sourceID: "test.box"
        )
        let first = ApproachPointSolver.approachPoint(for: box, grid: openGrid)
        let second = ApproachPointSolver.approachPoint(for: box, grid: openGrid)
        #expect(first == second)
    }
}
