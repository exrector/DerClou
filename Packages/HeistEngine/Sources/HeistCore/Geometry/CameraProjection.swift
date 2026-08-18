import Foundation

/// The tactical camera: a narrow-angle perspective view of the level, freely
/// tilted by the player.
///
/// Settled 2026-08-18, revised twice the same day.
///
/// **Perspective, not orthographic.** `OrthographicCameraComponent` does not
/// receive `DirectionalLightComponent` shadows in this build — confirmed with
/// an isolated scene, one floor, one block, one light, switched between an
/// orthographic and a perspective camera with every other number held
/// identical. Perspective throws a clean shadow; orthographic throws none, at
/// any shadow distance. A **narrow field of view held far back** is a
/// perspective camera in every way RealityKit is concerned with, so it shadows
/// correctly, while reading close enough to parallel that equal distances still
/// look equal and a rectangular building still looks rectangular.
///
/// **A free two-axis tilt, not a spherical orbit.** The first attempt at "let
/// the player look around freely" used one polar angle (tilt) and one
/// azimuthal angle (yaw around it) — spherical coordinates. That has a
/// property that reads as broken: at rest the two axes are not independent, so
/// a sideways drag does nothing until a vertical drag has tilted the view away
/// from straight down first, and tilting only ever went one way, so dragging
/// the "wrong" direction hit a wall immediately. The fix composes two
/// independent rotations, one around world X and one around world Z, applied
/// to the straight-down direction. Both are symmetric, both work from rest,
/// and they do not interact.
///
/// **The frame's size is fixed at rest, independent of the live tilt.** An
/// earlier version recomputed how much of the level had to fit on screen from
/// the *current* tilt on every touch move, so panning and zooming happened at
/// once — the picture visibly pulsed while the player was only trying to look
/// around. Framing is solved once, for the flat resting view; tilting only
/// moves the camera around that fixed frame, which is what makes it smooth.
public struct CameraProjection: Sendable, Equatable {
    /// Viewport width divided by height.
    public var aspectRatio: Double
    /// World meters spanned by the height of the screen, at the focus plane.
    /// Fixed for a given framing — tilting does not change it.
    public var verticalExtent: Double
    /// Point on the floor the camera looks at. Fixed for a given framing.
    public var focus: WorldPoint
    /// Vertical field of view, in degrees. Narrow: this is the whole knob that
    /// trades shadow support against how close to parallel the projection is.
    public var fieldOfViewDegrees: Double

    /// Degrees tilted around world X — drag up or down. Symmetric: positive and
    /// negative reveal opposite sides of a room.
    public var leanVertical: Double
    /// Degrees tilted around world Z — drag left or right. Symmetric and
    /// independent of `leanVertical`.
    public var leanHorizontal: Double

    /// How much of the level's own width falls outside the view, in meters.
    public var croppedWidth: Double
    /// How much of its depth falls outside, in meters.
    public var croppedDepth: Double

    public init(
        aspectRatio: Double,
        verticalExtent: Double,
        focus: WorldPoint,
        fieldOfViewDegrees: Double,
        leanVertical: Double = 0,
        leanHorizontal: Double = 0,
        croppedWidth: Double = 0,
        croppedDepth: Double = 0
    ) {
        self.aspectRatio = aspectRatio
        self.verticalExtent = verticalExtent
        self.focus = focus
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.leanVertical = leanVertical
        self.leanHorizontal = leanHorizontal
        self.croppedWidth = croppedWidth
        self.croppedDepth = croppedDepth
    }

    /// Half the vertical field of view, as a tangent.
    private var halfFovTangent: Double { tan(fieldOfViewDegrees * .pi / 360) }

    /// How far back the camera stands, so the frustum spans `verticalExtent`
    /// exactly at the focus plane. A pure function of the fixed framing, so it
    /// does not change while the player tilts the view.
    public var distance: Double { (verticalExtent / 2) / halfFovTangent }

    /// Direction from the focus out to the camera: two independent rotations of
    /// straight-up, one around world X and one around world Z. Order is fixed
    /// so the same control values always land on the same direction.
    public var offsetDirection: WorldPoint {
        WorldPoint(x: 0, y: 1, z: 0)
            .rotatedAboutX(leanVertical * .pi / 180)
            .rotatedAboutZ(leanHorizontal * .pi / 180)
    }

    /// Where the camera stands.
    public var position: WorldPoint { focus + offsetDirection * distance }

    /// Camera axes: screen right, screen up, and the direction it looks.
    public var basis: (right: WorldPoint, up: WorldPoint, forward: WorldPoint) {
        let forward = offsetDirection * -1
        var right = forward.cross(WorldPoint(x: 0, y: 1, z: 0))
        // Straight down is the degenerate case — both leans at zero — and it
        // is the resting view.
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

/// What the player can do to the camera: tilt it, and zoom.
///
/// Tilting stays where the player leaves it — no spring back, tried and
/// rejected earlier as something that fought the player's hand rather than
/// helping it. `focusButton`-style reset is a deliberate, separate action.
public struct CameraControl: Sendable, Equatable {
    /// Degrees tilted around world X, from dragging a finger up or down.
    public var leanVertical: Double
    /// Degrees tilted around world Z, from dragging a finger left or right.
    public var leanHorizontal: Double
    /// Zoom multiplier. 1 frames the whole building; above 1 moves closer.
    public var zoom: Double
    /// Where the view is centred while zoomed in, in meters from the centre.
    public var focusOffset: WorldPoint

    public init(
        leanVertical: Double = 0,
        leanHorizontal: Double = 0,
        zoom: Double = 1,
        focusOffset: WorldPoint = .zero
    ) {
        self.leanVertical = leanVertical
        self.leanHorizontal = leanHorizontal
        self.zoom = zoom
        self.focusOffset = focusOffset
    }

    public static let neutral = CameraControl()

    public var isNeutral: Bool { self == .neutral }

    /// How far the view may tilt on either axis, in either direction.
    ///
    /// Wide and symmetric on purpose: dragging up and dragging down are meant
    /// to feel like mirror images of each other, not like one direction works
    /// and the other hits a wall. Stops short of 90°, which would put the
    /// camera on the horizon and the level edge-on.
    public static let leanRange: ClosedRange<Double> = -70...70
    /// Zoom limits.
    public static let zoomRange: ClosedRange<Double> = 1.0...3.0

    public func tilted(vertical: Double, horizontal: Double) -> CameraControl {
        CameraControl(
            leanVertical: min(max(vertical, Self.leanRange.lowerBound), Self.leanRange.upperBound),
            leanHorizontal: min(max(horizontal, Self.leanRange.lowerBound), Self.leanRange.upperBound),
            zoom: zoom,
            focusOffset: focusOffset
        )
    }

    public func zoomed(by factor: Double) -> CameraControl {
        CameraControl(
            leanVertical: leanVertical,
            leanHorizontal: leanHorizontal,
            zoom: min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound),
            focusOffset: focusOffset
        )
    }

    public func focused(at offset: WorldPoint) -> CameraControl {
        CameraControl(
            leanVertical: leanVertical, leanHorizontal: leanHorizontal, zoom: zoom, focusOffset: offset
        )
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
    /// Vertical field of view, in degrees.
    ///
    /// Narrow enough that the level's own depth is a small fraction of the
    /// camera's distance, which is what keeps the projection reading as
    /// parallel. See `CameraProjection`'s own documentation for why this
    /// exists instead of a true orthographic camera.
    public static let defaultFieldOfViewDegrees = 4.0

    /// - Parameters:
    ///   - bounds: level bounds, in cells.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - mode: whether the level is fitted inside the screen or fills it.
    ///   - fieldOfViewDegrees: vertical field of view.
    ///   - margin: padding around the level, in meters. Enough for the rim of
    ///     ground around the building, and no more.
    ///   - control: the player's tilt and zoom. Tilt moves the camera around
    ///     the frame solved below; it does not change the frame's size.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fit,
        fieldOfViewDegrees: Double = defaultFieldOfViewDegrees,
        margin: Double = 0,
        control: CameraControl = .neutral
    ) -> CameraProjection {
        let aspect = max(aspectRatio, 0.01)
        let zoom = max(control.zoom, 0.01)

        // Solved once, flat: the frame the player sees at rest, looking
        // straight down. Tilting orbits the camera around this; it is never
        // recomputed for the live tilt, which is what keeps tilting from also
        // zooming.
        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        let width = levelWidth + margin * 2
        let depth = levelDepth + margin * 2
        let fromWidth = width / aspect

        let extent = switch mode {
        case .fit: max(depth, fromWidth)
        case .fill: min(depth, fromWidth)
        }
        let verticalExtent = extent / zoom
        let visibleWidth = verticalExtent * aspect

        let clamped = control.clampedToLevel(
            bounds: bounds,
            metrics: metrics,
            visibleWidth: visibleWidth,
            visibleDepth: verticalExtent
        )

        let centre = metrics.worldPoint(bounds.center)
        let focus = WorldPoint(
            x: centre.x + clamped.focusOffset.x,
            y: 0,
            z: centre.z + clamped.focusOffset.z
        )

        return CameraProjection(
            aspectRatio: aspect,
            verticalExtent: verticalExtent,
            focus: focus,
            fieldOfViewDegrees: fieldOfViewDegrees,
            leanVertical: clamped.leanVertical,
            leanHorizontal: clamped.leanHorizontal,
            croppedWidth: max(0, levelWidth - visibleWidth),
            croppedDepth: max(0, levelDepth - verticalExtent)
        )
    }
}
