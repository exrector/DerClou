import Foundation

/// How much world space an orthographic tactical camera must cover.
public struct CameraFraming: Sendable, Equatable {
    /// Vertical extent of the orthographic view, in meters.
    public var verticalExtent: Double
    /// World-space point the camera looks at.
    public var focus: WorldPoint
    /// Camera position, in meters.
    public var position: WorldPoint

    public init(verticalExtent: Double, focus: WorldPoint, position: WorldPoint) {
        self.verticalExtent = verticalExtent
        self.focus = focus
        self.position = position
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
        margin: Double = 1.5,
        distance: Double = 60
    ) -> CameraFraming {
        let width = metrics.meters(fromCells: bounds.size.width) + margin * 2
        let depth = metrics.meters(fromCells: bounds.size.depth) + margin * 2

        let tilt = tiltDegrees * .pi / 180
        // Tilting compresses the ground plane on screen but adds the wall
        // height back as apparent depth.
        let projectedDepth = depth * cos(tilt) + metrics.wallHeight * sin(tilt)

        // Fit both axes: the vertical extent needed to show the full depth, and
        // the vertical extent implied by having to show the full width.
        let verticalFromWidth = aspectRatio > 0 ? width / aspectRatio : projectedDepth
        let verticalExtent = max(projectedDepth, verticalFromWidth)

        let center = metrics.worldPoint(bounds.center)
        let focus = WorldPoint(x: center.x, y: 0, z: center.z)
        let position = WorldPoint(
            x: center.x,
            y: distance * cos(tilt),
            z: center.z + distance * sin(tilt)
        )

        return CameraFraming(verticalExtent: verticalExtent, focus: focus, position: position)
    }
}
