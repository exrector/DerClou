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
            tiltDegrees: 24,
            mode: .fillWidth,
            margin: 0,
            control: control
        )
    }

    // MARK: - Tactical framing

    @Test("The tactical view fits the floor's width exactly")
    func tacticalFramesTheFloor() {
        let framing = framing(.neutral)
        let horizontalExtent = framing.verticalExtent * (viewport.width / viewport.height)
        let levelWidth = level.metrics.meters(fromCells: level.bounds.size.width)

        #expect(abs(horizontalExtent - levelWidth) < 0.01)
    }

    @Test("Nothing but the floor edges shows: no ground beyond the far wall")
    func noGroundVisible() {
        let framing = framing(.neutral)
        let tilt = 24.0 * .pi / 180

        // Topmost point of the view, expressed as the floor position it lines up
        // with. Beyond the far wall this is not bare ground: the wall's height
        // leans toward the camera and covers a strip of it, reaching as far as
        //
        //     far edge − half thickness − height × tan(tilt)
        //
        // so the frame may reach past the wall's base without showing anything.
        let halfExtent = framing.verticalExtent / 2
        let farthestZ = framing.focus.z - halfExtent / cos(tilt)

        let metrics = level.metrics
        let farEdge = metrics.meters(fromCells: level.bounds.minY)
        let coveredTo = farEdge - metrics.wallThickness / 2 - metrics.wallHeight * tan(tilt)

        #expect(farthestZ >= coveredTo, "view reaches \(farthestZ), wall covers to \(coveredTo)")

        // And the near edge: the frame must not run past the outer face of the
        // near wall onto ground on that side either.
        let nearEdge = metrics.meters(fromCells: level.bounds.maxY)
        let nearestZ = framing.focus.z + halfExtent / cos(tilt)
        #expect(nearestZ <= nearEdge + metrics.wallThickness / 2 + 0.2)
    }

    // MARK: - Leaning

    @Test("Leaning up tips the world so the floor slides up the screen")
    func leanUpTipsTheWorld() {
        let tilt = CameraControl(leanVertical: 12).worldTilt

        // Rotating the level about screen-horizontal lifts its far edge toward
        // the camera, which is what slides the floor up the screen.
        #expect(tilt.aroundX < 0)
        #expect(tilt.aroundZ == 0)
    }

    @Test("Leaning sideways tips the world about the other axis")
    func leanSideTipsTheWorld() {
        let tilt = CameraControl(leanHorizontal: 8).worldTilt

        #expect(tilt.aroundZ > 0)
        #expect(tilt.aroundX == 0)
    }

    @Test("Leaning slides the camera without turning it")
    func cameraSlidesNeverTurns() {
        let flat = framing(.neutral)
        let leaned = framing(CameraControl(leanVertical: 9, leanHorizontal: 9))

        // The camera moves...
        #expect(abs(leaned.position.x - flat.position.x) > 0.5)
        // ...but keeps looking in exactly the same direction. This is what makes
        // the building's walls stay parallel to the display edges; orbiting the
        // camera instead turned the view and read as the map rotating.
        #expect(abs(leaned.viewDirection.x - flat.viewDirection.x) < 1e-9)
        #expect(abs(leaned.viewDirection.y - flat.viewDirection.y) < 1e-9)
        #expect(abs(leaned.viewDirection.z - flat.viewDirection.z) < 1e-9)
    }

    @Test("All four directions give the same amount of parallax")
    func leanIsSymmetric() {
        let flat = framing(.neutral)
        let right = framing(CameraControl(leanHorizontal: 9))
        let left = framing(CameraControl(leanHorizontal: -9))
        let up = framing(CameraControl(leanVertical: 9))
        let down = framing(CameraControl(leanVertical: -9))

        // Equal and opposite sideways, equal and opposite vertically. Earlier
        // versions added the lean to one axis only, so looking behind a wall
        // worked in one direction and not the others.
        #expect(abs((right.position.x - flat.position.x) + (left.position.x - flat.position.x)) < 1e-9)
        #expect(abs((up.position.z - flat.position.z) + (down.position.z - flat.position.z)) < 1e-9)
        #expect(abs(right.position.x - flat.position.x) > 0.5)
        #expect(abs(up.position.z - flat.position.z) > 0.5)
    }

    @Test("The map never turns: screen right stays world +x at any lean")
    func mapDoesNotRotate() {
        for lean in [-8.0, -4, 0, 4, 8] {
            let framing = framing(CameraControl(leanHorizontal: lean))
            let (right, _, _) = framing.basis

            #expect(right.x > 0.999, "lean \(lean) turned the map")
            #expect(abs(right.z) < 0.001, "lean \(lean) turned the map")
        }
    }

    @Test("Leaning is clamped to a small range")
    func leanIsClamped() {
        let control = CameraControl().leaned(vertical: 90, horizontal: -90)
        #expect(control.leanVertical == CameraControl.leanRange.upperBound)
        #expect(control.leanHorizontal == CameraControl.sidewaysLeanRange.lowerBound)
    }

    @Test("Leaning closes in so no empty space appears at the edges")
    func leaningCompensates() {
        let flat = framing(.neutral)
        let leaned = framing(CameraControl(leanVertical: 14, leanHorizontal: 8))

        // Foreshortening would open gaps; the framing pulls in to cover them.
        #expect(leaned.verticalExtent < flat.verticalExtent)
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
            CameraControl(leanVertical: 10, leanHorizontal: -8, zoom: 1.8)
        ] {
            let framing = framing(control)
            let screen = (x: 300.0, y: 210.0)

            let ray = try #require(ScreenProjection.ray(
                screenPoint: screen,
                viewportSize: viewport,
                framing: framing
            ))
            let world = try #require(ScreenProjection.hit(ray))
            let back = try #require(ScreenProjection.screenPoint(
                of: world,
                viewportSize: viewport,
                framing: framing
            ))

            // This is what keeps the anchor under the fingers during a peek.
            #expect(abs(back.x - screen.x) < 0.5)
            #expect(abs(back.y - screen.y) < 0.5)
        }
    }
}
