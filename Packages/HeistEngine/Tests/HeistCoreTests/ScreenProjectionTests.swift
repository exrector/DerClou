import Testing
@testable import HeistCore

@Suite("Screen projection")
struct ScreenProjectionTests {
    let level = LevelBlueprint.office01
    let viewport = (width: 874.0, height: 402.0)

    var framing: CameraFraming {
        CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height,
            tiltDegrees: 24
        )
    }

    func floorPoint(x: Double, y: Double) -> WorldPoint? {
        guard let ray = ScreenProjection.ray(
            screenPoint: (x: x, y: y),
            viewportSize: viewport,
            framing: framing
        ) else { return nil }
        return ScreenProjection.hit(ray)
    }

    @Test("Tapping the middle of the screen lands on the camera focus")
    func centreTap() throws {
        let point = try #require(floorPoint(x: viewport.width / 2, y: viewport.height / 2))

        #expect(abs(point.x - framing.focus.x) < 0.001)
        #expect(abs(point.z - framing.focus.z) < 0.001)
        #expect(abs(point.y) < 0.001)
    }

    @Test("Tapping right of centre moves the world point in +x")
    func horizontalMapping() throws {
        let centre = try #require(floorPoint(x: viewport.width / 2, y: viewport.height / 2))
        let right = try #require(floorPoint(x: viewport.width * 0.75, y: viewport.height / 2))

        #expect(right.x > centre.x)
        #expect(abs(right.z - centre.z) < 0.001)
    }

    @Test("Tapping above centre moves the world point away from the camera")
    func verticalMapping() throws {
        let centre = try #require(floorPoint(x: viewport.width / 2, y: viewport.height / 2))
        let up = try #require(floorPoint(x: viewport.width / 2, y: viewport.height * 0.25))

        // The camera sits at +z looking toward -z, so "up the screen" is -z.
        #expect(up.z < centre.z)
        #expect(abs(up.x - centre.x) < 0.001)
    }

    @Test("The whole level is reachable within the viewport")
    func levelIsReachable() throws {
        let topLeft = try #require(floorPoint(x: 0, y: 0))
        let bottomRight = try #require(floorPoint(x: viewport.width, y: viewport.height))

        let metrics = level.metrics
        let minX = metrics.meters(fromCells: level.bounds.minX)
        let maxX = metrics.meters(fromCells: level.bounds.maxX)
        let minZ = metrics.meters(fromCells: level.bounds.minY)
        let maxZ = metrics.meters(fromCells: level.bounds.maxY)

        #expect(topLeft.x < minX)
        #expect(bottomRight.x > maxX)
        #expect(topLeft.z < minZ)
        #expect(bottomRight.z > maxZ)
    }

    @Test("Screen and world round-trip through the thief's spawn point")
    func spawnRoundTrip() throws {
        // The thief spawns at cell (2.0, 8.6) = world (2.0, 0, 8.6). Find the
        // screen position that maps there by bisecting, then confirm the tap at
        // that position resolves back to the same spot.
        let target = level.metrics.worldPoint(CellPoint(2.0, 8.6))

        // Under perspective the two screen axes are coupled — moving down the
        // screen changes the depth, which changes the world x a column maps to —
        // so solve them alternately until both settle.
        var screenX = viewport.width / 2
        var screenY = viewport.height / 2

        for _ in 0..<4 {
            var low = 0.0
            var high = viewport.width
            for _ in 0..<40 {
                let mid = (low + high) / 2
                let point = try #require(floorPoint(x: mid, y: screenY))
                if point.x < target.x { low = mid } else { high = mid }
            }
            screenX = (low + high) / 2

            low = 0
            high = viewport.height
            for _ in 0..<40 {
                let mid = (low + high) / 2
                let point = try #require(floorPoint(x: screenX, y: mid))
                if point.z < target.z { low = mid } else { high = mid }
            }
            screenY = (low + high) / 2
        }

        let resolved = try #require(floorPoint(x: screenX, y: screenY))
        #expect(abs(resolved.x - target.x) < 0.01)
        #expect(abs(resolved.z - target.z) < 0.01)
    }

    @Test("A degenerate viewport yields no ray instead of a bad one")
    func degenerateViewport() {
        let ray = ScreenProjection.ray(
            screenPoint: (x: 10, y: 10),
            viewportSize: (width: 0, height: 0),
            framing: framing
        )
        #expect(ray == nil)
    }
}
