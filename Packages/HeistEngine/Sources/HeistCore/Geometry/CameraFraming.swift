import Foundation

/// How the tactical camera projects the world.
///
/// **Orthographic is the game's visual language and is not negotiable.** A true
/// orthographic camera needs iOS 18, which is why iOS 18 is the deployment floor.
///
/// The perspective case exists because a very narrow field of view pulled far
/// back approximates orthographic and reaches back to iOS 13. It is kept as a
/// deliberate escape hatch, not as the default: at any usable field of view the
/// verticals still converge, and a tactical plan view is exactly the situation
/// where that reads as wrong.
public enum CameraProjection: Sendable, Equatable {
    case orthographic
    /// Vertical field of view, in degrees. Small values approach orthographic.
    case perspective(fieldOfViewDegrees: Double)
}

/// How much world space a tactical camera must cover.
public struct CameraFraming: Sendable, Equatable {
    /// Vertical extent of the orthographic view, in meters.
    public var verticalExtent: Double
    /// World-space point the camera looks at.
    public var focus: WorldPoint
    /// Camera position, in meters.
    public var position: WorldPoint
    /// How much of the level's own depth falls outside the view, in meters.
    /// Zero means nothing is cropped. Only `.fill` can produce a positive value.
    public var croppedDepth: Double
    /// How much of the level's own width falls outside the view, in meters.
    public var croppedWidth: Double
    /// Projection the framing was solved for.
    public var projection: CameraProjection

    public init(
        verticalExtent: Double,
        focus: WorldPoint,
        position: WorldPoint,
        croppedDepth: Double = 0,
        croppedWidth: Double = 0,
        projection: CameraProjection = .orthographic
    ) {
        self.verticalExtent = verticalExtent
        self.focus = focus
        self.position = position
        self.croppedDepth = croppedDepth
        self.croppedWidth = croppedWidth
        self.projection = projection
    }

    /// Straight-line distance from the camera to its focus, in meters.
    public var distanceToFocus: Double {
        let dx = position.x - focus.x
        let dy = position.y - focus.y
        let dz = position.z - focus.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Camera basis: screen right, screen up, and the view direction.
    ///
    /// Derived rather than assumed, because the camera can now swing sideways as
    /// well as tilt. The world's up is used as the reference, which is what keeps
    /// the map from rotating on screen when the view leans.
    public var basis: (right: WorldPoint, up: WorldPoint, forward: WorldPoint) {
        let forward = (focus - position).normalized
        let worldUp = WorldPoint(x: 0, y: 1, z: 0)
        var right = forward.cross(worldUp).normalized
        if right.planarLength < 1e-6 && abs(right.y) < 1e-6 {
            right = WorldPoint(x: 1, y: 0, z: 0)
        }
        return (right, right.cross(forward), forward)
    }

    /// True when the whole level is on screen.
    public var showsWholeLevel: Bool {
        croppedDepth <= 0.001 && croppedWidth <= 0.001
    }
}

/// How the level is fitted to the viewport.
public enum FramingMode: String, Sendable, Codable, CaseIterable {
    /// Show the whole level, letterboxing whichever axis does not match the
    /// viewport. Nothing is ever cropped.
    case fit
    /// Fill the viewport edge to edge, cropping whichever axis overflows.
    ///
    /// This is the default: empty bars around a tactical map waste the screen.
    /// It is safe only when levels are authored roughly to the device's aspect
    /// ratio — otherwise it eats real playfield. `CameraFraming.croppedDepth`
    /// reports how much is being lost so a level can be checked in a test.
    case fill
    /// Fit the floor's width exactly to the display width.
    ///
    /// The default for gameplay. The floor spans the screen edge to edge, so the
    /// left, right and far walls fall outside the frame entirely — the player
    /// sees the room, not the box containing it. Only the near wall stays in
    /// shot, where the camera tilt reveals its thickness and gives the scene
    /// depth.
    case fillWidth
}

/// Player-controlled camera offset: pan across the floor and zoom in or out.
///
/// Rotation and tilt are deliberately absent. The map is a puzzle: walls must
/// read the same way every time, vision cones must be comparable at a glance,
/// screen directions must stay put so tap-to-move never fights the view, and a
/// level designer has to know what the player will see. The original game let
/// the camera swing freely; that freedom costs more than it gives here.
/// What the player can do to the camera: lean the view and zoom in.
///
/// Leaning is expressed as two angles away from straight down — one toward the
/// screen's vertical axis, one toward its horizontal axis. Dragging a finger up
/// slides the floor up and shows the depth of the far side of the room; dragging
/// right slides it right and shows the depth of the left side. The map itself
/// never turns: north stays at the top of the screen.
///
/// There is no free panning. The building is meant to stay pinned to the display
/// edges, so what moves is the angle you look from, not the piece of the world
/// you look at.
public struct CameraControl: Sendable, Equatable {
    /// Positive slides the floor **up** the screen, showing the depth of the far
    /// side of the room.
    public var leanVertical: Double
    /// Positive slides the floor **right**, showing the depth of the left side.
    public var leanHorizontal: Double
    /// Zoom multiplier. 1 frames the whole building; above 1 moves closer.
    public var zoom: Double
    /// Where the view is centred while zoomed in, in meters from the building's
    /// centre. Only meaningful above zoom 1, and always clamped so the frame
    /// stays inside the building.
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

    /// How far the view may lean.
    ///
    /// Deliberately tiny. The point is a glance into a room, not a change of
    /// viewpoint: the building must never look like it is being turned around,
    /// and the plan must stay readable throughout.
    public static let leanRange: ClosedRange<Double> = -7...7

    /// Sideways is held tighter still, since swinging around the building is
    /// what reads as the map turning.
    public static let sidewaysLeanRange: ClosedRange<Double> = -5...5

    /// Zoom limits.
    public static let zoomRange: ClosedRange<Double> = 1.0...3.0

    public func leaned(vertical: Double, horizontal: Double) -> CameraControl {
        CameraControl(
            leanVertical: min(max(vertical, Self.leanRange.lowerBound), Self.leanRange.upperBound),
            leanHorizontal: min(
                max(horizontal, Self.sidewaysLeanRange.lowerBound),
                Self.sidewaysLeanRange.upperBound
            ),
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
            leanVertical: leanVertical,
            leanHorizontal: leanHorizontal,
            zoom: zoom,
            focusOffset: offset
        )
    }

    /// How much the world is rotated to lean the view, in radians.
    ///
    /// Applied to the level rather than to the camera. The camera stays exactly
    /// where the tactical framing puts it, so the building keeps filling the
    /// display and the map never appears to turn — the floor simply tips toward
    /// the finger, revealing the depth of the far side of a room.
    public var worldTilt: (aroundX: Double, aroundZ: Double) {
        (aroundX: -leanVertical * .pi / 180, aroundZ: leanHorizontal * .pi / 180)
    }

    /// Zoom factor that keeps a leaned building covering the frame.
    ///
    /// Foreshortening alone (`cos`) is nowhere near enough: tipping the level
    /// also swings its far corners across the frame, which opens a wedge of
    /// empty space at one edge. Measured on device, a 14°/8° lean left about a
    /// tenth of the display bare, so the closing-in is linear in the total lean
    /// and tuned to cover it.
    public var leanCompensation: Double {
        let total = abs(leanVertical) + abs(leanHorizontal)
        return max(1 - total / 170, 0.5)
    }

    /// Clamps the centre so the visible rectangle never leaves the floor.
    ///
    /// This is what stops a zoomed or leaned view from showing anything that is
    /// not the building.
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

/// Computes tactical camera framing.
///
/// Pure maths, kept out of the view layer so the "does the level actually fill
/// the screen" question is answered by a unit test rather than by squinting at
/// a screenshot.
public enum CameraFramingSolver {
    /// - Parameters:
    ///   - bounds: level bounds, in cells.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - tiltDegrees: tilt away from straight down.
    ///   - margin: padding around the level, in meters.
    ///   - distance: camera pull-back. Irrelevant to scale under orthographic
    ///     projection; only has to clear the geometry and stay within near/far.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        tiltDegrees: Double,
        mode: FramingMode = .fill,
        projection: CameraProjection = .orthographic,
        margin: Double = 1.0,
        screenInsets: ScreenInsets = .zero,
        viewportSize: (width: Double, height: Double)? = nil,
        control: CameraControl = .neutral
    ) -> CameraFraming {
        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        var width = levelWidth + margin * 2
        var depth = levelDepth + margin * 2

        // Keep the whole level clear of system-reserved screen edges by pulling
        // the camera back until the reserved strips fall on empty ground.
        //
        // The strips are a fraction of the *view*, and the view grows as the
        // camera pulls back, so this is solved algebraically rather than by
        // adding a fudge factor: covered = extent × fraction, and we need
        // extent − covered ≥ level, hence extent = level / (1 − fraction).
        //
        // Chosen over modelling the notch's actual shape because iOS does not
        // expose that geometry, and guessing it per device is exactly what
        // docs/DEVELOPMENT_FINDINGS.md rules out.
        if mode != .fillWidth, let viewportSize, viewportSize.width > 0, viewportSize.height > 0 {
            let horizontalFraction = (screenInsets.leading + screenInsets.trailing) / viewportSize.width
            let verticalFraction = (screenInsets.top + screenInsets.bottom) / viewportSize.height

            if horizontalFraction > 0, horizontalFraction < 0.9 {
                width = max(width, (levelWidth + margin * 2) / (1 - horizontalFraction))
            }
            if verticalFraction > 0, verticalFraction < 0.9 {
                depth = max(depth, (levelDepth + margin * 2) / (1 - verticalFraction))
            }
        }

        // The camera never moves off the level's centre line. Leaning is applied
        // to the world instead — see `CameraControl.worldTilt`. Orbiting the
        // camera was tried first and was wrong twice over: screen-right swung
        // away from world +x, so the map appeared to rotate, and the building
        // slid off its own frame leaving empty corners.
        let tilt = tiltDegrees * .pi / 180
        // Tilting compresses the ground plane on screen but adds the wall
        // height back as apparent depth.
        let projectedDepth = depth * cos(tilt) + metrics.wallHeight * sin(tilt)

        // The vertical extent needed to show the full depth, versus the vertical
        // extent implied by having to show the full width.
        let verticalFromWidth = aspectRatio > 0 ? width / aspectRatio : projectedDepth
        let verticalExtentBeforeZoom = switch mode {
        case .fit: max(projectedDepth, verticalFromWidth)
        case .fill: min(projectedDepth, verticalFromWidth)
        // Width decides, full stop. Whatever does not fit vertically — the far
        // wall, the near wall's outer face — is meant to leave the frame.
        case .fillWidth: verticalFromWidth
        }

        // Leaning foreshortens the building, which would open gaps at the edges.
        // Closing in by the same factor keeps it filling the frame: the display
        // must never show anything that is not the building.
        let verticalExtent = verticalExtentBeforeZoom
            * control.leanCompensation
            / max(control.zoom, 0.01)

        let center = metrics.worldPoint(bounds.center)

        // Centre on what actually lands on screen, not on the floor.
        //
        // Tilting makes the far wall lean *up* into frame while the near wall
        // simply ends at the floor, so aiming at the floor's centre leaves a
        // sliver of ground visible beyond the far wall and wastes the same
        // amount at the bottom. Shifting the aim back by half the wall's
        // apparent height balances it: both walls then run off their edges.
        // Under perspective the walls already lean into frame on their own, so
        // the orthographic correction that pushed the aim back is not wanted.
        let tiltBias: Double = switch (mode, projection) {
        case (.fillWidth, .orthographic): metrics.wallHeight * sin(tilt) / (2 * cos(tilt))
        default: 0
        }

        // Keep the frame inside the floor: at zoom 1 the centre cannot move at
        // all, and beyond that only as far as the off-screen remainder allows.
        let visibleWidth = verticalExtent * aspectRatio
        let visibleDepth = verticalExtent / max(cos(tilt), 0.2)
        let clamped = control.clampedToLevel(
            bounds: bounds,
            metrics: metrics,
            visibleWidth: visibleWidth,
            visibleDepth: visibleDepth
        )

        // The focus sits on the *top* of the walls, not on the floor.
        //
        // This is what pins the wall tops to the display edges: whatever the
        // camera does, the plane it is aimed at stays put on screen, and under
        // perspective everything below it — the floor — swings instead. Aiming
        // at the floor would pin the floor and swing the walls, which is the
        // wrong way round.
        // Aim at the centre of the floor. The wall tops end up acting as the
        // visual anchor on their own, because they are nearer the camera and so
        // shift least when the view leans — which is the effect wanted, without
        // forcing any point to be mathematically pinned.
        let focus = WorldPoint(
            x: center.x + clamped.focusOffset.x,
            y: 0,
            z: center.z - tiltBias + clamped.focusOffset.z
        )

        // Orthographic scale is independent of distance, so the camera only has
        // to clear the geometry. A perspective camera has to stand exactly far
        // enough back that `verticalExtent` fills its field of view.
        let distance: Double = switch projection {
        case .orthographic:
            60
        case .perspective(let fieldOfViewDegrees):
            // Stand far enough back that the floor's width exactly spans the
            // field of view at the distance of the floor itself.
            (verticalExtent / 2) / tan(fieldOfViewDegrees * .pi / 360)
        }

        // What the framing costs, measured against the level itself rather than
        // the margin, so trimming empty padding does not count as cropping.
        let visibleGroundDepth = (verticalExtent - metrics.wallHeight * sin(tilt)) / cos(tilt)
        let croppedDepth = max(0, levelDepth - visibleGroundDepth)
        let croppedWidth = max(0, levelWidth - visibleWidth)

        // Leaning swings the camera around that fixed focus. Under perspective
        // this is what makes the floor slide while the wall tops hold still.
        let swingX = control.leanHorizontal * .pi / 180
        let swingZ = control.leanVertical * .pi / 180

        let position = WorldPoint(
            x: focus.x - distance * sin(swingX),
            y: focus.y + distance * cos(tilt) * cos(swingX),
            z: focus.z + distance * sin(tilt) + distance * sin(swingZ)
        )

        return CameraFraming(
            verticalExtent: verticalExtent,
            focus: focus,
            position: position,
            croppedDepth: croppedDepth,
            croppedWidth: croppedWidth,
            projection: projection
        )
    }
}
