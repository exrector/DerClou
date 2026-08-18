import Foundation
import OSLog
import RealityKit
import HeistCore

/// The tactical camera: a narrow-angle perspective view, built from standard
/// parts.
///
/// `PerspectiveCameraComponent` with a narrow field of view, built from the
/// projection's own axes rather than `look(at:from:)`. Every number comes from
/// a `CameraProjection`, which is also what tap resolution and the safe-area
/// solver read — one projection, one set of numbers, no second implementation
/// to drift out of step.
///
/// Not orthographic. `CameraProjection`'s own documentation has the reason: a
/// true orthographic camera does not receive `DirectionalLightComponent`
/// shadows in this build, confirmed with an isolated scene, and a narrow field
/// of view held far back reads close enough to parallel while shadowing
/// correctly.
@MainActor
public final class TacticalCamera {
    private let log = Logger(subsystem: "com.exrector.DerClou", category: "camera")

    /// Padding around the level, in meters. The building stands in a landscape,
    /// so a little of it belongs in frame.
    public var margin: Double

    /// Whether the level is fitted inside the viewport or fills it.
    public var mode: FramingMode

    /// Vertical field of view, in degrees.
    public var fieldOfViewDegrees: Double

    public let entity: Entity

    /// The projection currently applied. The single source of truth for anything
    /// that turns between the screen and the world.
    public private(set) var projection: CameraProjection?

    public init(
        margin: Double = 1.4,
        mode: FramingMode = .fit,
        fieldOfViewDegrees: Double = CameraProjectionSolver.defaultFieldOfViewDegrees
    ) {
        self.margin = margin
        self.mode = mode
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.entity = Entity()
        entity.name = "camera.tactical"

        var camera = PerspectiveCameraComponent(
            near: 0.05, far: 800, fieldOfViewInDegrees: Float(fieldOfViewDegrees)
        )
        camera.fieldOfViewOrientation = .vertical
        entity.components.set(camera)
    }

    /// Player tilt and zoom.
    public var control: CameraControl = .neutral

    /// Frames the given level for a viewport of `aspectRatio`.
    ///
    /// Clamps `control` itself first, not just the projection built from it —
    /// see `CameraProjectionSolver.clamp` for why that distinction matters.
    public func frame(bounds: CellRect, metrics: LevelMetrics, aspectRatio: Double) {
        control = CameraProjectionSolver.clamp(
            control, bounds: bounds, metrics: metrics, aspectRatio: aspectRatio, mode: mode, margin: margin
        )
        apply(CameraProjectionSolver.solve(
            bounds: bounds,
            metrics: metrics,
            aspectRatio: aspectRatio,
            mode: mode,
            fieldOfViewDegrees: fieldOfViewDegrees,
            margin: margin,
            control: control
        ))
    }

    public func apply(_ projection: CameraProjection) {
        guard projection != self.projection else { return }
        self.projection = projection

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
            \(projection.distance, privacy: .public) m back, \
            lean \(projection.leanVertical, privacy: .public)/\(projection.leanHorizontal, privacy: .public)
            """)
    }
}
