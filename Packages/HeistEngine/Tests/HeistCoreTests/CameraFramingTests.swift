import Testing
@testable import HeistCore

@Suite("Camera framing")
struct CameraFramingTests {
    let level = LevelBlueprint.office01

    /// iPhone in landscape, roughly 19.5:9.
    let landscapeAspect = 2.17

    @Test("In landscape the level fills most of the screen height")
    func landscapeFilling() {
        let framing = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 24
        )

        let levelDepth = level.metrics.meters(fromCells: level.bounds.size.depth)
        let fill = levelDepth / framing.verticalExtent

        #expect(fill > 0.7, "Level fills only \(fill * 100)% of the view height")
        #expect(fill < 1.0, "Level must not be cropped")
    }

    @Test("In landscape the whole level width is inside the view")
    func landscapeWidthFits() {
        let framing = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 24
        )

        let horizontalExtent = framing.verticalExtent * landscapeAspect
        let levelWidth = level.metrics.meters(fromCells: level.bounds.size.width)

        #expect(horizontalExtent >= levelWidth)
    }

    @Test("A portrait viewport zooms out instead of cropping")
    func portraitFallsBack() {
        let portrait = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: 0.46,
            tiltDegrees: 24
        )
        let landscape = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 24
        )

        // A narrow viewport has to pull back far more to fit the same width.
        // This is the failure mode that made the first build render tiny: the
        // camera was framed with a portrait aspect ratio.
        #expect(portrait.verticalExtent > landscape.verticalExtent * 2.5)
    }

    @Test("The camera looks at the level centre from above and behind")
    func cameraPlacement() {
        let framing = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 24
        )

        #expect(framing.focus.x == 7)
        #expect(framing.focus.z == 5)
        #expect(framing.position.y > 50)
        #expect(framing.position.z > framing.focus.z)
    }

    @Test("Tilting compresses the ground plane, so it needs slightly less coverage")
    func tiltCompressesGround() {
        let flat = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 0
        )
        let tilted = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 40
        )

        #expect(flat.position.z == flat.focus.z)
        // The ground foreshortens faster than the added wall height compensates,
        // so a tilted view fits the same building in slightly less coverage.
        #expect(tilted.verticalExtent < flat.verticalExtent)
        #expect(tilted.verticalExtent > flat.verticalExtent * 0.8)
    }
}
