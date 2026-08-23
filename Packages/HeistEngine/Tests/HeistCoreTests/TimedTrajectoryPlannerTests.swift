import Testing
@testable import HeistCore

@Suite("Time-aware route planning")
struct TimedTrajectoryPlannerTests {
    private let grid = NavGrid(
        minX: -5, minZ: -5, cellSize: 0.2,
        columns: 50, rows: 50,
        walkable: [Bool](repeating: true, count: 2_500)
    )

    @Test("A newly tapped route avoids an older moving trajectory before starting")
    func olderTrajectoryKeepsCorridor() throws {
        let start = WorldPoint(x: -2, y: 0, z: 0)
        let destination = WorldPoint(x: 2, y: 0, z: 0)
        let initial = try PathFinder.findPath(
            from: start,
            to: destination,
            in: grid,
            character: .standard
        ).get()
        let guardSamples = stride(from: 0.0, through: 4.0, by: 0.1).map { time in
            TimedAgentPosition(
                missionTime: time,
                position: WorldPoint(x: 0, y: 0, z: -2 + time)
            )
        }
        let request = NavigationPlanRequest(
            id: 1,
            actorID: "thief",
            worldRevision: 0,
            start: start,
            destination: destination,
            character: .standard,
            topology: .grid(grid),
            startedAt: 0,
            initialFacing: 90,
            trajectoryCommittedAt: 1,
            tieBreakerPriority: 50,
            avoidanceGrid: grid,
            reservedTrajectories: [ReservedAgentTrajectory(
                actorID: "guard",
                radius: CharacterProfile.standard.radius,
                committedAt: 0,
                tieBreakerPriority: 10,
                samples: guardSamples
            )]
        )

        let result = TimedTrajectoryPlanner.refine(
            request: request,
            initialPath: initial,
            in: grid
        )

        #expect(result.waypoints.count >= 2)
        #expect(result.waypoints.last == destination)
        #expect(result.length > initial.length)
    }

    @Test("A later reservation cannot displace an already committed route")
    func laterTrajectoryDoesNotOwnCorridor() throws {
        let start = WorldPoint(x: -2, y: 0, z: 0)
        let destination = WorldPoint(x: 2, y: 0, z: 0)
        let initial = try PathFinder.findPath(from: start, to: destination, in: grid).get()
        let request = NavigationPlanRequest(
            id: 2,
            actorID: "first-mover",
            worldRevision: 0,
            start: start,
            destination: destination,
            character: .standard,
            topology: .grid(grid),
            trajectoryCommittedAt: 1,
            avoidanceGrid: grid,
            reservedTrajectories: [ReservedAgentTrajectory(
                actorID: "late-mover",
                radius: 0.3,
                committedAt: 2,
                tieBreakerPriority: 10,
                samples: [
                    .init(missionTime: 0, position: .init(x: 0, y: 0, z: -2)),
                    .init(missionTime: 4, position: .init(x: 0, y: 0, z: 2))
                ]
            )]
        )

        let result = TimedTrajectoryPlanner.refine(
            request: request,
            initialPath: initial,
            in: grid
        )

        #expect(result == PathFinder.minimumLinkPath(from: start, path: initial, in: grid))
    }
}
