import Testing
@testable import HeistCore

@Suite("Path walking")
struct PathWalkerTests {
    func point(_ x: Double, _ z: Double) -> WorldPoint {
        WorldPoint(x: x, y: 0, z: z)
    }

    /// Walks a route to completion at a fixed tick, returning position and time.
    func walk(
        _ walker: inout PathWalker,
        from start: WorldPoint,
        speed: Double,
        tick: Double = 1.0 / 60,
        limit: Int = 10_000
    ) -> (position: WorldPoint, elapsed: Double, stalled: Bool) {
        var position = start
        var elapsed = 0.0
        for _ in 0..<limit {
            let step = walker.advance(from: position, speed: speed, deltaTime: tick)
            position = step.position
            elapsed += tick
            if step.isStalled { return (position, elapsed, true) }
            if step.isFinished { return (position, elapsed, false) }
        }
        return (position, elapsed, false)
    }

    @Test("Walking a straight run takes distance over speed")
    func timingMatchesDistance() {
        var walker = PathWalker(waypoints: [point(10, 0)])
        let result = walk(&walker, from: point(0, 0), speed: 2.0)

        #expect(walker.isFinished)
        // 10 m at 2 m/s, within one tick.
        #expect(abs(result.elapsed - 5.0) < 0.02, "took \(result.elapsed) s")
        #expect(result.position.planarDistance(to: point(10, 0)) < 0.001)
    }

    @Test("Timing is independent of frame rate")
    func frameRateIndependent() {
        var fast = PathWalker(waypoints: [point(12, 0)])
        var slow = PathWalker(waypoints: [point(12, 0)])

        let atSixty = walk(&fast, from: point(0, 0), speed: 1.5, tick: 1.0 / 60)
        let atThirty = walk(&slow, from: point(0, 0), speed: 1.5, tick: 1.0 / 30)

        // This is what makes a plan's ETA trustworthy on any device.
        #expect(abs(atSixty.elapsed - atThirty.elapsed) < 0.05)
    }

    @Test("A corner is turned without overshooting")
    func turnsCorners() {
        var walker = PathWalker(waypoints: [point(5, 0), point(5, 5)])
        let result = walk(&walker, from: point(0, 0), speed: 3.0)

        #expect(walker.isFinished)
        #expect(result.position.planarDistance(to: point(5, 5)) < 0.001)
        // 10 m of path at 3 m/s.
        #expect(abs(result.elapsed - 10.0 / 3.0) < 0.05)
    }

    @Test("Facing follows the direction of travel")
    func facesTravel() {
        var walker = PathWalker(waypoints: [point(0, 8)])
        let step = walker.advance(from: point(0, 0), speed: 1.4, deltaTime: 1.0 / 60)

        let facing = try! #require(step.facing)
        #expect(facing.z > 0.99)
        #expect(abs(facing.x) < 0.01)
    }

    @Test("A big time step does not skip past waypoints")
    func handlesLargeSteps() {
        var walker = PathWalker(waypoints: [point(2, 0), point(2, 2), point(0, 2)])
        // One second at 10 m/s covers the whole 6 m route in a single tick.
        let step = walker.advance(from: point(0, 0), speed: 10, deltaTime: 1.0)

        #expect(step.isFinished)
        #expect(step.position.planarDistance(to: point(0, 2)) < 0.001)
    }

    @Test("Duplicate waypoints do not wedge the walker")
    func duplicateWaypoints() {
        var walker = PathWalker(waypoints: [point(1, 0), point(1, 0), point(2, 0)])
        let result = walk(&walker, from: point(0, 0), speed: 1.0)

        #expect(walker.isFinished)
        #expect(!result.stalled)
    }

    @Test("An actor that cannot progress reports a stall instead of standing mute")
    func reportsStall() {
        var walker = PathWalker(waypoints: [point(5, 0)])
        var stalled = false

        // Speed zero: no progress is possible, and the walker must say so rather
        // than leave the caller guessing.
        for _ in 0..<200 {
            let step = walker.advance(from: point(0, 0), speed: 1.0, deltaTime: 0.1)
            // Feeding the same position back simulates being wedged on geometry.
            if step.isStalled { stalled = true; break }
        }

        #expect(stalled)
    }

    @Test("Walking is deterministic")
    func deterministic() {
        var first = PathWalker(waypoints: [point(3, 0), point(3, 4)])
        var second = PathWalker(waypoints: [point(3, 0), point(3, 4)])

        let a = walk(&first, from: point(0, 0), speed: 1.4)
        let b = walk(&second, from: point(0, 0), speed: 1.4)

        #expect(a.position == b.position)
        #expect(a.elapsed == b.elapsed)
    }
}
