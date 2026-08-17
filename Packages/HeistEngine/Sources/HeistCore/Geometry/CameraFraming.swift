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
public struct CameraControl: Sendable, Equatable {
    /// Pan offset from the level centre, in meters.
    public var pan: WorldPoint
    /// Zoom multiplier. 1 frames the level; above 1 moves closer.
    public var zoom: Double

    public init(pan: WorldPoint = .zero, zoom: Double = 1) {
        self.pan = pan
        self.zoom = zoom
    }

    public static let neutral = CameraControl()

    public var isNeutral: Bool { self == .neutral }

    /// Zoom limits. The lower bound keeps the level from shrinking into the
    /// middle of the screen; the upper one stops the player losing all context.
    public static let zoomRange: ClosedRange<Double> = 1.0...3.0

    public func zoomed(by factor: Double) -> CameraControl {
        CameraControl(
            pan: pan,
            zoom: min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        )
    }

    /// Pans by a world-space delta, clamped so the view cannot leave the level.
    public func panned(by delta: WorldPoint, within bounds: CellRect, metrics: LevelMetrics) -> CameraControl {
        guard zoom > 1 else { return CameraControl(pan: .zero, zoom: zoom) }

        // How far the centre may stray: the part of the level currently off
        // screen, halved.
        let slackX = metrics.meters(fromCells: bounds.size.width) * (1 - 1 / zoom) / 2
        let slackZ = metrics.meters(fromCells: bounds.size.depth) * (1 - 1 / zoom) / 2

        return CameraControl(
            pan: WorldPoint(
                x: min(max(pan.x + delta.x, -slackX), slackX),
                y: 0,
                z: min(max(pan.z + delta.z, -slackZ), slackZ)
            ),
            zoom: zoom
        )
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

        // Zoom shrinks the covered extent; pan slides the focus.
        let verticalExtent = verticalExtentBeforeZoom / max(control.zoom, 0.01)

        let center = metrics.worldPoint(bounds.center)

        // Centre on what actually lands on screen, not on the floor.
        //
        // Tilting makes the far wall lean *up* into frame while the near wall
        // simply ends at the floor, so aiming at the floor's centre leaves a
        // sliver of ground visible beyond the far wall and wastes the same
        // amount at the bottom. Shifting the aim back by half the wall's
        // apparent height balances it: both walls then run off their edges.
        let tiltBias: Double = switch mode {
        case .fillWidth: metrics.wallHeight * sin(tilt) / (2 * cos(tilt))
        case .fit, .fill: 0
        }

        let focus = WorldPoint(
            x: center.x + control.pan.x,
            y: 0,
            z: center.z - tiltBias + control.pan.z
        )

        // Orthographic scale is independent of distance, so the camera only has
        // to clear the geometry. A perspective camera has to stand exactly far
        // enough back that `verticalExtent` fills its field of view.
        let distance: Double = switch projection {
        case .orthographic:
            60
        case .perspective(let fieldOfViewDegrees):
            (verticalExtent / 2) / tan(fieldOfViewDegrees * .pi / 360)
        }

        // What the framing costs, measured against the level itself rather than
        // the margin, so trimming empty padding does not count as cropping.
        let visibleGroundDepth = (verticalExtent - metrics.wallHeight * sin(tilt)) / cos(tilt)
        let visibleWidth = verticalExtent * aspectRatio
        let croppedDepth = max(0, levelDepth - visibleGroundDepth)
        let croppedWidth = max(0, levelWidth - visibleWidth)

        let position = WorldPoint(
            x: focus.x,
            y: distance * cos(tilt),
            z: focus.z + distance * sin(tilt)
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
