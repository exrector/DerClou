import Foundation
import Testing
@testable import HeistCore

/// The contract of the tactical camera, tested where it is actually defined:
/// on the projection of world points, not on rendered pixels.
///
/// A screenshot comparison would also pass today and would also be a reasonable
/// integration check, but it is not the contract — Apple can change
/// anti-aliasing or rasterisation without changing the camera maths, and a test
/// that fails for that reason teaches nothing. The debug scene in `CameraLab`
/// covers the rendered side by eye.
@Suite("Camera projection")
struct CameraProjectionTests {
    let level = LevelBlueprint.office01
    /// iPhone 16 in landscape.
    let viewport = (width: 852.0, height: 393.0)

    func projection(_ control: CameraControl) -> CameraProjection {
        CameraProjectionSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height,
            control: control
        )
    }

    /// Peeks worth checking, including the corners of the range.
    var peeks: [CameraControl] {
        var controls: [CameraControl] = []
        for vertical in [-20.0, -11, 0, 11, 20] {
            for horizontal in [-20.0, -11, 0, 11, 20] {
                controls.append(CameraControl(leanVertical: vertical, leanHorizontal: horizontal))
            }
        }
        return controls
    }

    /// The four corners of the level's outline at the height of the wall tops:
    /// the frame that must not move.
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

    // MARK: - The frame holds, the floor does not

    @Test("A wall top and the floor beneath it: one is fixed, the other is not")
    func theFrameHoldsAndTheFloorMoves() throws {
        // The pair the whole camera is about, checked at one corner of the frame.
        let onTheWall = try #require(frameCorners.first)
        let onTheFloor = WorldPoint(x: onTheWall.x, y: 0, z: onTheWall.z)

        func screen(_ point: WorldPoint, _ control: CameraControl) throws -> (x: Double, y: Double) {
            try #require(projection(control).screenPoint(of: point, viewportSize: viewport))
        }

        let restWall = try screen(onTheWall, .neutral)
        let restFloor = try screen(onTheFloor, .neutral)

        for peek in [
            CameraControl(leanHorizontal: 20),
            CameraControl(leanHorizontal: -20),
            CameraControl(leanVertical: 20),
            CameraControl(leanVertical: -20)
        ] {
            let wall = try screen(onTheWall, peek)
            let floor = try screen(onTheFloor, peek)

            #expect(abs(wall.x - restWall.x) < 0.001, "wall top moved sideways at \(peek)")
            #expect(abs(wall.y - restWall.y) < 0.001, "wall top moved vertically at \(peek)")

            let travelled = ((floor.x - restFloor.x) * (floor.x - restFloor.x)
                + (floor.y - restFloor.y) * (floor.y - restFloor.y)).squareRoot()
            #expect(travelled > 20, "the floor barely moved at \(peek): \(travelled) points")
        }
    }

    @Test("Every corner of the frame holds, at every peek")
    func theWholeFrameIsPinned() throws {
        let atRest = try frameCorners.map {
            try #require(projection(.neutral).screenPoint(of: $0, viewportSize: viewport))
        }

        for control in peeks {
            let projection = projection(control)
            for (corner, rest) in zip(frameCorners, atRest) {
                let moved = try #require(projection.screenPoint(of: corner, viewportSize: viewport))

                // Not "roughly", and not "the middle of it": every corner, at
                // every peek. The level is a box the player looks into, and the
                // rim of that box is fixed to the display.
                #expect(abs(moved.x - rest.x) < 0.001, "corner \(corner) moved at \(control)")
                #expect(abs(moved.y - rest.y) < 0.001, "corner \(corner) moved at \(control)")
            }
        }
    }

    @Test("The floor slides by the anchor height times the tangent of the peek")
    func theFloorSlidesByThePredictedAmount() throws {
        let metrics = level.metrics
        let centreOfFloor = WorldPoint(x: 12, y: 0, z: 5.5)

        let rest = try #require(
            projection(.neutral).screenPoint(of: centreOfFloor, viewportSize: viewport)
        )

        for degrees in [8.0, 14, 20] {
            let projection = projection(CameraControl(leanVertical: degrees))
            let moved = try #require(
                projection.screenPoint(of: centreOfFloor, viewportSize: viewport)
            )

            // Predicted from the geometry alone, with nothing measured: a point
            // `h` below the anchor plane shifts by `h * tan(peek)`.
            let expected = metrics.wallHeight * tan(degrees * .pi / 180)
            let metresPerPoint = projection.verticalExtent / viewport.height
            let travelled = (moved.y - rest.y) * metresPerPoint

            #expect(travelled > 0, "the floor must follow the finger")
            #expect(abs(travelled - expected) < 0.02, "moved \(travelled) m, expected \(expected) m")
        }
    }

    @Test("The floor follows the finger in all four directions, symmetrically")
    func theFloorFollowsTheFinger() throws {
        let centreOfFloor = WorldPoint(x: 12, y: 0, z: 5.5)

        func screen(_ control: CameraControl) throws -> (x: Double, y: Double) {
            try #require(projection(control).screenPoint(of: centreOfFloor, viewportSize: viewport))
        }

        let rest = try screen(.neutral)
        let down = try screen(CameraControl(leanVertical: 15))
        let up = try screen(CameraControl(leanVertical: -15))
        let right = try screen(CameraControl(leanHorizontal: 15))
        let left = try screen(CameraControl(leanHorizontal: -15))

        #expect(down.y > rest.y)
        #expect(up.y < rest.y)
        #expect(right.x > rest.x)
        #expect(left.x < rest.x)

        #expect(abs((down.y - rest.y) + (up.y - rest.y)) < 0.001)
        #expect(abs((right.x - rest.x) + (left.x - rest.x)) < 0.001)
    }

    // MARK: - The matrix agrees with the projection

    @Test("At rest the matrix is an ordinary symmetric frustum")
    func restingMatrixIsSymmetric() {
        let columns = projection(.neutral).matrixColumns

        // The off-axis terms are the only difference from a standard camera, so
        // at rest they must be exactly zero.
        #expect(columns[2][0] == 0)
        #expect(columns[2][1] == 0)

        // And the rest is the textbook reverse-depth perspective matrix, built
        // here independently of the implementation.
        let projection = projection(.neutral)
        let halfHeight = tan(projection.fieldOfViewDegrees * .pi / 360)
        let near = projection.near, far = projection.far

        #expect(abs(columns[0][0] - 1 / (halfHeight * projection.aspectRatio)) < 1e-12)
        #expect(abs(columns[1][1] - 1 / halfHeight) < 1e-12)
        #expect(abs(columns[2][2] - near / (far - near)) < 1e-12)
        #expect(columns[2][3] == -1)
        #expect(abs(columns[3][2] - far * near / (far - near)) < 1e-12)
    }

    @Test("The matrix puts world points where the projection says they go")
    func matrixAgreesWithScreenPoint() throws {
        // Two implementations of one projection would drift, and the symptom
        // would be taps landing away from the finger. This is the test that
        // catches that: the matrix the renderer uses, applied by hand, has to
        // agree with the maths tap handling uses.
        for control in [
            CameraControl.neutral,
            CameraControl(leanVertical: 17, leanHorizontal: -13),
            CameraControl(leanVertical: -20, leanHorizontal: 20, zoom: 2)
        ] {
            let projection = projection(control)
            let columns = projection.matrixColumns
            let camera = projection.position

            for world in frameCorners + [WorldPoint(x: 4, y: 0, z: 2), WorldPoint(x: 19, y: 1.1, z: 8)] {
                // Camera space: right is +x, up is -z, and the camera looks down
                // its own -z.
                let view = [
                    world.x - camera.x,
                    -(world.z - camera.z),
                    -(camera.y - world.y),
                    1.0
                ]
                var clip = [0.0, 0.0, 0.0, 0.0]
                for row in 0..<4 {
                    for column in 0..<4 {
                        clip[row] += columns[column][row] * view[column]
                    }
                }
                guard clip[3] > 0.0001 else { continue }

                let expected = try #require(
                    projection.screenPoint(of: world, viewportSize: viewport)
                )
                let byMatrix = (
                    x: (clip[0] / clip[3] + 1) / 2 * viewport.width,
                    y: (1 - clip[1] / clip[3]) / 2 * viewport.height
                )

                #expect(abs(byMatrix.x - expected.x) < 0.001, "at \(control), point \(world)")
                #expect(abs(byMatrix.y - expected.y) < 0.001, "at \(control), point \(world)")
            }
        }
    }

    @Test("A tap projects back to the pixel it came from")
    func projectionRoundTrip() throws {
        for control in [
            CameraControl.neutral,
            CameraControl(leanVertical: 16, leanHorizontal: -14, zoom: 1.8)
        ] {
            let projection = projection(control)
            let screen = (x: 300.0, y: 210.0)

            let ray = try #require(projection.ray(screenPoint: screen, viewportSize: viewport))
            let onTheFloor = try #require(ray.hit())
            let back = try #require(
                projection.screenPoint(of: onTheFloor, viewportSize: viewport)
            )

            #expect(abs(back.x - screen.x) < 0.5)
            #expect(abs(back.y - screen.y) < 0.5)
        }
    }

    // MARK: - Framing

    @Test("At rest the camera hangs straight above the middle of the level")
    func hangsAboveTheCentre() {
        let projection = projection(.neutral)

        #expect(projection.anchor.centre.x == 12)
        #expect(projection.anchor.centre.z == 5.5)
        #expect(projection.anchor.height == level.metrics.wallHeight)

        #expect(abs(projection.position.x - projection.anchor.centre.x) < 1e-12)
        #expect(abs(projection.position.z - projection.anchor.centre.z) < 1e-12)
        #expect(projection.position.y > level.metrics.wallHeight)
    }

    @Test("The camera never rotates")
    func neverRotates() {
        for control in peeks {
            let (right, up, forward) = projection(control).basis
            #expect(right == WorldPoint(x: 1, y: 0, z: 0))
            #expect(up == WorldPoint(x: 0, y: 0, z: -1))
            #expect(forward == WorldPoint(x: 0, y: -1, z: 0))
        }
    }

    @Test("Nothing outside the building can come into frame")
    func nothingOutsideShows() throws {
        let metrics = level.metrics
        let minX = metrics.meters(fromCells: level.bounds.minX)
        let maxX = metrics.meters(fromCells: level.bounds.maxX)
        let minZ = metrics.meters(fromCells: level.bounds.minY)
        let maxZ = metrics.meters(fromCells: level.bounds.maxY)

        for control in peeks {
            let projection = projection(control)

            for corner in [
                (x: 0.0, y: 0.0),
                (x: viewport.width, y: 0.0),
                (x: 0.0, y: viewport.height),
                (x: viewport.width, y: viewport.height)
            ] {
                let ray = try #require(
                    projection.ray(screenPoint: corner, viewportSize: viewport)
                )
                // Where the corner of the display meets the anchor plane. The
                // walls are the outermost thing in the level, so if this lands
                // inside the outline, anything beyond the building is either
                // behind a wall or off screen.
                let hit = try #require(ray.hit(planeY: metrics.wallHeight))

                #expect(hit.x >= minX - 0.001, "\(control) at \(corner)")
                #expect(hit.x <= maxX + 0.001, "\(control) at \(corner)")
                #expect(hit.z >= minZ - 0.001, "\(control) at \(corner)")
                #expect(hit.z <= maxZ + 0.001, "\(control) at \(corner)")
            }
        }
    }

    @Test("office01 is shaped so that filling costs no playfield")
    func officeSurvivesFill() {
        let projection = projection(.neutral)

        // Losing the outer face of an exterior wall is free; losing more than
        // that is the level shape and the camera disagreeing.
        let free = level.metrics.wallThickness
        #expect(projection.croppedWidth < free, "cropped \(projection.croppedWidth) m of width")
        #expect(projection.croppedDepth < free, "cropped \(projection.croppedDepth) m of depth")
    }

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

    @Test("Zooming in moves the camera closer and shows less")
    func zoomMovesIn() {
        let rest = projection(.neutral)
        let close = projection(CameraControl(zoom: 2))

        #expect(close.position.y < rest.position.y)
        #expect(close.anchorDistance < rest.anchorDistance)
    }

    @Test("Peek and zoom are clamped and independent")
    func controlsAreClamped() {
        let peeked = CameraControl().leaned(vertical: 90, horizontal: -90)
        #expect(peeked.leanVertical == CameraControl.leanRange.upperBound)
        #expect(peeked.leanHorizontal == CameraControl.leanRange.lowerBound)

        let zoomed = CameraControl(leanVertical: 8).zoomed(by: 10)
        #expect(zoomed.zoom == CameraControl.zoomRange.upperBound)
        #expect(zoomed.leanVertical == 8)
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
}
