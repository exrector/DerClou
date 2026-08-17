import Foundation
import OSLog
import RealityKit
import HeistCore

/// The top-down planning camera.
///
/// Looks straight down, never rotates, and never moves except to zoom. The peek
/// gesture does not touch it at all: leaning is a shear of the scene about the
/// plane of the wall tops, which is what holds the level's frame still on screen
/// — see `CameraFraming` and `ViewShear`.
@MainActor
public final class TacticalCamera {
    private let log = Logger(subsystem: "com.exrector.DerClou", category: "camera")

    /// Extra margin around the level bounds, in meters.
    public var margin: Double

    /// Whether the level is fitted inside the viewport or fills it.
    public var mode: FramingMode

    /// Vertical field of view, in degrees.
    public var fieldOfViewDegrees: Double

    public let entity: Entity

    /// Last framing applied, for debugging and tests.
    public private(set) var framing: CameraFraming?

    public init(
        margin: Double = 0,
        mode: FramingMode = .fill,
        fieldOfViewDegrees: Double = CameraFramingSolver.defaultFieldOfViewDegrees
    ) {
        self.margin = margin
        self.mode = mode
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.entity = Entity()
        entity.name = "camera.tactical"

        // Set once and never touched again: screen right is world +x, screen up
        // is world -z, and the camera looks down its own -z at the floor.
        entity.setOrientation(
            simd_quatf(simd_float3x3(
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 0, -1),
                SIMD3<Float>(0, 1, 0)
            )),
            relativeTo: nil
        )

        // Present from the start: RealityView looks for a camera when the scene
        // is first made, and an entity that gains one later is not picked up.
        var camera = PerspectiveCameraComponent(
            near: 0.05,
            far: 400,
            fieldOfViewInDegrees: Float(fieldOfViewDegrees)
        )
        // Stated rather than assumed: the framing solves for the height of the
        // screen, so the field of view has to be the vertical one.
        camera.fieldOfViewOrientation = .vertical
        entity.components.set(camera)
    }

    /// Player lean and zoom.
    public var control: CameraControl = .neutral

    /// Frames the given level for a viewport of `aspectRatio`.
    public func frame(bounds: CellRect, metrics: LevelMetrics, aspectRatio: Double) {
        let framing = CameraFramingSolver.solve(
            bounds: bounds,
            metrics: metrics,
            aspectRatio: aspectRatio,
            mode: mode,
            fieldOfViewDegrees: fieldOfViewDegrees,
            margin: margin,
            control: control
        )
        if !framing.showsWholeLevel {
            log.warning("""
                Filling the viewport crops \(framing.croppedWidth, privacy: .public) m of width \
                and \(framing.croppedDepth, privacy: .public) m of depth — \
                this level's shape does not suit the screen
                """)
        }
        apply(framing)
    }

    public func apply(_ framing: CameraFraming) {
        guard framing != self.framing else { return }
        self.framing = framing

        entity.setPosition(
            SIMD3<Float>(
                Float(framing.position.x),
                Float(framing.position.y),
                Float(framing.position.z)
            ),
            relativeTo: nil
        )

        log.debug("""
            Framed camera: \(framing.position.y, privacy: .public) m up, \
            lean \(framing.shear.acrossX, privacy: .public)/\(framing.shear.acrossZ, privacy: .public)
            """)
    }
}
