import Foundation
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
            mode: mode
        )
    }

    @Test("At rest the camera hangs straight above the middle of the level")
    func hangsAboveTheCentre() {
        let framing = framing(aspect: landscapeAspect)

        #expect(framing.anchor.x == 12)
        #expect(framing.anchor.z == 5.5)
        // The anchor is the plane of the wall tops, not the floor.
        #expect(framing.anchor.y == level.metrics.wallHeight)

        // Directly above it, with no shear: at rest this is a plain plan view.
        #expect(abs(framing.position.x - framing.anchor.x) < 1e-9)
        #expect(abs(framing.position.z - framing.anchor.z) < 1e-9)
        #expect(framing.position.y > level.metrics.wallHeight)
        #expect(framing.shear.isFlat)
    }

    @Test("The camera never rotates")
    func neverRotates() {
        for control in [
            CameraControl.neutral,
            CameraControl(leanVertical: 20),
            CameraControl(leanVertical: -14, leanHorizontal: 20, zoom: 2.5)
        ] {
            let framing = CameraFramingSolver.solve(
                bounds: level.bounds,
                metrics: level.metrics,
                aspectRatio: landscapeAspect,
                control: control
            )
            let (right, up, forward) = framing.basis

            // Screen right is world +x and the view is straight down, at every
            // lean and zoom there is. This is what keeps every exterior wall
            // parallel to an edge of the display.
            #expect(right == WorldPoint(x: 1, y: 0, z: 0))
            #expect(up == WorldPoint(x: 0, y: 0, z: -1))
            #expect(forward == WorldPoint(x: 0, y: -1, z: 0))
        }
    }

    @Test("Filling leaves no empty bars on a landscape phone")
    func fillLeavesNoBars() {
        let framing = framing(aspect: landscapeAspect)

        let levelWidth = level.metrics.meters(fromCells: level.bounds.size.width)
        let levelDepth = level.metrics.meters(fromCells: level.bounds.size.depth)

        // What the frustum covers at the anchor plane is the frame that gets
        // pinned to the screen. Filling means that frame is no bigger than the
        // building, or the screen would show ground past its edge.
        let coveredDepth = 2 * framing.halfHeight * framing.anchorDistance
        let coveredWidth = 2 * framing.halfWidth * framing.anchorDistance

        #expect(coveredDepth <= levelDepth + 0.001)
        #expect(coveredWidth <= levelWidth + 0.001)
    }

    @Test("office01 is shaped so that filling costs no playfield")
    func officeSurvivesFill() {
        let framing = framing(aspect: landscapeAspect)

        // This is the reason office01 is 24 x 11 rather than square: a level much
        // squarer than the device forces a choice between empty bars and lost
        // playfield. Losing the outer face of an exterior wall is free — losing
        // more than that is the level shape and the camera disagreeing.
        let free = level.metrics.wallThickness
        #expect(framing.croppedWidth < free, "cropped \(framing.croppedWidth) m of width")
        #expect(framing.croppedDepth < free, "cropped \(framing.croppedDepth) m of depth")
    }

    @Test("Fitting never crops, whatever the aspect ratio")
    func fitNeverCrops() {
        for aspect in [1.0, 1.33, 1.78, 2.17, 2.5] {
            let framing = framing(aspect: aspect, mode: .fit)
            #expect(framing.showsWholeLevel, "aspect \(aspect) cropped \(framing.croppedDepth) m")
        }
    }

    @Test("Fitting a narrow viewport pulls back rather than cropping")
    func portraitFitFallsBack() {
        let portrait = framing(aspect: 0.46, mode: .fit)
        let landscape = framing(aspect: landscapeAspect, mode: .fit)

        // This is the failure mode that made the first build render tiny: the
        // camera was framed with a portrait aspect ratio.
        #expect(portrait.position.y > landscape.position.y * 2.5)
        #expect(portrait.showsWholeLevel)
    }

    @Test("A narrower field of view stands the camera further back")
    func fieldOfViewSetsTheDistance() {
        let wide = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            fieldOfViewDegrees: 50
        )
        let narrow = CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: landscapeAspect,
            fieldOfViewDegrees: 15
        )

        #expect(narrow.position.y > wide.position.y)

        // And both frame the same thing: the field of view is a look, not a
        // change to how much level is on screen.
        #expect(abs(narrow.halfHeight * narrow.anchorDistance
            - wide.halfHeight * wide.anchorDistance) < 0.001)
    }

    @Test("Cropping is reported honestly when a level does not suit the screen")
    func croppingIsReported() {
        // A square level on a wide screen: filling has to cut depth.
        let square = CellRect(x: 0, y: 0, width: 10, depth: 10)
        let framing = CameraFramingSolver.solve(
            bounds: square,
            metrics: .standard,
            aspectRatio: landscapeAspect,
            mode: .fill
        )

        #expect(!framing.showsWholeLevel)
        #expect(framing.croppedDepth > 3)
        #expect(framing.croppedWidth == 0)
    }
}
