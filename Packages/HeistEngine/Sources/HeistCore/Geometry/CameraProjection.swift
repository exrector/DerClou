import Foundation

/// The tactical camera: a tilted orthographic view of the level.
///
/// Settled 2026-08-18, and chosen for what it does *not* do. Parallel projection
/// means lines never converge: a room at the far edge of the screen is drawn at
/// exactly the same scale as one at the near edge, a rectangular building stays
/// a rectangle, and equal distances look equal wherever they are. That is what a
/// planning game needs, and it is what a tilted perspective camera cannot give —
/// that one keystones the level into a trapezium.
///
/// The tilt does the rest: the floor foreshortens, walls and furniture gain
/// height, and both happen together and consistently, so nothing reads as
/// stretched.
///
/// Standard `OrthographicCameraComponent`, standard `look(at:from:)`, and the
/// maths below is the textbook orthographic screen transform. An earlier camera
/// here used a custom off-axis projection matrix to hold the level's outline
/// pinned to the display while the viewpoint shifted. It worked, but it rested
/// on an undocumented depth convention, and it could not show anything at an
/// angle without the oblique distortion that comes of an unforeshortened floor.
/// Standard parts, chosen deliberately — see docs/UI_AND_CAMERA.md.
public struct CameraProjection: Sendable, Equatable {
    /// Viewport width divided by height.
    public var aspectRatio: Double
    /// World meters spanned by the height of the screen.
    public var verticalExtent: Double
    /// Point on the floor the camera looks at.
    public var focus: WorldPoint
    /// How far back the camera stands. Orthographic scale does not depend on it;
    /// it only has to clear the geometry.
    public var distance: Double

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
        distance: Double = 80,
        tiltDegrees: Double,
        yawDegrees: Double = 0,
        croppedWidth: Double = 0,
        croppedDepth: Double = 0
    ) {
        self.aspectRatio = aspectRatio
        self.verticalExtent = verticalExtent
        self.focus = focus
        self.distance = distance
        self.tiltDegrees = tiltDegrees
        self.yawDegrees = yawDegrees
        self.croppedWidth = croppedWidth
        self.croppedDepth = croppedDepth
    }

    private var tilt: Double { tiltDegrees * .pi / 180 }
    private var yaw: Double { yawDegrees * .pi / 180 }

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

    /// Half the screen's height, in meters.
    public var halfHeight: Double { verticalExtent / 2 }
    /// Half its width.
    public var halfWidth: Double { halfHeight * aspectRatio }

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
        guard halfWidth > 0, halfHeight > 0 else { return nil }

        let (right, up, _) = basis
        let offset = world - position

        return (
            x: (offset.dot(right) / halfWidth + 1) / 2 * viewportSize.width,
            y: (1 - offset.dot(up) / halfHeight) / 2 * viewportSize.height
        )
    }

    /// The ray a screen point casts into the world.
    ///
    /// Parallel projection, so rays do not fan out from a focal point: they all
    /// run along the view direction and start offset from the camera.
    public func ray(
        screenPoint: (x: Double, y: Double),
        viewportSize: (width: Double, height: Double)
    ) -> WorldRay? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let ndcX = (screenPoint.x / viewportSize.width) * 2 - 1
        let ndcY = 1 - (screenPoint.y / viewportSize.height) * 2

        let (right, up, forward) = basis
        return WorldRay(
            origin: position + right * (ndcX * halfWidth) + up * (ndcY * halfHeight),
            direction: forward
        )
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

    /// - Parameters:
    ///   - bounds: level bounds, in cells.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - mode: whether the level is fitted inside the screen or fills it.
    ///   - tiltDegrees: resting tilt away from straight down.
    ///   - margin: padding around the level, in meters. Enough for the rim of
    ///     ground around the building, and no more.
    ///   - control: the player's peek and zoom.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fit,
        tiltDegrees: Double = defaultTiltDegrees,
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
            // Kept as short as the geometry allows. Orthographic scale does
            // not depend on the distance, but the shadow cascade is built
            // around the *camera*, so standing needlessly far back puts the
            // level outside its own shadows.
            distance: metrics.wallHeight + 12,
            tiltDegrees: tiltTotal,
            yawDegrees: control.yaw,
            croppedWidth: max(0, levelWidth - visibleWidth),
            croppedDepth: max(0, levelDepth - visibleDepth)
        )
    }
}
