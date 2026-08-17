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

    // MARK: - Peek

    @Test("Peeking lowers the camera without turning the map")
    func peekLowersTheCamera() {
        let flat = framing(.neutral)
        let peeked = framing(CameraControl(peekDegrees: 12))

        // Lower camera: less height, more standoff.
        #expect(peeked.position.y < flat.position.y)
        #expect(peeked.position.z > flat.position.z)
        // The map never rotates, so the camera stays on the level's centre line.
        #expect(abs(peeked.position.x - flat.position.x) < 0.001)
    }

    @Test("Peeking is clamped to a small range")
    func peekIsClamped() {
        #expect(CameraControl().peeked(to: 90).peekDegrees == CameraControl.peekRange.upperBound)
        #expect(CameraControl().peeked(to: -30).peekDegrees == 0)
    }

    @Test("Peeking may push the level off screen rather than zooming out")
    func peekMayCrop() {
        let peeked = framing(CameraControl(peekDegrees: 14))

        // Deliberate: a peek is local inspection. Auto-zooming out to keep
        // everything visible would defeat the point of leaning in.
        let flat = framing(.neutral)
        #expect(abs(peeked.verticalExtent - flat.verticalExtent) < 0.001)
    }

    @Test("Zoom is clamped and does not disturb the peek angle")
    func zoomIndependentOfPeek() {
        let control = CameraControl(peekDegrees: 8).zoomed(by: 10)

        #expect(control.zoom == CameraControl.zoomRange.upperBound)
        #expect(control.peekDegrees == 8)
    }

    @Test("Panning is refused at neutral zoom, allowed while peeking")
    func panningRules() {
        let metrics = level.metrics
        let delta = WorldPoint(x: 5, y: 0, z: 0)

        let neutral = CameraControl().panned(by: delta, within: level.bounds, metrics: metrics)
        #expect(neutral.pan == .zero)

        let peeking = CameraControl(peekDegrees: 10)
            .panned(by: delta, within: level.bounds, metrics: metrics)
        #expect(peeking.pan.x > 0)
    }

    @Test("Panning cannot wander off the level when zoomed")
    func panningIsClamped() {
        var control = CameraControl(zoom: 2)
        for _ in 0..<50 {
            control = control.panned(
                by: WorldPoint(x: 10, y: 0, z: 10),
                within: level.bounds,
                metrics: level.metrics
            )
        }

        let halfWidth = level.metrics.meters(fromCells: level.bounds.size.width) / 2
        #expect(control.pan.x <= halfWidth)
    }

    // MARK: - Screen projection round trip

    @Test("A world point projects back to the pixel it came from")
    func projectionRoundTrip() throws {
        for control in [CameraControl.neutral, CameraControl(zoom: 1.8, peekDegrees: 10)] {
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
