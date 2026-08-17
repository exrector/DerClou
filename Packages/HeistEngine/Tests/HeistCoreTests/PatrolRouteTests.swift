import Testing
@testable import HeistCore

@Suite("Patrol route")
struct PatrolRouteTests {
    func point(_ x: Double, _ z: Double) -> WorldPoint {
        WorldPoint(x: x, y: 0, z: z)
    }

    /// A 10 x 4 m rectangle at 1 m/s with 2 s pauses: 28 m of walking plus four
    /// pauses = 36 s per circuit.
    var route: PatrolRoute {
        PatrolRoute(
            waypoints: [point(0, 0), point(10, 0), point(10, 4), point(0, 4)],
            speed: 1.0,
            pauseAtWaypoint: 2.0
        )
    }

    @Test("A circuit takes walking time plus pauses")
    func cycleDuration() {
        #expect(route.cycleDuration == 36.0)
    }

    @Test("The guard starts paused at the first waypoint")
    func start() {
        let state = route.state(at: 0)

        #expect(state.position == point(0, 0))
        #expect(state.isPaused)
    }

    @Test("Position is a direct function of time, not a simulation")
    func positionAtTime() {
        // 2 s pause, then walking east at 1 m/s: at t=7 the guard is 5 m along.
        let state = route.state(at: 7)

        #expect(abs(state.position.x - 5) < 0.001)
        #expect(abs(state.position.z) < 0.001)
        #expect(!state.isPaused)
        // Travelling +x means facing +x, which is 90° in blueprint yaw.
        #expect(abs(state.facing - 90) < 0.001)
    }

    @Test("The route repeats")
    func loops() {
        // The property a player relies on: learn the cycle once, trust it
        // forever. Compared with a tolerance because t and t + cycle are
        // different inputs — exact Double equality across them is not something
        // any wrapping arithmetic can promise, and 1 mm is far below anything
        // that could change an outcome.
        for time in stride(from: 0.0, through: 36.0, by: 0.7) {
            let first = route.state(at: time)
            let second = route.state(at: time + route.cycleDuration)
            let third = route.state(at: time + route.cycleDuration * 5)

            #expect(first.position.planarDistance(to: second.position) < 0.001, "at \(time)")
            #expect(first.position.planarDistance(to: third.position) < 0.001, "at \(time)")
            #expect(first.isPaused == second.isPaused, "at \(time)")
        }
    }

    @Test("Asking the same time twice gives the same answer")
    func deterministic() {
        #expect(route.state(at: 12.34) == route.state(at: 12.34))
    }

    @Test("Negative time is handled rather than crashing")
    func negativeTime() {
        let state = route.state(at: -5)
        #expect(state.position.x.isFinite)
    }

    @Test("A non-looping route holds its final pose")
    func nonLooping() {
        var route = self.route
        route.isLoop = false

        let end = route.state(at: 10_000)
        #expect(end.position == point(0, 4))
        #expect(end.isPaused)
    }

    @Test("Time spent walking a leg matches distance over speed")
    func legTiming() {
        // Second leg: 4 m north, entered after 2 s pause + 10 s walk + 2 s pause.
        let entry = 14.0
        let midway = route.state(at: entry + 2)

        #expect(abs(midway.position.x - 10) < 0.001)
        #expect(abs(midway.position.z - 2) < 0.001)
    }

    @Test("office01's guard route builds from the blueprint")
    func fromBlueprint() throws {
        let level = LevelBlueprint.office01
        let actor = try #require(level.actors.first { $0.id == "office01.guard.01" })
        let prototype = try #require(PropCatalog.standard[actor.prototype])

        let route = try #require(PatrolRoute(
            actor: actor,
            metrics: level.metrics,
            character: CharacterProfile(prototype: prototype)
        ))

        #expect(route.waypoints.count == 4)
        #expect(route.speed == 1.2)
        #expect(route.cycleDuration > 0)
        // The circuit has to be long enough to be worth timing a plan around.
        #expect(route.cycleDuration > 20)
    }
}
