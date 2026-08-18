import Foundation
import OSLog
import RealityKit
import HeistCore

/// The tactical camera: a tilted orthographic view, built from standard parts.
///
/// `OrthographicCameraComponent` and `look(at:from:)`, nothing else. Every number
/// comes from a `CameraProjection`, which is also what tap resolution and the
/// safe-area solver read — one projection, one set of numbers, no second
/// implementation to drift out of step.
@MainActor
public final class TacticalCamera {
    private let log = Logger(subsystem: "com.exrector.DerClou", category: "camera")

    /// Padding around the level, in meters. The building stands in a landscape,
    /// so a little of it belongs in frame.
    public var margin: Double

    /// Whether the level is fitted inside the viewport or fills it.
    public var mode: FramingMode

    /// Resting tilt away from straight down, in degrees.
    public var tiltDegrees: Double

    public let entity: Entity

    /// The projection currently applied. The single source of truth for anything
    /// that turns between the screen and the world.
    public private(set) var projection: CameraProjection?

    public init(
        margin: Double = 1.4,
        mode: FramingMode = .fit,
        tiltDegrees: Double = CameraProjectionSolver.defaultTiltDegrees
    ) {
        self.margin = margin
        self.mode = mode
        self.tiltDegrees = tiltDegrees
        self.entity = Entity()
        entity.name = "camera.tactical"

        var camera = OrthographicCameraComponent()
        camera.near = 0.05
        camera.far = 600
        camera.scaleDirection = .vertical
        entity.components.set(camera)
    }

    /// Player peek and zoom.
    public var control: CameraControl = .neutral

    /// Frames the given level for a viewport of `aspectRatio`.
    public func frame(bounds: CellRect, metrics: LevelMetrics, aspectRatio: Double) {
        apply(CameraProjectionSolver.solve(
            bounds: bounds,
            metrics: metrics,
            aspectRatio: aspectRatio,
            mode: mode,
            tiltDegrees: tiltDegrees,
            margin: margin,
            control: control
        ))
    }

    public func apply(_ projection: CameraProjection) {
        guard projection != self.projection else { return }
        self.projection = projection

        var camera = entity.components[OrthographicCameraComponent.self]
            ?? OrthographicCameraComponent()
        // Measured against the SDK: `scale` is the *half* extent of the view
        // along `scaleDirection`, not the full one.
        camera.scale = Float(projection.verticalExtent / 2)
        camera.scaleDirection = .vertical
        entity.components.set(camera)

        let position = projection.position
        entity.setPosition(
            SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z)),
            relativeTo: nil
        )

        // Built from the projection's own axes rather than `look(at:from:)`.
        // At rest the camera looks straight down, and that is exactly the case
        // where `look` is degenerate: the world's up is parallel to the view, so
        // the roll is undefined and the level comes out a couple of degrees
        // askew. The basis states the roll instead of leaving it to be guessed.
        let (right, up, forward) = projection.basis
        entity.setOrientation(
            simd_quatf(simd_float3x3(
                SIMD3<Float>(Float(right.x), Float(right.y), Float(right.z)),
                SIMD3<Float>(Float(up.x), Float(up.y), Float(up.z)),
                SIMD3<Float>(Float(-forward.x), Float(-forward.y), Float(-forward.z))
            )),
            relativeTo: nil
        )

        log.debug("""
            Camera: \(projection.verticalExtent, privacy: .public) m across the screen, \
            tilt \(projection.tiltDegrees, privacy: .public), yaw \(projection.yawDegrees, privacy: .public)
            """)
    }
}
