import Foundation
import Testing
@testable import HeistCore

/// The contract of the tactical camera, tested where it is defined: on the
/// projection of world points, not on rendered pixels.
@Suite("Camera projection")
struct CameraProjectionTests {
    let level = LevelBlueprint.office01
    /// iPhone 16 in landscape.
    let viewport = (width: 852.0, height: 393.0)

    func projection(_ control: CameraControl = .neutral, mode: FramingMode = .fit) -> CameraProjection {
        CameraProjectionSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height,
            mode: mode,
            control: control
        )
    }

    // MARK: - Parallel projection

    @Test("Equal distances are equal wherever they are on screen")
    func scaleIsUniform() throws {
        // The whole reason for a parallel projection. A perspective camera would
        // draw the far pair smaller than the near one, and a planning game is
        // one where the player compares two routes by eye.
        let projection = projection()

        func span(from: WorldPoint, to: WorldPoint) throws -> Double {
            let a = try #require(projection.screenPoint(of: from, viewportSize: viewport))
            let b = try #require(projection.screenPoint(of: to, viewportSize: viewport))
            return ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }

        let near = try span(
            from: WorldPoint(x: 3, y: 0, z: 9),
            to: WorldPoint(x: 7, y: 0, z: 9)
        )
        let far = try span(
            from: WorldPoint(x: 15, y: 0, z: 1),
            to: WorldPoint(x: 19, y: 0, z: 1)
        )

        #expect(abs(near - far) < 0.001, "near \(near) points, far \(far)")
    }

    @Test("A rectangular building stays a rectangle")
    func noKeystone() throws {
        let metrics = level.metrics
        let minX = metrics.meters(fromCells: level.bounds.minX)
        let maxX = metrics.meters(fromCells: level.bounds.maxX)
        let minZ = metrics.meters(fromCells: level.bounds.minY)
        let maxZ = metrics.meters(fromCells: level.bounds.maxY)

        let projection = projection()
        func screen(_ x: Double, _ z: Double) throws -> (x: Double, y: Double) {
            try #require(projection.screenPoint(
                of: WorldPoint(x: x, y: 0, z: z), viewportSize: viewport
            ))
        }

        let farLeft = try screen(minX, minZ)
        let farRight = try screen(maxX, minZ)
        let nearLeft = try screen(minX, maxZ)
        let nearRight = try screen(maxX, maxZ)

        // The far edge and the near edge are the same length on screen, and both
        // sides are vertical. That is what a keystone destroys.
        #expect(abs((farRight.x - farLeft.x) - (nearRight.x - nearLeft.x)) < 0.001)
        #expect(abs(farLeft.x - nearLeft.x) < 0.001)
        #expect(abs(farRight.x - nearRight.x) < 0.001)
    }

    @Test("The tilt gives height its own place on screen")
    func tiltShowsHeight() throws {
        let projection = projection()
        let foot = WorldPoint(x: 12, y: 0, z: 5)
        let head = WorldPoint(x: 12, y: level.metrics.wallHeight, z: 5)

        let onScreenFoot = try #require(projection.screenPoint(of: foot, viewportSize: viewport))
        let onScreenHead = try #require(projection.screenPoint(of: head, viewportSize: viewport))

        // Straight up in the world is straight up the screen, and it covers real
        // distance — otherwise the view is a plan drawing.
        #expect(abs(onScreenHead.x - onScreenFoot.x) < 0.001)
        #expect(onScreenFoot.y - onScreenHead.y > 20)
    }

    @Test("Screen up is world -z, screen right is world +x")
    func screenAxes() {
        let (right, up, forward) = projection().basis

        #expect(right.x > 0.999)
        #expect(abs(right.z) < 1e-9)
        #expect(up.z < 0)
        #expect(forward.y < 0)
    }

    // MARK: - Peeking

    @Test("Peeking turns the view and lifts it, within a small range")
    func peekIsBounded() {
        let peeked = CameraControl().peeked(pitch: 90, yaw: -90)

        #expect(peeked.pitch == CameraControl.pitchRange.upperBound)
        #expect(peeked.yaw == CameraControl.yawRange.lowerBound)
    }

    @Test("Turning the view moves the camera off the level's centre line")
    func yawMovesTheCamera() {
        let rest = projection()
        let turned = projection(CameraControl(yaw: 20))

        #expect(abs(turned.position.x - rest.position.x) > 1)
        // And it is the same level, framed the same way: peeking is a look
        // around, not a different shot.
        #expect(abs(turned.verticalExtent - rest.verticalExtent) < 0.001)
    }

    @Test("A tap projects back to the pixel it came from")
    func projectionRoundTrip() throws {
        for control in [
            CameraControl.neutral,
            CameraControl(pitch: -10, yaw: 18, zoom: 1.8)
        ] {
            let projection = projection(control)
            let screen = (x: 300.0, y: 210.0)

            let ray = try #require(projection.ray(screenPoint: screen, viewportSize: viewport))
            let onTheFloor = try #require(ray.hit())
            let back = try #require(projection.screenPoint(of: onTheFloor, viewportSize: viewport))

            #expect(abs(back.x - screen.x) < 0.5)
            #expect(abs(back.y - screen.y) < 0.5)
        }
    }

    @Test("Rays run parallel, as a parallel projection requires")
    func raysAreParallel() throws {
        let projection = projection()
        let left = try #require(projection.ray(
            screenPoint: (x: 40, y: 200), viewportSize: viewport
        ))
        let right = try #require(projection.ray(
            screenPoint: (x: 800, y: 100), viewportSize: viewport
        ))

        #expect(abs(left.direction.x - right.direction.x) < 1e-9)
        #expect(abs(left.direction.y - right.direction.y) < 1e-9)
        #expect(abs(left.direction.z - right.direction.z) < 1e-9)
    }

    // MARK: - Framing

    @Test("Fitting never crops, whatever the aspect ratio")
    func fitNeverCrops() {
        for aspect in [1.0, 1.33, 1.78, 2.17, 2.5] {
            let projection = CameraProjectionSolver.solve(
                bounds: level.bounds,
                metrics: level.metrics,
                aspectRatio: aspect,
                mode: .fit
            )
            #expect(projection.showsWholeLevel, "aspect \(aspect) cropped \(projection.croppedDepth) m")
        }
    }

    @Test("The camera looks at the level from above and behind")
    func cameraPlacement() {
        let projection = projection()

        #expect(projection.focus.x == 12)
        #expect(projection.position.y > 10)
        // Tilted, so it stands off toward +z rather than straight overhead.
        #expect(projection.position.z > projection.focus.z)
    }

    @Test("Zooming in shows less")
    func zoomShowsLess() {
        #expect(projection(CameraControl(zoom: 2)).verticalExtent < projection().verticalExtent)
    }

    @Test("At neutral zoom the view cannot be moved off centre")
    func neutralZoomIsPinned() {
        let control = CameraControl(focusOffset: WorldPoint(x: 30, y: 0, z: 30))
            .clampedToLevel(
                bounds: level.bounds,
                metrics: level.metrics,
                visibleWidth: level.metrics.meters(fromCells: level.bounds.size.width),
                visibleDepth: level.metrics.meters(fromCells: level.bounds.size.depth)
            )

        #expect(control.focusOffset == .zero)
    }

    @Test("Zoomed in, the frame still cannot leave the floor")
    func zoomedFrameStaysInside() {
        let metrics = level.metrics
        let levelWidth = metrics.meters(fromCells: level.bounds.size.width)
        let levelDepth = metrics.meters(fromCells: level.bounds.size.depth)

        let control = CameraControl(zoom: 2, focusOffset: WorldPoint(x: 100, y: 0, z: 100))
            .clampedToLevel(
                bounds: level.bounds,
                metrics: metrics,
                visibleWidth: levelWidth / 2,
                visibleDepth: levelDepth / 2
            )

        #expect(abs(control.focusOffset.x - levelWidth / 4) < 0.001)
        #expect(abs(control.focusOffset.z - levelDepth / 4) < 0.001)
    }

    @Test("Zoom is clamped and leaves the peek alone")
    func zoomIndependentOfPeek() {
        let control = CameraControl(pitch: 8).zoomed(by: 10)

        #expect(control.zoom == CameraControl.zoomRange.upperBound)
        #expect(control.pitch == 8)
    }
}
