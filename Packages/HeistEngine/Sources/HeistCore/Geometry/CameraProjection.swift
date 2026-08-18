import Foundation

/// The tactical camera: a narrow-angle perspective view of the level, tilted.
///
/// Settled 2026-08-18, revised the same day after a real, verified constraint:
/// RealityKit's directional-light shadows do not render behind an
/// `OrthographicCameraComponent` in this build. Confirmed by an isolated
/// scene — one floor, one block, one light — switched between an orthographic
/// and a perspective camera with every other number held identical. Perspective
/// throws a clean shadow; orthographic throws none, at any shadow distance.
///
/// The fix keeps what orthographic was for — equal distances reading equal, a
/// rectangular building staying a rectangle — without giving up real shadows.
/// A **narrow field of view held far back** is a perspective camera in every
/// way RealityKit is concerned with, so it shadows correctly; and the narrower
/// the angle, the closer its projection sits to a parallel one. `fieldOfView`
/// is chosen tight enough that the keystone it leaves is under the threshold
/// `CameraProjectionTests` checks for — not zero, but not something a player
/// looking at a tactical map notices either.
///
/// Standard `PerspectiveCameraComponent`, built from the projection's own axes.
/// Two earlier cameras are recorded in `docs/UI_AND_CAMERA.md` and not tried
/// again: a custom off-axis projection matrix (worked, but rested on an
/// undocumented depth convention), and a true orthographic camera (worked
/// visually, but cannot be shadowed here).
public struct CameraProjection: Sendable, Equatable {
    /// Viewport width divided by height.
    public var aspectRatio: Double
    /// World meters spanned by the height of the screen, **at the focus
    /// plane**. Perspective, so this is exact there and only approximately true
    /// elsewhere — by design: the field of view is narrow enough that the
    /// approximation holds over a level's depth.
    public var verticalExtent: Double
    /// Point on the floor the camera looks at.
    public var focus: WorldPoint
    /// Vertical field of view, in degrees. Narrow: this is the whole knob that
    /// trades shadow support against how close to parallel the projection is.
    public var fieldOfViewDegrees: Double

    /// Degrees away from straight down. Zero is a plan drawing; the game's view
    /// is well off vertical, so rooms have depth.
    public var tiltDegrees: Double
    /// Degrees the view is turned about the vertical, for the peek. Zero at rest,
    /// and it springs back there.
    public var yawDegrees: Double

    /// How much of the level's own width falls outside the view, in meters.
    public var croppedWidth: Double
    /// How much of its depth falls outside, in meters.
    public var croppedDepth: Double

    public init(
        aspectRatio: Double,
        verticalExtent: Double,
        focus: WorldPoint,
        fieldOfViewDegrees: Double,
        tiltDegrees: Double,
        yawDegrees: Double = 0,
        croppedWidth: Double = 0,
        croppedDepth: Double = 0
    ) {
        self.aspectRatio = aspectRatio
        self.verticalExtent = verticalExtent
        self.focus = focus
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.tiltDegrees = tiltDegrees
        self.yawDegrees = yawDegrees
        self.croppedWidth = croppedWidth
        self.croppedDepth = croppedDepth
    }

    private var tilt: Double { tiltDegrees * .pi / 180 }
    private var yaw: Double { yawDegrees * .pi / 180 }

    /// Half the vertical field of view, as a tangent.
    private var halfFovTangent: Double { tan(fieldOfViewDegrees * .pi / 360) }

    /// How far back the camera stands, so the frustum spans `verticalExtent`
    /// exactly at the focus plane.
    public var distance: Double { (verticalExtent / 2) / halfFovTangent }

    /// Direction from the focus out to the camera.
    public var offsetDirection: WorldPoint {
        WorldPoint(
            x: sin(yaw) * sin(tilt),
            y: cos(tilt),
            z: cos(yaw) * sin(tilt)
        )
    }

    /// Where the camera stands.
    public var position: WorldPoint { focus + offsetDirection * distance }

    /// Camera axes: screen right, screen up, and the direction it looks.
    public var basis: (right: WorldPoint, up: WorldPoint, forward: WorldPoint) {
        let forward = offsetDirection * -1
        var right = forward.cross(WorldPoint(x: 0, y: 1, z: 0))
        // Straight down is the degenerate case, and it is a legal tilt.
        if right.length < 1e-9 {
            right = WorldPoint(x: 1, y: 0, z: 0)
        } else {
            right = right.normalized
        }
        return (right, right.cross(forward), forward)
    }

    /// True when the whole level is on screen.
    public var showsWholeLevel: Bool {
        croppedDepth <= 0.001 && croppedWidth <= 0.001
    }

    // MARK: - Projecting, and going back

    /// Where a world point lands on screen, in points from the top left.
    public func screenPoint(
        of world: WorldPoint,
        viewportSize: (width: Double, height: Double)
    ) -> (x: Double, y: Double)? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let (right, up, forward) = basis
        let offset = world - position
        let depth = offset.dot(forward)
        guard depth > 0.0001 else { return nil }

        let ndcX = offset.dot(right) / (depth * halfFovTangent * aspectRatio)
        let ndcY = offset.dot(up) / (depth * halfFovTangent)

        return (
            x: (ndcX + 1) / 2 * viewportSize.width,
            y: (1 - ndcY) / 2 * viewportSize.height
        )
    }

    /// The ray a screen point casts into the world.
    ///
    /// All rays share the camera's position and fan out by the field of view —
    /// a real perspective camera, not an approximation of one.
    public func ray(
        screenPoint: (x: Double, y: Double),
        viewportSize: (width: Double, height: Double)
    ) -> WorldRay? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let ndcX = (screenPoint.x / viewportSize.width) * 2 - 1
        let ndcY = 1 - (screenPoint.y / viewportSize.height) * 2

        let (right, up, forward) = basis
        let direction = (forward
            + right * (ndcX * halfFovTangent * aspectRatio)
            + up * (ndcY * halfFovTangent)).normalized
        return WorldRay(origin: position, direction: direction)
    }
}

/// How the level is fitted to the viewport.
public enum FramingMode: String, Sendable, Codable, CaseIterable {
    /// Show the whole level, letterboxing whichever axis does not match.
    case fit
    /// Fill the viewport edge to edge, cropping whichever axis overflows.
    case fill
}

/// What the player can do to the camera: peek around it, and zoom.
///
/// Peeking turns and lifts the view a little and then lets go of it — the view
/// springs back to the framing the level was authored for. A look around, not a
/// free camera: the map is a puzzle, and it is only learnable if the player's
/// picture of it survives from one glance to the next.
public struct CameraControl: Sendable, Equatable {
    /// Degrees added to the tilt. Positive lowers the view toward the horizon.
    public var pitch: Double
    /// Degrees the view is turned about the vertical.
    public var yaw: Double
    /// Zoom multiplier. 1 frames the whole building; above 1 moves closer.
    public var zoom: Double
    /// Where the view is centred while zoomed in, in meters from the centre.
    public var focusOffset: WorldPoint

    public init(
        pitch: Double = 0,
        yaw: Double = 0,
        zoom: Double = 1,
        focusOffset: WorldPoint = .zero
    ) {
        self.pitch = pitch
        self.yaw = yaw
        self.zoom = zoom
        self.focusOffset = focusOffset
    }

    public static let neutral = CameraControl()

    public var isNeutral: Bool { self == .neutral }

    /// How far the view may be tilted over. It starts at straight down, so this
    /// only goes one way, and it stays where the player leaves it.
    public static let pitchRange: ClosedRange<Double> = 0...48
    /// How far it may be turned. Deliberately small: past this the player has to
    /// re-learn which way is which.
    public static let yawRange: ClosedRange<Double> = -30...30
    /// Zoom limits.
    public static let zoomRange: ClosedRange<Double> = 1.0...3.0

    public func peeked(pitch: Double, yaw: Double) -> CameraControl {
        CameraControl(
            pitch: min(max(pitch, Self.pitchRange.lowerBound), Self.pitchRange.upperBound),
            yaw: min(max(yaw, Self.yawRange.lowerBound), Self.yawRange.upperBound),
            zoom: zoom,
            focusOffset: focusOffset
        )
    }

    public func zoomed(by factor: Double) -> CameraControl {
        CameraControl(
            pitch: pitch,
            yaw: yaw,
            zoom: min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound),
            focusOffset: focusOffset
        )
    }

    public func focused(at offset: WorldPoint) -> CameraControl {
        CameraControl(pitch: pitch, yaw: yaw, zoom: zoom, focusOffset: offset)
    }

    /// Clamps the centre so the framed rectangle never leaves the building.
    public func clampedToLevel(
        bounds: CellRect,
        metrics: LevelMetrics,
        visibleWidth: Double,
        visibleDepth: Double
    ) -> CameraControl {
        let halfWidth = max(0, metrics.meters(fromCells: bounds.size.width) / 2 - visibleWidth / 2)
        let halfDepth = max(0, metrics.meters(fromCells: bounds.size.depth) / 2 - visibleDepth / 2)

        return focused(at: WorldPoint(
            x: min(max(focusOffset.x, -halfWidth), halfWidth),
            y: 0,
            z: min(max(focusOffset.z, -halfDepth), halfDepth)
        ))
    }
}

/// Builds the camera for a level and a viewport.
public enum CameraProjectionSolver {
    /// The resting tilt, in degrees from straight down.
    ///
    /// Zero, and stated by the owner from the first day: at rest the camera
    /// looks straight down and the level is a plan. Depth is something the
    /// player asks for by dragging, not something the view imposes.
    public static let defaultTiltDegrees = 0.0

    /// Vertical field of view, in degrees.
    ///
    /// Narrow enough that the level's own depth is a small fraction of the
    /// camera's distance, which is what keeps the projection reading as
    /// parallel. See the type's own documentation for why this exists instead
    /// of a true orthographic camera.
    public static let defaultFieldOfViewDegrees = 4.0

    /// - Parameters:
    ///   - bounds: level bounds, in cells.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - mode: whether the level is fitted inside the screen or fills it.
    ///   - tiltDegrees: resting tilt away from straight down.
    ///   - fieldOfViewDegrees: vertical field of view.
    ///   - margin: padding around the level, in meters. Enough for the rim of
    ///     ground around the building, and no more.
    ///   - control: the player's peek and zoom.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fit,
        tiltDegrees: Double = defaultTiltDegrees,
        fieldOfViewDegrees: Double = defaultFieldOfViewDegrees,
        margin: Double = 0,
        control: CameraControl = .neutral
    ) -> CameraProjection {
        let aspect = max(aspectRatio, 0.01)
        let zoom = max(control.zoom, 0.01)

        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        let width = levelWidth + margin * 2
        let depth = levelDepth + margin * 2

        let tiltTotal = tiltDegrees + control.pitch
        let tilt = tiltTotal * .pi / 180

        // Tilting foreshortens the floor and stands the walls up into the frame,
        // so what the screen has to cover vertically is the sum of the two.
        let projectedDepth = depth * cos(tilt) + metrics.wallHeight * sin(tilt)
        let fromWidth = width / aspect

        let extent = switch mode {
        case .fit: max(projectedDepth, fromWidth)
        case .fill: min(projectedDepth, fromWidth)
        }
        let verticalExtent = extent / zoom
        let visibleWidth = verticalExtent * aspect

        // What of the floor lands on screen, once the walls have taken a share.
        let visibleDepth = max(
            0,
            (verticalExtent - metrics.wallHeight * sin(tilt)) / max(cos(tilt), 0.01)
        )

        let clamped = control.clampedToLevel(
            bounds: bounds,
            metrics: metrics,
            visibleWidth: visibleWidth,
            visibleDepth: visibleDepth
        )

        let centre = metrics.worldPoint(bounds.center)
        // Aim a little past the middle, by half of what the walls take: the far
        // wall leans up into frame while the near one simply ends at the floor,
        // so aiming at the floor's centre wastes as much again at the bottom.
        let bias = metrics.wallHeight * sin(tilt) / 2

        return CameraProjection(
            aspectRatio: aspect,
            verticalExtent: verticalExtent,
            focus: WorldPoint(
                x: centre.x + clamped.focusOffset.x,
                y: 0,
                z: centre.z - bias + clamped.focusOffset.z
            ),
            fieldOfViewDegrees: fieldOfViewDegrees,
            tiltDegrees: tiltTotal,
            yawDegrees: control.yaw,
            croppedWidth: max(0, levelWidth - visibleWidth),
            croppedDepth: max(0, levelDepth - visibleDepth)
        )
    }
}
