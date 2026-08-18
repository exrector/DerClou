import Foundation
import OSLog
import RealityKit
import HeistCore

/// The tactical camera: a fixed top-plane anchored off-axis perspective camera.
///
/// This type owns nothing but the RealityKit entity. Every number it uses comes
/// from a `CameraProjection`, which is also what tap resolution and the safe-area
/// solver read — one projection, one set of numbers, no second implementation to
/// drift out of step.
///
/// Uses `ProjectiveTransformCameraComponent` because the off-axis shift is the
/// point of the camera and `PerspectiveCameraComponent` only offers a symmetric
/// frustum. Note that a symmetric one cannot do this job even in principle: an
/// unchanged image of the anchor plane forces the camera to keep looking straight
/// down, and a straight-down symmetric camera images that plane as a plain scale
/// and offset, which cannot stay put while the camera moves.
@MainActor
public final class TacticalCamera {
    private let log = Logger(subsystem: "com.exrector.DerClou", category: "camera")

    /// Extra margin around the level bounds, in meters.
    public var margin: Double

    /// Whether the level is fitted inside the viewport or fills it.
    public var mode: FramingMode

    /// Vertical field of view, in degrees.
    public var fieldOfViewDegrees: Double

    /// Height of the plane held still on screen. Nil means the tops of the
    /// walls, which is the game's camera.
    public var anchorHeight: Double?

    /// The angle the view sits at with no gesture in progress.
    public var restingLean: RestingLean

    public let entity: Entity

    /// The projection currently applied. The single source of truth for anything
    /// that needs to turn between the screen and the world.
    public private(set) var projection: CameraProjection?

    public init(
        margin: Double = 0,
        mode: FramingMode = .fill,
        fieldOfViewDegrees: Double = CameraProjectionSolver.defaultFieldOfViewDegrees,
        anchorHeight: Double? = nil,
        restingLean: RestingLean = .tactical
    ) {
        self.margin = margin
        self.mode = mode
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.anchorHeight = anchorHeight
        self.restingLean = restingLean
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
        entity.components.set(ProjectiveTransformCameraComponent(
            projectionMatrix: matrix_identity_float4x4
        ))
    }

    /// Player peek and zoom.
    public var control: CameraControl = .neutral

    /// Frames the given level for a viewport of `aspectRatio`.
    public func frame(bounds: CellRect, metrics: LevelMetrics, aspectRatio: Double) {
        let projection = CameraProjectionSolver.solve(
            bounds: bounds,
            metrics: metrics,
            aspectRatio: aspectRatio,
            mode: mode,
            fieldOfViewDegrees: fieldOfViewDegrees,
            margin: margin,
            anchorHeight: anchorHeight,
            restingLean: restingLean,
            control: control
        )
        if !projection.showsWholeLevel {
            log.warning("""
                Filling the viewport crops \(projection.croppedWidth, privacy: .public) m of width \
                and \(projection.croppedDepth, privacy: .public) m of depth — \
                this level's shape does not suit the screen
                """)
        }
        apply(projection)
    }

    public func apply(_ projection: CameraProjection) {
        guard projection != self.projection else { return }
        self.projection = projection

        let position = projection.position
        entity.setPosition(
            SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z)),
            relativeTo: nil
        )
        entity.components.set(ProjectiveTransformCameraComponent(
            projectionMatrix: Self.matrix(projection)
        ))

        log.debug("""
            Camera \(position.y, privacy: .public) m up, \
            peek \(projection.peekAcross, privacy: .public)/\(projection.peekUp, privacy: .public)
            """)
    }

    /// The projection's own numbers, in the shape RealityKit wants them.
    ///
    /// The only place `HeistCore`'s plain columns meet a platform graphics type.
    static func matrix(_ projection: CameraProjection) -> simd_float4x4 {
        let columns = projection.matrixColumns
        return simd_float4x4(
            SIMD4<Float>(columns[0].map(Float.init)),
            SIMD4<Float>(columns[1].map(Float.init)),
            SIMD4<Float>(columns[2].map(Float.init)),
            SIMD4<Float>(columns[3].map(Float.init))
        )
    }
}
