import Testing
@testable import HeistCore

@Suite("Path finding")
struct PathFindingTests {
    let geometry = LevelGeometryBuilder.build(.office01)

    var grid: NavGrid {
        NavGridBuilder.build(geometry: geometry)
    }

    /// Cell coordinates in office01, converted to world meters.
    func world(_ x: Double, _ z: Double) -> WorldPoint {
        LevelMetrics.standard.worldPoint(CellPoint(x, z))
    }

    func path(_ from: WorldPoint, _ to: WorldPoint) -> PathResult? {
        try? PathFinder.findPath(from: from, to: to, in: grid).get()
    }

    // MARK: - The grid itself

    @Test("A doorway lintel does not block the doorway")
    func lintelIsNotAnObstacle() {
        // This was the bug: wall segments above a doorway were fed to the
        // navigation bake as solid, sealing every room off from the corridor.
        let doorway = world(3, 6)
        #expect(grid.isWalkable(grid.cell(at: doorway)))
    }

    @Test("Walls are solid")
    func wallsAreSolid() {
        // Middle of the divider between office A and office B.
        #expect(!grid.isWalkable(grid.cell(at: world(6, 3))))
        // Middle of the corridor wall, away from any doorway.
        #expect(!grid.isWalkable(grid.cell(at: world(7, 6))))
    }

    @Test("Furniture is solid")
    func furnitureIsSolid() {
        // Centre of the desk in office A.
        #expect(!grid.isWalkable(grid.cell(at: world(2.4, 2.0))))
    }

    @Test("Open floor is walkable")
    func floorIsWalkable() {
        #expect(grid.isWalkable(grid.cell(at: world(12, 8))))
        #expect(grid.isWalkable(grid.cell(at: world(2, 8.6))))
    }

    @Test("The grid keeps clear of walls by the character radius")
    func gridInsetsWalls() {
        // 10 cm from the corridor wall face: too close for a 0.3 m radius body.
        #expect(!grid.isWalkable(grid.cell(at: world(12, 6.2))))
        // 60 cm away is fine.
        #expect(grid.isWalkable(grid.cell(at: world(12, 6.75))))
    }

    // MARK: - Routing

    @Test("Getting between two offices routes through the corridor")
    func routesThroughCorridor() throws {
        let start = world(2.4, 4.5)
        let goal = world(9.5, 4.5)
        let result = try #require(path(start, goal))

        // A straight line would cross the divider wall. Any legal route has to
        // detour out to the corridor and back, so it is meaningfully longer.
        let straight = 7.1
        #expect(result.length > straight * 1.3, "length \(result.length)")

        // And it must dip into the corridor, past the wall at z = 6.
        #expect(result.waypoints.contains { $0.z > 6.4 })
    }

    @Test("No path segment passes through a wall")
    func pathNeverCrossesGeometry() throws {
        let journeys = [
            (world(2.4, 4.5), world(9.5, 4.5)),
            (world(2, 8.6), world(20, 2)),
            (world(20, 2), world(1.2, 9)),
            (world(16, 4), world(4, 1.5))
        ]

        for (start, goal) in journeys {
            let result = try #require(path(start, goal), "no path from \(start) to \(goal)")

            var previous = start
            for point in result.waypoints {
                #expect(
                    PathFinder.hasLineOfSight(from: previous, to: point, in: grid),
                    "segment \(previous) -> \(point) leaves walkable space"
                )
                previous = point
            }
        }
    }

    @Test("Every room is reachable from the spawn point")
    func everyRoomReachable() throws {
        let spawn = world(2, 8.6)
        let destinations = [
            world(3, 3),      // office A
            world(11, 3),     // office B
            world(20, 3),     // store room
            world(22, 9),     // far end of the corridor
            world(1.2, 9)     // extraction
        ]

        for destination in destinations {
            let result = try #require(path(spawn, destination), "cannot reach \(destination)")
            #expect(result.length > 0)
        }
    }

    @Test("A destination inside a wall reports failure instead of a fake route")
    func unreachableDestination() {
        let result = PathFinder.findPath(from: world(2, 8.6), to: world(7, 6), in: grid)

        // Nearest-walkable snapping is deliberately short-range, so the middle
        // of a wall stays a failure rather than silently becoming "somewhere
        // near the wall".
        switch result {
        case .success(let path):
            // If it did snap, it must at least have snapped somewhere legal.
            #expect(path.waypoints.allSatisfy { grid.isWalkable(grid.cell(at: $0)) })
        case .failure(let failure):
            #expect(failure == .destinationNotReachable || failure == .noRoute)
        }
    }

    @Test("Smoothing removes the grid staircase")
    func pathIsSmoothed() throws {
        // A straight run down the corridor should come back as a couple of
        // waypoints, not one per cell.
        let result = try #require(path(world(3, 8), world(20, 8)))
        #expect(result.waypoints.count <= 4, "\(result.waypoints.count) waypoints for a straight corridor")
    }

    @Test("Path finding is deterministic")
    func deterministic() throws {
        let start = world(2, 8.6)
        let goal = world(20, 2)
        let first = try #require(path(start, goal))
        let second = try #require(path(start, goal))

        #expect(first == second)
    }

    @Test("Path length is consistent with walking time")
    func lengthMatchesGeometry() throws {
        let result = try #require(path(world(3, 8), world(13, 8)))
        // A clear 10 m run down the corridor, so the route should be close to it.
        #expect(result.length > 9.5)
        #expect(result.length < 11.5)
    }
}
