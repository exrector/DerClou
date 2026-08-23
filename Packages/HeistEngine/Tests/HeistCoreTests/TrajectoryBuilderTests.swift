import Testing
@testable import HeistCore

@Suite("Comfortable locomotion trajectory")
struct TrajectoryBuilderTests {
    private let openGrid = NavGrid(
        minX: -2,
        minZ: -2,
        cellSize: 0.1,
        columns: 80,
        rows: 80,
        walkable: [Bool](repeating: true, count: 6_400)
    )

    @Test("A right-angle path becomes a deterministic rounded corner")
    func roundsCorner() {
        let start = WorldPoint(x: 0, y: 0, z: 0)
        let raw = PathResult(
            waypoints: [WorldPoint(x: 2, y: 0, z: 0), WorldPoint(x: 2, y: 0, z: 2)],
            length: 4
        )
        let rounded = TrajectoryBuilder.rounded(
            start: start,
            path: raw,
            in: openGrid,
            character: .standard
        )

        #expect(rounded.waypoints.count > raw.waypoints.count)
        #expect(!rounded.waypoints.contains(WorldPoint(x: 2, y: 0, z: 0)))
        #expect(rounded == TrajectoryBuilder.rounded(
            start: start, path: raw, in: openGrid, character: .standard
        ))
    }

    @Test("Rounding never leaves the walkable corridor")
    func roundedOfficePathStaysLegal() throws {
        let geometry = LevelGeometryBuilder.build(.office01)
        let grid = NavGridBuilder.build(geometry: geometry)
        let start = LevelMetrics.standard.worldPoint(CellPoint(2.4, 4.5))
        let goal = LevelMetrics.standard.worldPoint(CellPoint(9.5, 4.5))
        let raw = try PathFinder.findPath(from: start, to: goal, in: grid).get()
        let rounded = TrajectoryBuilder.rounded(
            start: start, path: raw, in: grid, character: .standard
        )

        var previous = start
        for point in rounded.waypoints {
            #expect(PathFinder.hasLineOfSight(from: previous, to: point, in: grid))
            previous = point
        }
    }

    @Test("A replacement route steers from the current heading instead of pivoting")
    func replacementRouteHasContinuousHeading() {
        let start = WorldPoint(x: 0, y: 0, z: 0)
        let raw = PathResult(
            waypoints: [WorldPoint(x: 3, y: 0, z: 0)],
            length: 3
        )
        let trajectory = TrajectoryBuilder.continuous(
            start: start,
            path: raw,
            initialFacing: 0,
            in: openGrid,
            character: .standard
        )
        let first = trajectory.waypoints[0]
        let initialChordFacing = PatrolRoute.yaw(from: start, to: first)

        #expect(trajectory.waypoints.count > 2)
        #expect(abs(PatrolRoute.shortestTurn(from: 0, to: initialChordFacing)) < 4)

        let task = AgentNavigationTask(
            goal: .move(destination: raw.waypoints[0]),
            start: start,
            path: trajectory,
            startedAt: 0,
            speed: CharacterProfile.standard.walkSpeed,
            initialFacing: 0,
            worldRevision: 0,
            acceleration: CharacterProfile.standard.acceleration,
            deceleration: CharacterProfile.standard.deceleration,
            maximumTurnRateDegrees: CharacterProfile.standard.maximumTurnRateDegrees
        )
        #expect(task.state(at: 0.05).activity != .turningLeft)
        #expect(task.state(at: 0.05).activity != .turningRight)
    }

    @Test("A reversal remains an explicit turnaround")
    func reversalDoesNotInventAUSide() {
        let start = WorldPoint(x: 0, y: 0, z: 0)
        let raw = PathResult(
            waypoints: [WorldPoint(x: -2, y: 0, z: 0)],
            length: 2
        )
        let trajectory = TrajectoryBuilder.continuous(
            start: start,
            path: raw,
            initialFacing: 90,
            in: openGrid,
            character: .standard
        )

        #expect(trajectory == TrajectoryBuilder.rounded(
            start: start, path: raw, in: openGrid, character: .standard
        ))
    }

    @Test("Retarget heading matrix curves ordinary changes and pivots reversals")
    func retargetHeadingMatrix() {
        let start = WorldPoint(x: 0, y: 0, z: 0)
        let destination = WorldPoint(x: 0, y: 0, z: 5)
        let raw = PathResult(waypoints: [destination], length: 5)

        for initialFacing in stride(from: -180.0, through: 180.0, by: 15) {
            let trajectory = TrajectoryBuilder.continuous(
                start: start,
                path: raw,
                initialFacing: initialFacing,
                in: openGrid,
                character: .standard
            )
            let change = abs(PatrolRoute.shortestTurn(from: initialFacing, to: 0))

            if change > 110 {
                #expect(trajectory == raw)
            } else if change >= 4 {
                #expect(trajectory.waypoints.count > 1)
                let firstFacing = PatrolRoute.yaw(from: start, to: trajectory.waypoints[0])
                #expect(abs(PatrolRoute.shortestTurn(
                    from: initialFacing,
                    to: firstFacing
                )) < 4)
            }

            var previous = start
            for point in trajectory.waypoints {
                #expect(PathFinder.hasLineOfSight(from: previous, to: point, in: openGrid))
                previous = point
            }
            #expect(trajectory.waypoints.last == destination)
        }
    }

    @Test("Heading blending never leaves the walkable office grid")
    func continuousOfficePathStaysLegal() throws {
        let geometry = LevelGeometryBuilder.build(.office01)
        let grid = NavGridBuilder.build(geometry: geometry)
        let start = LevelMetrics.standard.worldPoint(CellPoint(2.4, 4.5))
        let goal = LevelMetrics.standard.worldPoint(CellPoint(9.5, 4.5))
        let raw = try PathFinder.findPath(from: start, to: goal, in: grid).get()
        let trajectory = TrajectoryBuilder.continuous(
            start: start,
            path: raw,
            initialFacing: 180,
            in: grid,
            character: .standard
        )

        var previous = start
        for point in trajectory.waypoints {
            #expect(PathFinder.hasLineOfSight(from: previous, to: point, in: grid))
            previous = point
        }
    }
}
