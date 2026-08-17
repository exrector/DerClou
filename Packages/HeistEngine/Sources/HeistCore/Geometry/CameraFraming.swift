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
        margin: Double = 1.0
    ) -> CameraFraming {
        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        let width = levelWidth + margin * 2
        let depth = levelDepth + margin * 2

        let tilt = tiltDegrees * .pi / 180
        // Tilting compresses the ground plane on screen but adds the wall
        // height back as apparent depth.
        let projectedDepth = depth * cos(tilt) + metrics.wallHeight * sin(tilt)

        // The vertical extent needed to show the full depth, versus the vertical
        // extent implied by having to show the full width.
        let verticalFromWidth = aspectRatio > 0 ? width / aspectRatio : projectedDepth
        let verticalExtent = switch mode {
        case .fit: max(projectedDepth, verticalFromWidth)
        case .fill: min(projectedDepth, verticalFromWidth)
        }

        // What that costs, measured against the level itself rather than the
        // margin, so trimming empty padding does not count as cropping.
        let visibleGroundDepth = (verticalExtent - metrics.wallHeight * sin(tilt)) / cos(tilt)
        let visibleWidth = verticalExtent * aspectRatio
        let croppedDepth = max(0, levelDepth - visibleGroundDepth)
        let croppedWidth = max(0, levelWidth - visibleWidth)

        let center = metrics.worldPoint(bounds.center)
        let focus = WorldPoint(x: center.x, y: 0, z: center.z)

        // Orthographic scale is independent of distance, so the camera only has
        // to clear the geometry. A perspective camera has to stand exactly far
        // enough back that `verticalExtent` fills its field of view.
        let distance: Double = switch projection {
        case .orthographic:
            60
        case .perspective(let fieldOfViewDegrees):
            (verticalExtent / 2) / tan(fieldOfViewDegrees * .pi / 360)
        }

        let position = WorldPoint(
            x: center.x,
            y: distance * cos(tilt),
            z: center.z + distance * sin(tilt)
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
