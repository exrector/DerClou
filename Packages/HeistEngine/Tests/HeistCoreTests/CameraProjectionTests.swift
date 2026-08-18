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

        // Not a mathematical zero any more: rest sits `restElevationDegrees`
        // off the pole on purpose (see `azimuthWorksAtRestElevation`), so
        // there is a small, real amount of perspective at rest now. The bound
        // stays tight enough to catch a real regression while allowing for
        // that.
        #expect(abs(near - far) < 1, "near \(near) points, far \(far)")
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

        // The far edge and the near edge are close to the same length on
        // screen, and both sides are close to vertical — "close to" rather
        // than exactly, now that rest sits a few degrees off the pole on
        // purpose (see `azimuthWorksAtRestElevation`), which is what a real
        // keystone would otherwise destroy outright.
        #expect(abs((farRight.x - farLeft.x) - (nearRight.x - nearLeft.x)) < 4)
        #expect(abs(farLeft.x - nearLeft.x) < 2)
        #expect(abs(farRight.x - nearRight.x) < 2)
    }

    @Test("On the camera's own boresight, height takes no room on screen")
    func restIsAPlanViewOnAxis() throws {
        // Any two points along the camera's own line of sight land on the
        // exact same pixel, regardless of how elevated the camera is — this
        // holds unconditionally, not just at a perfectly flat rest, which is
        // what makes it a safe invariant now that rest itself sits a few
        // degrees off the pole (see `CameraControl.restElevationDegrees`).
        let projection = projection()
        let forward = projection.basis.forward
        let near = projection.position + forward * (projection.distance * 0.5)
        let far = projection.position + forward * (projection.distance * 1.5)

        let onScreenNear = try #require(projection.screenPoint(of: near, viewportSize: viewport))
        let onScreenFar = try #require(projection.screenPoint(of: far, viewportSize: viewport))

        #expect(abs(onScreenNear.x - onScreenFar.x) < 1e-6)
        #expect(abs(onScreenNear.y - onScreenFar.y) < 1e-6)
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

    @Test("Climbing elevation gives height its own place on screen")
    func tiltShowsHeight() throws {
        let projection = projection(CameraControl(elevation: 40))
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

    // MARK: - Orbiting: free, wrapping, always live

    @Test("Elevation clamps at its ceiling and its floor; azimuth wraps instead")
    func orientationIsBoundedAndWrapped() {
        let climbed = CameraControl().oriented(elevation: 200, azimuth: 0)
        #expect(climbed.elevation == CameraControl.elevationRange.upperBound)

        let flattened = CameraControl().oriented(elevation: -200, azimuth: 0)
        #expect(flattened.elevation == CameraControl.elevationRange.lowerBound)

        // Azimuth has no edge to hit — 400° and 40° are the same heading, and
        // -30° is the same heading as 330°.
        let wrapped = CameraControl().oriented(elevation: CameraControl.restElevationDegrees, azimuth: 400)
        #expect(abs(wrapped.azimuth - 40) < 1e-9)

        let wrappedNegative = CameraControl().oriented(elevation: CameraControl.restElevationDegrees, azimuth: -30)
        #expect(abs(wrappedNegative.azimuth - 330) < 1e-9)
    }

    @Test("Elevation only climbs from rest — the far side is reached by turning, not by tilting past vertical")
    func elevationIsOneSided() {
        // The old lean model tilted both ways from rest; this one does not
        // need to, because azimuth already reaches every side by turning all
        // the way around. Climbing elevation only ever moves the camera
        // further from directly overhead.
        func horizontalOffset(_ projection: CameraProjection) -> Double {
            let dx = projection.position.x - projection.focus.x
            let dz = projection.position.z - projection.focus.z
            return (dx * dx + dz * dz).squareRoot()
        }

        let rest = projection()
        let climbed = projection(CameraControl(elevation: 40))
        let climbedMore = projection(CameraControl(elevation: 70))

        #expect(horizontalOffset(rest) < horizontalOffset(climbed))
        #expect(horizontalOffset(climbed) < horizontalOffset(climbedMore))
        #expect(CameraControl().oriented(elevation: -500, azimuth: 0).elevation == CameraControl.elevationRange.lowerBound)
    }

    @Test("Turning left and turning right are mirror images of each other")
    func azimuthIsSymmetric() {
        let rest = projection()
        let right = projection(CameraControl(azimuth: 30))
        let left = projection(CameraControl(azimuth: -30)) // wraps to 330

        #expect(abs(right.position.x - rest.position.x) > 0.01)
        #expect(abs(left.position.x - rest.position.x) > 0.01)
        #expect(abs((right.position.x - rest.position.x) + (left.position.x - rest.position.x)) < 1e-9)
    }

    @Test("Azimuth has a real effect even at rest elevation — no dead zone at the pole")
    func azimuthWorksAtRestElevation() {
        // The reason elevation cannot rest at exactly zero. Looking straight
        // down, every compass heading looks identical — a sideways drag would
        // do nothing, which is the exact "непонятно куда водить пальцем"
        // complaint the old coupled tilt+yaw model had, just for a genuine
        // geometric reason this time rather than a coding mistake.
        // `restElevationDegrees` keeps this — and the first pixel of any real
        // drag — off that dead point.
        let rest = projection()
        let turned = projection(CameraControl(azimuth: 15))

        #expect(abs(turned.position.x - rest.position.x) > 0.01)
    }

    @Test("Azimuth's effect grows with elevation, but is never suppressed to nothing")
    func azimuthScalesWithElevation() {
        // Elevation and azimuth are a genuine spherical pair, unlike the old
        // independent lean axes: azimuth sweeps a circle whose radius is
        // distance × sin(elevation), so the same turn moves the camera
        // further once elevation has climbed. That coupling is expected —
        // it is what "turn to face the tall side of the room" should feel
        // like. What must still hold is that the effect is never zero once
        // elevation is at least at its resting floor.
        let lowRest = projection(CameraControl(elevation: CameraControl.restElevationDegrees))
        let low = projection(CameraControl(elevation: CameraControl.restElevationDegrees, azimuth: 20))
        let highRest = projection(CameraControl(elevation: 50))
        let high = projection(CameraControl(elevation: 50, azimuth: 20))

        let lowEffect = abs(low.position.x - lowRest.position.x)
        let highEffect = abs(high.position.x - highRest.position.x)

        #expect(lowEffect > 0.01)
        #expect(highEffect > lowEffect)
    }

    @Test("Orbiting does not change the frame's size — only zoom does")
    func tiltingDoesNotResize() {
        // What made the earlier camera feel jerky: it recomputed how much of
        // the level had to fit on screen from the *live* tilt, so panning and
        // zooming happened at once while the player was only trying to look
        // around. The frame is solved once, at rest, now.
        let rest = projection()
        for control in [
            CameraControl(elevation: 45),
            CameraControl(azimuth: -45),
            CameraControl(elevation: 60, azimuth: 60)
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
            CameraControl(elevation: 40, azimuth: 18, zoom: 1.8)
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

    @Test("At rest the camera sits almost straight above the level's centre")
    func cameraPlacement() {
        let rest = projection()

        #expect(rest.focus.x == 12)
        #expect(rest.position.y > 10)
        // Not exactly overhead any more: `restElevationDegrees` holds a few
        // degrees off the pole on purpose (see `azimuthWorksAtRestElevation`),
        // and at azimuth 0 that lift shows up entirely in z, not x.
        #expect(abs(rest.position.x - rest.focus.x) < 1e-9)
        let expectedRestOffset = rest.distance * sin(CameraControl.restElevationDegrees * .pi / 180)
        #expect(abs((rest.position.z - rest.focus.z) - expectedRestOffset) < 1e-6)

        // Climbing elevation stands it off further.
        #expect(projection(CameraControl(elevation: 35)).position.z > rest.position.z)
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

    @Test("Zoom is clamped and leaves elevation and azimuth alone")
    func zoomIndependentOfOrbit() {
        let control = CameraControl(elevation: 30, azimuth: 8).zoomed(by: 10)

        #expect(control.zoom == CameraControl.zoomRange.upperBound)
        #expect(control.elevation == 30)
        #expect(control.azimuth == 8)
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
