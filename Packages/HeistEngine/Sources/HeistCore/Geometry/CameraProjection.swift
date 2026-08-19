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
/// **A true orbit, not a bounded lean.** Two earlier attempts both turned out
/// to be the wrong shape. The first used one polar angle (tilt) and one
/// azimuthal angle (yaw around it) coupled together — at rest a sideways drag
/// did nothing until a vertical drag had tilted the view away from straight
/// down first. The second decoupled them into two independent *lean* axes
/// (rotations around world X and world Z) — that fixed the coupling, but
/// neither axis could sweep past about 70° without the camera reaching the
/// horizon or going underground, because leaning is a rotation around a
/// *horizontal* axis. A full turn around the building — "spin the whole
/// field" — needs a rotation around the *vertical* axis instead: `azimuth`,
/// a compass heading that wraps all the way around with no edge to hit, paired
/// with `elevation`, how far up from looking straight down the camera sits.
/// This is the standard orbit-camera pair (see most 3D viewers' "orbit" tool),
/// and unlike the lean model it never has to stop short of anything.
///
/// **Elevation cannot start at exactly zero.** Looking straight down, every
/// compass heading looks identical — azimuth has no visible effect at the
/// pole, which is exactly the "sideways drag does nothing" bug the coupled
/// model had, just for a different reason (geometry, not a coding mistake:
/// there is no "which way you're facing" when you're staring straight down).
/// `CameraControl.restElevationDegrees` keeps rest a few degrees off the pole
/// so azimuth is always live, from the very first pixel of any drag. At this
/// camera's narrow field of view the offset is visually negligible — see
/// `restParallaxIsSmall` — so the resting view still reads as a plan.
///
/// **The frame's size is fixed at rest, independent of the live orbit.** An
/// earlier version recomputed how much of the level had to fit on screen from
/// the *current* tilt on every touch move, so panning and zooming happened at
/// once — the picture visibly pulsed while the player was only trying to look
/// around. Framing is solved once, for the flat resting view; orbiting only
/// moves the camera around that fixed frame, which is what makes it smooth.
public struct CameraProjection: Sendable, Equatable {
    /// Viewport width divided by height.
    public var aspectRatio: Double
    /// World meters spanned by the height of the screen, at the focus plane.
    /// Fixed for a given framing — orbiting does not change it.
    public var verticalExtent: Double
    /// Point on the floor the camera looks at. Fixed for a given framing.
    public var focus: WorldPoint
    /// Vertical field of view, in degrees. Narrow: this is the whole knob that
    /// trades shadow support against how close to parallel the projection is.
    public var fieldOfViewDegrees: Double

    /// Degrees up from looking straight down — drag up or down. Never
    /// negative: `CameraControl.restElevationDegrees` is as flat as this
    /// model goes, and the far side of a room is reached by turning `azimuth`
    /// around to it, not by tilting past vertical.
    public var elevation: Double
    /// Compass heading in degrees, wrapping — drag left or right. A full turn
    /// brings the view back to exactly where it started; there is no edge to
    /// hit.
    public var azimuth: Double

    /// How much of the level's own width falls outside the view, in meters.
    public var croppedWidth: Double
    /// How much of its depth falls outside, in meters.
    public var croppedDepth: Double

    public init(
        aspectRatio: Double,
        verticalExtent: Double,
        focus: WorldPoint,
        fieldOfViewDegrees: Double,
        elevation: Double = CameraControl.restElevationDegrees,
        azimuth: Double = 0,
        croppedWidth: Double = 0,
        croppedDepth: Double = 0
    ) {
        self.aspectRatio = aspectRatio
        self.verticalExtent = verticalExtent
        self.focus = focus
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.elevation = elevation
        self.azimuth = azimuth
        self.croppedWidth = croppedWidth
        self.croppedDepth = croppedDepth
    }

    /// Half the vertical field of view, as a tangent.
    private var halfFovTangent: Double { tan(fieldOfViewDegrees * .pi / 360) }

    /// How far back the camera stands, so the frustum spans `verticalExtent`
    /// exactly at the focus plane. A pure function of the fixed framing, so it
    /// does not change while the player orbits the view.
    public var distance: Double { (verticalExtent / 2) / halfFovTangent }

    /// Direction from the focus out to the camera, in standard elevation/
    /// azimuth (spherical) form: `elevation` how far up from straight down,
    /// `azimuth` which way that lift faces.
    public var offsetDirection: WorldPoint {
        let elevationRadians = elevation * .pi / 180
        let azimuthRadians = azimuth * .pi / 180
        return WorldPoint(
            x: sin(elevationRadians) * sin(azimuthRadians),
            y: cos(elevationRadians),
            z: sin(elevationRadians) * cos(azimuthRadians)
        )
    }

    /// Where the camera stands.
    public var position: WorldPoint { focus + offsetDirection * distance }

    /// Camera axes: screen right, screen up, and the direction it looks.
    public var basis: (right: WorldPoint, up: WorldPoint, forward: WorldPoint) {
        let forward = offsetDirection * -1
        var right = forward.cross(WorldPoint(x: 0, y: 1, z: 0))
        // Straight down is the degenerate case — elevation at the pole, where
        // azimuth has no axis to turn around. `CameraControl.restElevationDegrees`
        // keeps normal operation off this exact point, but the fallback stays
        // for safety.
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

/// What the player can do to the camera: orbit it, and zoom.
///
/// Orbiting stays where the player leaves it — no spring back, tried and
/// rejected earlier as something that fought the player's hand rather than
/// helping it. `focusButton`-style reset is a deliberate, separate action.
public struct CameraControl: Sendable, Equatable {
    /// Degrees up from looking straight down, from dragging a finger up or
    /// down. Never below `restElevationDegrees`.
    public var elevation: Double
    /// Compass heading in degrees, wrapping, from dragging a finger left or
    /// right. A full turn returns to exactly where it started.
    public var azimuth: Double
    /// Zoom multiplier. 1 frames the whole building; above 1 moves closer.
    public var zoom: Double
    /// Where the view is centred while zoomed in, in meters from the centre.
    public var focusOffset: WorldPoint

    public init(
        elevation: Double = restElevationDegrees,
        azimuth: Double = 0,
        zoom: Double = 1,
        focusOffset: WorldPoint = .zero
    ) {
        self.elevation = elevation
        self.azimuth = Self.wrapped(azimuth)
        self.zoom = zoom
        self.focusOffset = focusOffset
    }

    public static let neutral = CameraControl()

    public var isNeutral: Bool { self == .neutral }

    /// How far off the pole rest sits.
    ///
    /// Looking exactly straight down, azimuth has no axis to turn around —
    /// every heading looks identical, so a horizontal drag would do nothing,
    /// reproducing the exact "sideways drag does nothing at rest" complaint
    /// that a coupled tilt+yaw model had, this time for a real geometric
    /// reason rather than a coding mistake. A few degrees keeps azimuth live
    /// from the first pixel of any drag; at this camera's narrow field of
    /// view that offset is not visible — see `restParallaxIsSmall`.
    public static let restElevationDegrees: Double = 3
    /// How far up from rest the view may go. Stops short of 90°, which would
    /// put the camera on the horizon; the far side of a room is reached by
    /// turning `azimuth`, not by climbing past vertical.
    public static let elevationRange: ClosedRange<Double> = restElevationDegrees...75
    /// Zoom limits. 1 always frames the whole building — there is nothing
    /// beyond that to zoom out to, so the lower bound stays put. The upper
    /// bound is how far the player can push in on one room or object; raised
    /// from an earlier 3 to 6 after the owner found 3 too shallow to actually
    /// close in on something specific.
    public static let zoomRange: ClosedRange<Double> = 1.0...6.0

    private static func wrapped(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    public func oriented(elevation: Double, azimuth: Double) -> CameraControl {
        CameraControl(
            elevation: min(max(elevation, Self.elevationRange.lowerBound), Self.elevationRange.upperBound),
            azimuth: azimuth,
            zoom: zoom,
            focusOffset: focusOffset
        )
    }

    public func zoomed(by factor: Double) -> CameraControl {
        CameraControl(
            elevation: elevation,
            azimuth: azimuth,
            zoom: min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound),
            focusOffset: focusOffset
        )
    }

    public func focused(at offset: WorldPoint) -> CameraControl {
        CameraControl(
            elevation: elevation, azimuth: azimuth, zoom: zoom, focusOffset: offset
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

    /// How much of the level fills the screen at the current zoom, before any
    /// panning is applied. A pure function of level size, viewport, framing
    /// and zoom — not of focus, so it is shared by both clamping and solving
    /// rather than computed twice and risking the two falling out of step.
    private static func frameSize(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode,
        margin: Double,
        zoom: Double
    ) -> (verticalExtent: Double, visibleWidth: Double) {
        let aspect = max(aspectRatio, 0.01)
        let z = max(zoom, 0.01)

        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        let width = levelWidth + margin * 2
        let depth = levelDepth + margin * 2
        let fromWidth = width / aspect

        let extent = switch mode {
        case .fit: max(depth, fromWidth)
        case .fill: min(depth, fromWidth)
        }
        let verticalExtent = extent / z
        return (verticalExtent, verticalExtent * aspect)
    }

    /// Clamps a control to what this level and viewport can actually show.
    ///
    /// Meant to be applied to the camera's *stored* control immediately after
    /// every pan, tilt or zoom — not just to the projection built for display.
    /// Tilt already clamps itself the moment it changes (`tilted(_:_:)`), but
    /// `focusOffset` did not, which let it drift arbitrarily far past the
    /// building's edge while the player kept dragging. The overshoot was
    /// invisible — the rendered frame was clamped — but it had to be dragged
    /// back through before the view moved again, which is what read as the
    /// camera snapping or jerking once it finally caught up. Clamping the
    /// stored value at write time closes that gap: there is nothing left to
    /// unwind.
    public static func clamp(
        _ control: CameraControl,
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fit,
        margin: Double = 0
    ) -> CameraControl {
        let (verticalExtent, visibleWidth) = frameSize(
            bounds: bounds, metrics: metrics, aspectRatio: aspectRatio,
            mode: mode, margin: margin, zoom: control.zoom
        )
        return control.clampedToLevel(
            bounds: bounds, metrics: metrics,
            visibleWidth: visibleWidth, visibleDepth: verticalExtent
        )
    }

    /// - Parameters:
    ///   - bounds: level bounds, in cells.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - mode: whether the level is fitted inside the screen or fills it.
    ///   - fieldOfViewDegrees: vertical field of view.
    ///   - margin: padding around the level, in meters. Enough for the rim of
    ///     ground around the building, and no more.
    ///   - control: the player's tilt, pan and zoom, expected to already be
    ///     clamped (see `clamp(_:bounds:metrics:aspectRatio:mode:margin:)`).
    ///     Clamped again here regardless, so an un-clamped control is still
    ///     safe to pass in — just not idempotent with what gets stored.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fit,
        fieldOfViewDegrees: Double = defaultFieldOfViewDegrees,
        margin: Double = 0,
        control: CameraControl = .neutral
    ) -> CameraProjection {
        // Solved once, flat: the frame the player sees at rest, looking
        // straight down. Tilting orbits the camera around this; it is never
        // recomputed for the live tilt, which is what keeps tilting from also
        // zooming.
        let (verticalExtent, visibleWidth) = frameSize(
            bounds: bounds, metrics: metrics, aspectRatio: aspectRatio,
            mode: mode, margin: margin, zoom: control.zoom
        )
        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)

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
            aspectRatio: max(aspectRatio, 0.01),
            verticalExtent: verticalExtent,
            focus: focus,
            fieldOfViewDegrees: fieldOfViewDegrees,
            elevation: clamped.elevation,
            azimuth: clamped.azimuth,
            croppedWidth: max(0, levelWidth - visibleWidth),
            croppedDepth: max(0, levelDepth - verticalExtent)
        )
    }
}
