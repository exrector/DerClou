import Testing
@testable import HeistCore

@Suite("Camera framing")
struct CameraFramingTests {
    let level = LevelBlueprint.office01

    /// iPhone in landscape, roughly 19.5:9.
    let landscapeAspect = 2.17

    func framing(aspect: Double, mode: FramingMode = .fill) -> CameraFraming {
        CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: aspect,
            tiltDegrees: 24,
            mode: mode
        )
    }

    @Test("Filling leaves no empty bars on a landscape phone")
    func fillLeavesNoBars() {
        let framing = framing(aspect: landscapeAspect)

        let horizontalExtent = framing.verticalExtent * landscapeAspect
        let levelWidth = level.metrics.meters(fromCells: level.bounds.size.width)
        let levelDepth = level.metrics.meters(fromCells: level.bounds.size.depth)

        // One axis must be tight against the level, otherwise we are letterboxing.
        let widthSlack = horizontalExtent - levelWidth
        let depthSlack = framing.verticalExtent - levelDepth
        #expect(min(widthSlack, depthSlack) < 2.5, "width slack \(widthSlack), depth slack \(depthSlack)")
    }

    @Test("office01 is shaped so that filling crops nothing on a landscape phone")
    func officeSurvivesFill() {
        let framing = framing(aspect: landscapeAspect)

        // This is the reason office01 is 24 x 10 rather than square: a level much
        // squarer than the device forces a choice between empty bars and lost
        // playfield. If this fails, the level shape and the camera disagree.
        #expect(framing.showsWholeLevel, """
            cropped \(framing.croppedDepth) m of depth and \(framing.croppedWidth) m of width
            """)
    }

    @Test("Fitting never crops, whatever the aspect ratio")
    func fitNeverCrops() {
        for aspect in [1.0, 1.33, 1.78, 2.17, 2.5] {
            let framing = framing(aspect: aspect, mode: .fit)
            #expect(framing.showsWholeLevel, "aspect \(aspect) cropped \(framing.croppedDepth) m")
        }
    }

    @Test("Fitting a narrow viewport zooms out rather than cropping")
    func portraitFitFallsBack() {
        let portrait = framing(aspect: 0.46, mode: .fit)
        let landscape = framing(aspect: landscapeAspect, mode: .fit)

        // This is the failure mode that made the first build render tiny: the
        // camera was framed with a portrait aspect ratio.
        #expect(portrait.verticalExtent > landscape.verticalExtent * 2.5)
        #expect(portrait.showsWholeLevel)
    }

    @Test("The camera looks at the level centre from above and behind")
    func cameraPlacement() {
        let framing = framing(aspect: landscapeAspect)

        #expect(framing.focus.x == 12)
        #expect(framing.focus.z == 5.5)
        #expect(framing.position.y > 50)
        #expect(framing.position.z > framing.focus.z)
    }

    @Test("Tilting compresses the ground plane, so it needs slightly less coverage")
    func tiltCompressesGround() {
        let flat = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 0,
            mode: .fit
        )
        let tilted = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            tiltDegrees: 40,
            mode: .fit
        )

        #expect(flat.position.z == flat.focus.z)
        #expect(tilted.verticalExtent < flat.verticalExtent)
        #expect(tilted.verticalExtent > flat.verticalExtent * 0.8)
    }

    @Test("Cropping is reported honestly when a level does not suit the screen")
    func croppingIsReported() {
        // A square level on a wide screen: filling has to cut depth.
        let square = CellRect(x: 0, y: 0, width: 10, depth: 10)
        let framing = CameraFramingSolver.solve(
            bounds: square,
            metrics: .standard,
            aspectRatio: landscapeAspect,
            tiltDegrees: 24,
            mode: .fill
        )

        #expect(!framing.showsWholeLevel)
        #expect(framing.croppedDepth > 3)
        #expect(framing.croppedWidth == 0)
    }
}
