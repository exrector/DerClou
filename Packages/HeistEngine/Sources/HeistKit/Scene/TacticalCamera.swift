import Foundation
import OSLog
import RealityKit
import HeistCore

/// The fixed top-down planning camera.
///
/// Orthographic on purpose: with no perspective divergence, a corridor is the
/// same width wherever it sits on screen, so distances read as distances and the
/// scene works as a tactical map while still being real 3D.
@MainActor
public final class TacticalCamera {
    private let log = Logger(subsystem: "com.exrector.DerClou", category: "camera")

    /// Tilt away from straight down, in degrees.
    ///
    /// Zero is a pure plan view and loses all sense of volume; a small tilt
    /// exposes enough of the wall and prop sides to read height without letting
    /// tall geometry hide the floor behind it.
    public var tiltDegrees: Double

    /// Extra margin around the level bounds, in meters.
    public var margin: Double

    /// Whether the level is fitted inside the viewport or fills it.
    public var mode: FramingMode

    /// Perspective by default: orthographic has no parallax, so wall tops and
    /// floor can only move together.
        /// Narrow on purpose — telephoto rather than wide angle.
    ///
    /// A wide field of view turns rooms into perspective funnels. Narrow, with
    /// the camera correspondingly far back, keeps the base view reading as a
    /// tactical board while still giving parallax the moment the view leans.
    public var projection: CameraProjection = .perspective(fieldOfViewDegrees: 26)

    public let entity: Entity

    /// Last framing applied, for debugging and tests.
    public private(set) var framing: CameraFraming?

    public init(tiltDegrees: Double = 24, margin: Double = 0, mode: FramingMode = .fillWidth) {
        self.tiltDegrees = tiltDegrees
        self.margin = margin
        self.mode = mode
        self.entity = Entity()
        entity.name = "camera.tactical"

        applyProjection()
    }

    /// Player pan and zoom. Rotation is deliberately not offered.
    public var control: CameraControl = .neutral

    /// Frames the given level for a viewport of `aspectRatio`.
    public func frame(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        screenInsets: ScreenInsets = .zero,
        viewportSize: (width: Double, height: Double)? = nil
    ) {
        let framing = CameraFramingSolver.solve(
            bounds: bounds,
            metrics: metrics,
            aspectRatio: aspectRatio,
            tiltDegrees: tiltDegrees,
            mode: mode,
            projection: projection,
            margin: margin,
            screenInsets: screenInsets,
            viewportSize: viewportSize,
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

    /// Installs the camera component for the current projection.
    private func applyProjection() {
        switch projection {
        case .orthographic:
            var camera = OrthographicCameraComponent()
            camera.near = 0.05
            camera.far = 400
            camera.scaleDirection = .vertical
            entity.components.set(camera)
        case .perspective(let fieldOfViewDegrees):
            entity.components.remove(OrthographicCameraComponent.self)
            entity.components.set(PerspectiveCameraComponent(
                near: 0.05,
                far: 400,
                fieldOfViewInDegrees: Float(fieldOfViewDegrees)
            ))
        }
    }

    public func apply(_ framing: CameraFraming) {
        guard framing != self.framing else { return }
        self.framing = framing

        if case .orthographic = projection {
            var camera = entity.components[OrthographicCameraComponent.self]
                ?? OrthographicCameraComponent()
            // Measured against the SDK: `scale` is the *half* extent of the view
            // along `scaleDirection`, not the full one.
            camera.scale = Float(framing.verticalExtent / 2)
            camera.scaleDirection = .vertical
            entity.components.set(camera)
        }

        let focus = SIMD3<Float>(
            Float(framing.focus.x),
            Float(framing.focus.y),
            Float(framing.focus.z)
        )
        let position = SIMD3<Float>(
            Float(framing.position.x),
            Float(framing.position.y),
            Float(framing.position.z)
        )
        entity.look(at: focus, from: position, relativeTo: nil)

        log.debug("Framed camera: vertical extent \(framing.verticalExtent, privacy: .public) m")
    }
}
