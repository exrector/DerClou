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

    @Test("On the camera's own axis, height takes no room on screen at rest")
    func restIsAPlanViewOnAxis() throws {
        let projection = projection()
        // Directly below the camera, height genuinely does not move the screen
        // point: the offset from the boresight is zero at any elevation, exactly,
        // perspective or not. This is the resting view the owner asked for.
        let foot = WorldPoint(x: projection.focus.x, y: 0, z: projection.focus.z)
        let head = WorldPoint(x: projection.focus.x, y: level.metrics.wallHeight, z: projection.focus.z)

        let onScreenFoot = try #require(projection.screenPoint(of: foot, viewportSize: viewport))
        let onScreenHead = try #require(projection.screenPoint(of: head, viewportSize: viewport))

        #expect(abs(onScreenHead.x - onScreenFoot.x) < 1e-6)
        #expect(abs(onScreenHead.y - onScreenFoot.y) < 1e-6)
    }

    @Test("Off axis at rest, a narrow field of view keeps height's parallax small")
    func restParallaxIsSmall() throws {
        // The trade this camera makes: real perspective, so real shadows, but
        // only a small, bounded amount of parallax from a wall's height even
        // away from dead centre — the field of view is chosen narrow enough
        // that this stays under a few points, not the many it would be at a
        // normal field of view.
        let projection = projection()
        let foot = WorldPoint(x: 3, y: 0, z: 9)
        let head = WorldPoint(x: 3, y: level.metrics.wallHeight, z: 9)

        let onScreenFoot = try #require(projection.screenPoint(of: foot, viewportSize: viewport))
        let onScreenHead = try #require(projection.screenPoint(of: head, viewportSize: viewport))

        let moved = ((onScreenHead.x - onScreenFoot.x) * (onScreenHead.x - onScreenFoot.x)
            + (onScreenHead.y - onScreenFoot.y) * (onScreenHead.y - onScreenFoot.y)).squareRoot()
        #expect(moved < 8, "a wall's height moved \(moved) points off its own footprint at rest")
    }

    @Test("Tilting gives height its own place on screen")
    func tiltShowsHeight() throws {
        let projection = projection(CameraControl(leanVertical: 40))
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

    // MARK: - Tilting: free, symmetric, independent

    @Test("Tilt is bounded, the same in every direction on both axes")
    func tiltIsBoundedSymmetrically() {
        let tilted = CameraControl().tilted(vertical: 200, horizontal: -200)

        #expect(tilted.leanVertical == CameraControl.leanRange.upperBound)
        #expect(tilted.leanHorizontal == CameraControl.leanRange.lowerBound)

        let opposite = CameraControl().tilted(vertical: -200, horizontal: 200)
        #expect(opposite.leanVertical == CameraControl.leanRange.lowerBound)
        #expect(opposite.leanHorizontal == CameraControl.leanRange.upperBound)
    }

    @Test("Dragging up and dragging down are mirror images of each other")
    func verticalTiltIsSymmetric() {
        // This is the bug the owner hit: tilt used to only go one way, so
        // dragging "up" hit a wall at rest and did nothing while dragging
        // "down" worked. Both directions now move the camera by the same
        // amount, in opposite directions.
        let rest = projection()
        let down = projection(CameraControl(leanVertical: 30))
        let up = projection(CameraControl(leanVertical: -30))

        #expect(abs(down.position.z - rest.position.z) > 0.5)
        #expect(abs(up.position.z - rest.position.z) > 0.5)
        #expect(abs((down.position.z - rest.position.z) + (up.position.z - rest.position.z)) < 1e-9)
    }

    @Test("Dragging left and dragging right are mirror images of each other")
    func horizontalTiltIsSymmetric() {
        let rest = projection()
        let right = projection(CameraControl(leanHorizontal: 30))
        let left = projection(CameraControl(leanHorizontal: -30))

        #expect(abs(right.position.x - rest.position.x) > 0.5)
        #expect(abs(left.position.x - rest.position.x) > 0.5)
        #expect(abs((right.position.x - rest.position.x) + (left.position.x - rest.position.x)) < 1e-9)
    }

    @Test("Horizontal tilt works from a dead-flat rest, with no vertical tilt needed first")
    func horizontalTiltNeedsNoVerticalTiltFirst() {
        // The bug behind "непонятно куда пальцем водить": an earlier version
        // expressed tilt as one polar angle plus an azimuth around it, so a
        // sideways drag did nothing until a vertical drag had tilted the view
        // away from straight down. The two axes are independent now.
        let rest = projection()
        let turned = projection(CameraControl(leanHorizontal: 15))

        #expect(abs(turned.position.x - rest.position.x) > 0.5)
    }

    @Test("The two tilt axes do not interact")
    func tiltAxesAreIndependent() {
        let vertical = projection(CameraControl(leanVertical: 20))
        let both = projection(CameraControl(leanVertical: 20, leanHorizontal: 15))

        // Adding a horizontal tilt does not change how far the vertical one
        // moved the camera on its own axis.
        #expect(abs(both.position.z - vertical.position.z) < 1e-9)
    }

    @Test("Tilting does not change the frame's size — only zoom does")
    func tiltingDoesNotResize() {
        // What made the earlier camera feel jerky: it recomputed how much of
        // the level had to fit on screen from the *live* tilt, so panning and
        // zooming happened at once while the player was only trying to look
        // around. The frame is solved once, at rest, now.
        let rest = projection()
        for control in [
            CameraControl(leanVertical: 45),
            CameraControl(leanHorizontal: -45),
            CameraControl(leanVertical: 60, leanHorizontal: 60)
        ] {
            let tilted = projection(control)
            #expect(tilted.verticalExtent == rest.verticalExtent)
            #expect(tilted.focus == rest.focus)
        }
    }

    @Test("A tap projects back to the pixel it came from")
    func projectionRoundTrip() throws {
        for control in [
            CameraControl.neutral,
            CameraControl(leanVertical: -10, leanHorizontal: 18, zoom: 1.8)
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

    @Test("Rays fan out, but only within the narrow field of view")
    func raysStayWithinTheFieldOfView() throws {
        // A real perspective camera, unlike the off-axis orthographic one this
        // replaced: rays are not parallel. What makes it read as close to
        // orthographic is that the fan is narrow — bounded by the field of view,
        // a few degrees wide rather than tens.
        let projection = projection()
        let centre = try #require(projection.ray(
            screenPoint: (x: viewport.width / 2, y: viewport.height / 2), viewportSize: viewport
        ))
        let edge = try #require(projection.ray(
            screenPoint: (x: 40, y: 200), viewportSize: viewport
        ))

        let cosAngle = centre.direction.dot(edge.direction)
        let angleDegrees = acos(min(max(cosAngle, -1), 1)) * 180 / .pi
        #expect(angleDegrees < CameraProjectionSolver.defaultFieldOfViewDegrees)

        let left = edge
        let right = try #require(projection.ray(
            screenPoint: (x: 800, y: 100), viewportSize: viewport
        ))
        #expect(abs(left.direction.x - right.direction.x) < 0.2)
        #expect(abs(left.direction.y - right.direction.y) < 0.01)
        #expect(abs(left.direction.z - right.direction.z) < 0.03)
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

    @Test("At rest the camera hangs straight above the level's centre")
    func cameraPlacement() {
        let rest = projection()

        #expect(rest.focus.x == 12)
        #expect(rest.position.y > 10)
        #expect(abs(rest.position.x - rest.focus.x) < 1e-9)
        #expect(abs(rest.position.z - rest.focus.z) < 1e-9)

        // Tilting is what stands it off toward +z.
        #expect(projection(CameraControl(leanVertical: 35)).position.z > rest.focus.z)
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

    @Test("Zoom is clamped and leaves the tilt alone")
    func zoomIndependentOfTilt() {
        let control = CameraControl(leanVertical: 8).zoomed(by: 10)

        #expect(control.zoom == CameraControl.zoomRange.upperBound)
        #expect(control.leanVertical == 8)
    }

    @Test("Pinching holds the point under the fingers in place, not just the level's centre")
    func zoomCanAnchorAwayFromCentre() throws {
        // The bug: `zoomed(by:)` alone always scales toward the level's own
        // centre, because it never touches `focusOffset`. This reproduces what
        // the view does with a pinch that starts off-centre — resolve the
        // world point under the fingers, zoom, then correct the focus by
        // exactly how far that point drifted — and checks the point lands
        // back where the fingers are, not somewhere toward the middle.
        let start = projection()
        let anchorScreen = (x: 700.0, y: 120.0) // well off from the screen's centre
        let anchorWorld = try #require(
            start.ray(screenPoint: anchorScreen, viewportSize: viewport)?.hit()
        )

        var control = CameraControl.neutral.zoomed(by: 2.2)
        var after = projection(control)
        let drifted = try #require(
            after.ray(screenPoint: anchorScreen, viewportSize: viewport)?.hit()
        )

        control = control.focused(at: WorldPoint(
            x: control.focusOffset.x + (anchorWorld.x - drifted.x),
            y: 0,
            z: control.focusOffset.z + (anchorWorld.z - drifted.z)
        ))
        after = projection(control)

        let landedAt = try #require(after.screenPoint(of: anchorWorld, viewportSize: viewport))
        #expect(abs(landedAt.x - anchorScreen.x) < 0.5)
        #expect(abs(landedAt.y - anchorScreen.y) < 0.5)

        // And it actually zoomed, rather than just re-centring at zoom 1.
        #expect(after.verticalExtent < start.verticalExtent)
    }

    @Test("Clamping the stored control matches what solving would have clamped anyway")
    func clampAgreesWithSolve() {
        // The point of exposing `clamp` separately: the *stored* control has
        // to carry the same limit the projection enforces, or a drag that
        // keeps pushing past an edge accumulates an invisible overshoot that
        // has to be dragged back through before the view moves again — the
        // camera "catching up" all at once reads as a jerk. This checks the
        // two paths agree, not just that clamping does something.
        let control = CameraControl(zoom: 2, focusOffset: WorldPoint(x: 200, y: 0, z: 200))
        let clamped = CameraProjectionSolver.clamp(
            control, bounds: level.bounds, metrics: level.metrics, aspectRatio: viewport.width / viewport.height
        )

        let viaClamp = CameraProjectionSolver.solve(
            bounds: level.bounds, metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height, control: clamped
        )
        let viaSolveDirectly = CameraProjectionSolver.solve(
            bounds: level.bounds, metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height, control: control
        )

        #expect(viaClamp.focus == viaSolveDirectly.focus)
        // And a control already inside the building passes through untouched.
        #expect(CameraProjectionSolver.clamp(
            .neutral, bounds: level.bounds, metrics: level.metrics, aspectRatio: viewport.width / viewport.height
        ) == .neutral)
    }
}
