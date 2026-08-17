import Foundation
import Testing
@testable import HeistCore

@Suite("Camera control")
struct CameraControlTests {
    let level = LevelBlueprint.office01
    let viewport = (width: 852.0, height: 393.0)

    func framing(_ control: CameraControl) -> CameraFraming {
        CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height,
            control: control
        )
    }

    /// Every lean worth checking, including the corners of the range.
    var leans: [CameraControl] {
        var controls: [CameraControl] = []
        for vertical in [-20.0, -11, 0, 11, 20] {
            for horizontal in [-20.0, -11, 0, 11, 20] {
                controls.append(CameraControl(leanVertical: vertical, leanHorizontal: horizontal))
            }
        }
        return controls
    }

    /// The four corners of the level's outline, at the height of the wall tops.
    /// This rectangle is the frame that must not move on screen.
    var frameCorners: [WorldPoint] {
        let metrics = level.metrics
        let minX = metrics.meters(fromCells: level.bounds.minX)
        let maxX = metrics.meters(fromCells: level.bounds.maxX)
        let minZ = metrics.meters(fromCells: level.bounds.minY)
        let maxZ = metrics.meters(fromCells: level.bounds.maxY)

        return [
            WorldPoint(x: minX, y: metrics.wallHeight, z: minZ),
            WorldPoint(x: maxX, y: metrics.wallHeight, z: minZ),
            WorldPoint(x: minX, y: metrics.wallHeight, z: maxZ),
            WorldPoint(x: maxX, y: metrics.wallHeight, z: maxZ)
        ]
    }

    // MARK: - The frame is pinned

    @Test("The frame of wall tops does not move on screen at any lean")
    func theFrameIsPinned() throws {
        let atRest = try frameCorners.map {
            try #require(ScreenProjection.screenPoint(
                of: $0, viewportSize: viewport, framing: framing(.neutral)
            ))
        }

        for control in leans {
            let framing = framing(control)
            for (corner, rest) in zip(frameCorners, atRest) {
                let leaned = try #require(ScreenProjection.screenPoint(
                    of: corner, viewportSize: viewport, framing: framing
                ))

                // Not "roughly", and not "the middle of it": every corner of the
                // frame, to the pixel, at every lean. This is the one thing the
                // camera exists to guarantee — the level is a box the player
                // looks into, and the rim of that box is fixed to the display.
                #expect(abs(leaned.x - rest.x) < 0.01, "corner \(corner) moved at \(control)")
                #expect(abs(leaned.y - rest.y) < 0.01, "corner \(corner) moved at \(control)")
            }
        }
    }

    @Test("Nothing outside the building can come into frame")
    func theFrameHoldsTheEdges() throws {
        let metrics = level.metrics
        let minX = metrics.meters(fromCells: level.bounds.minX)
        let maxX = metrics.meters(fromCells: level.bounds.maxX)
        let minZ = metrics.meters(fromCells: level.bounds.minY)
        let maxZ = metrics.meters(fromCells: level.bounds.maxY)

        for control in leans {
            let framing = framing(control)

            for corner in [
                (x: 0.0, y: 0.0),
                (x: viewport.width, y: 0.0),
                (x: 0.0, y: viewport.height),
                (x: viewport.width, y: viewport.height)
            ] {
                let ray = try #require(ScreenProjection.ray(
                    screenPoint: corner, viewportSize: viewport, framing: framing
                ))
                // Where the corner of the display meets the plane of the wall
                // tops. The walls are the outermost thing in the level, so if
                // this lands inside the outline, nothing beyond the building can
                // be on screen — whatever is out there is behind a wall.
                let hit = try #require(ScreenProjection.hit(ray, planeY: metrics.wallHeight))

                let slack = 0.001
                #expect(hit.x >= minX - slack, "\(control) at \(corner)")
                #expect(hit.x <= maxX + slack, "\(control) at \(corner)")
                #expect(hit.z >= minZ - slack, "\(control) at \(corner)")
                #expect(hit.z <= maxZ + slack, "\(control) at \(corner)")
            }
        }
    }

    // MARK: - What does move

    @Test("The floor slides against the frame, by the wall height times the lean")
    func theFloorSlides() throws {
        let metrics = level.metrics
        let centreOfFloor = WorldPoint(x: 12, y: 0, z: 5.5)

        let rest = try #require(ScreenProjection.screenPoint(
            of: centreOfFloor, viewportSize: viewport, framing: framing(.neutral)
        ))

        for degrees in [8.0, 14, 20] {
            let framing = framing(CameraControl(leanVertical: degrees))
            let leaned = try #require(ScreenProjection.screenPoint(
                of: centreOfFloor, viewportSize: viewport, framing: framing
            ))

            // Predicted from the geometry alone: a point `h` below the anchor
            // plane shifts by `h * tan(lean)` in world terms. That is how much
            // of a wall's inside face comes into view.
            let expected = metrics.wallHeight * tan(degrees * .pi / 180)
            let metersPerPoint = (2 * framing.halfHeight * framing.position.y) / viewport.height
            let moved = (leaned.y - rest.y) * metersPerPoint

            #expect(moved > 0, "the floor must follow the finger")
            #expect(abs(moved - expected) < 0.05, "moved \(moved) m, expected \(expected) m")
        }
    }

    @Test("The floor follows the finger in all four directions")
    func theFloorFollowsTheFinger() throws {
        let centreOfFloor = WorldPoint(x: 12, y: 0, z: 5.5)

        func screenPoint(_ control: CameraControl) throws -> (x: Double, y: Double) {
            try #require(ScreenProjection.screenPoint(
                of: centreOfFloor, viewportSize: viewport, framing: framing(control)
            ))
        }

        let rest = try screenPoint(.neutral)
        let down = try screenPoint(CameraControl(leanVertical: 15))
        let up = try screenPoint(CameraControl(leanVertical: -15))
        let right = try screenPoint(CameraControl(leanHorizontal: 15))
        let left = try screenPoint(CameraControl(leanHorizontal: -15))

        #expect(down.y > rest.y)
        #expect(up.y < rest.y)
        #expect(right.x > rest.x)
        #expect(left.x < rest.x)

        // Equal and opposite: looking into a room has to feel the same whichever
        // way it is done.
        #expect(abs((down.y - rest.y) + (up.y - rest.y)) < 0.001)
        #expect(abs((right.x - rest.x) + (left.x - rest.x)) < 0.001)
    }

    @Test("Leaning is clamped to a range that keeps the view a plan view")
    func leanIsClamped() {
        let control = CameraControl().leaned(vertical: 90, horizontal: -90)
        #expect(control.leanVertical == CameraControl.leanRange.upperBound)
        #expect(control.leanHorizontal == CameraControl.leanRange.lowerBound)
    }

    // MARK: - Staying inside the building

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

        // Half the building visible: the centre may stray a quarter of it.
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

    @Test("Zooming in moves the camera closer and shows less")
    func zoomMovesIn() {
        let rest = framing(.neutral)
        let close = framing(CameraControl(zoom: 2))

        #expect(close.position.y < rest.position.y)
        #expect(close.anchorDistance < rest.anchorDistance)
    }

    @Test("Zoom is clamped and leaves the lean alone")
    func zoomIndependentOfLean() {
        let control = CameraControl(leanVertical: 8).zoomed(by: 10)

        #expect(control.zoom == CameraControl.zoomRange.upperBound)
        #expect(control.leanVertical == 8)
    }

    // MARK: - Screen projection round trip

    @Test("A world point projects back to the pixel it came from")
    func projectionRoundTrip() throws {
        for control in [
            CameraControl.neutral,
            CameraControl(leanVertical: 16, leanHorizontal: -14, zoom: 1.8)
        ] {
            let framing = framing(control)
            let screen = (x: 300.0, y: 210.0)

            let ray = try #require(ScreenProjection.ray(
                screenPoint: screen, viewportSize: viewport, framing: framing
            ))
            // The ray is in the leaning scene; the floor it has to meet is the
            // flat one the game is authored in. This is exactly the conversion
            // tap handling does, and getting it wrong is what makes a tap land
            // somewhere other than under the finger.
            let onTheFloor = try #require(ScreenProjection.hit(framing.shear.undo(ray)))
            let back = try #require(ScreenProjection.screenPoint(
                of: onTheFloor, viewportSize: viewport, framing: framing
            ))

            // Taps have to land where the finger is, at any lean.
            #expect(abs(back.x - screen.x) < 0.5)
            #expect(abs(back.y - screen.y) < 0.5)
        }
    }
}
