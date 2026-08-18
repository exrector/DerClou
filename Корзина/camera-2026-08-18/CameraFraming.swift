import Foundation

/// Where the tactical camera stands, what it sees, and how far the view is
/// leaning into the building.
///
/// The camera is a window onto an open-topped box, and three things are true of
/// it at all times:
///
/// * **It never rotates.** It looks straight down, always, and screen right is
///   always world +x. Every exterior wall is parallel to an edge of the display
///   and stays that way.
/// * **It never moves for a gesture.** Only zoom changes where it stands.
/// * **The tops of the exterior walls are pinned to the screen.** They frame the
///   level, and that frame does not move, scale or skew for any gesture.
///
/// Leaning is carried by `shear`, which tips the contents of the box about the
/// plane of the wall tops — see `ViewShear`. An off-axis frustum would express
/// the same thing on the camera instead, and was tried first: RealityKit's
/// `ProjectiveTransformCameraComponent` is ignored by `RealityView`, which
/// renders black, so the shear lives on the scene.
public struct CameraFraming: Sendable, Equatable {
    /// Camera position, in meters. Always looking straight down from here.
    public var position: WorldPoint
    /// The point the view is pinned on: the middle of the level, at the height
    /// of the tops of the walls.
    public var anchor: WorldPoint

    /// Half-width of the frustum at unit depth — a tangent, not a distance.
    public var halfWidth: Double
    /// Half-height of the frustum at unit depth.
    public var halfHeight: Double
    /// How far the view is leaning into the building.
    public var shear: ViewShear

    /// How much of the level's own width falls outside the view, in meters.
    public var croppedWidth: Double
    /// How much of the level's own depth falls outside the view, in meters.
    public var croppedDepth: Double

    public init(
        position: WorldPoint,
        anchor: WorldPoint,
        halfWidth: Double,
        halfHeight: Double,
        shear: ViewShear = .none,
        croppedWidth: Double = 0,
        croppedDepth: Double = 0
    ) {
        self.position = position
        self.anchor = anchor
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.shear = shear
        self.croppedWidth = croppedWidth
        self.croppedDepth = croppedDepth
    }

    /// Distance from the camera down to the pinned plane, in meters.
    public var anchorDistance: Double { position.y - anchor.y }

    /// World meters spanned by the height of the screen, measured on the floor.
    public var verticalExtent: Double { 2 * halfHeight * position.y }

    /// The camera's axes. Constant: the camera does not rotate, ever.
    public var basis: (right: WorldPoint, up: WorldPoint, forward: WorldPoint) {
        (
            right: WorldPoint(x: 1, y: 0, z: 0),
            up: WorldPoint(x: 0, y: 0, z: -1),
            forward: WorldPoint(x: 0, y: -1, z: 0)
        )
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
    /// This is the default: the display must never show anything that is not the
    /// game. It is safe only when levels are authored roughly to the device's
    /// aspect ratio — `CameraFraming.croppedWidth` reports how much playfield is
    /// being lost, so a level can be checked in a test.
    case fill
}

/// What the player can do to the camera: lean into the box, and zoom.
///
/// Leaning is two angles, and it moves the viewpoint without moving the frame —
/// see `CameraFraming`. Yaw is deliberately absent: every exterior wall is
/// parallel to an edge of the screen, and the map is only learnable as a puzzle
/// if it stays that way.
public struct CameraControl: Sendable, Equatable {
    /// Degrees of lean from dragging a finger up and down the screen. The floor
    /// follows the finger.
    public var leanVertical: Double
    /// Degrees of lean from dragging a finger across the screen.
    public var leanHorizontal: Double
    /// Zoom multiplier. 1 frames the whole building; above 1 moves closer.
    public var zoom: Double
    /// Where the view is centred while zoomed in, in meters from the building's
    /// centre. Always clamped so the frame stays inside the building.
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

    /// How far the view may lean, the same in all four directions.
    ///
    /// How much of a wall's inside face this reveals is fixed by geometry: a
    /// lean of θ shifts the floor against the frame by the wall's height times
    /// tan θ, so 20° shows a little over a third of the wall's height.
    public static let leanRange: ClosedRange<Double> = -20...20

    /// Zoom limits.
    public static let zoomRange: ClosedRange<Double> = 1.0...3.0

    public func leaned(vertical: Double, horizontal: Double) -> CameraControl {
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
            leanVertical: leanVertical,
            leanHorizontal: leanHorizontal,
            zoom: zoom,
            focusOffset: offset
        )
    }

    /// Clamps the centre so the visible rectangle never leaves the floor.
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
/// Pure maths, kept out of the view layer so "does the frame actually stay
/// still" is answered by a unit test rather than by squinting at a screenshot.
public enum CameraFramingSolver {
    /// The default field of view, measured up the screen.
    ///
    /// Narrow on purpose — telephoto rather than wide angle. It sets how strong
    /// the perspective is: the wider it goes, the more of every inside wall face
    /// is visible before the player leans at all, and the more the building
    /// reads as a funnel rather than as a plan.
    public static let defaultFieldOfViewDegrees = 26.0

    /// - Parameters:
    ///   - bounds: level bounds, in cells. Their outline at wall-top height is
    ///     the frame that gets pinned to the display.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - mode: whether the level is fitted inside the screen or fills it.
    ///   - fieldOfViewDegrees: vertical field of view.
    ///   - margin: padding around the level, in meters.
    ///   - control: the player's lean and zoom.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fill,
        fieldOfViewDegrees: Double = defaultFieldOfViewDegrees,
        margin: Double = 0,
        control: CameraControl = .neutral
    ) -> CameraFraming {
        let aspect = max(aspectRatio, 0.01)
        let zoom = max(control.zoom, 0.01)

        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        let halfWidth = (levelWidth + margin * 2) / 2
        let halfDepth = (levelDepth + margin * 2) / 2

        // How much of the frame the screen has room for. Showing the full width
        // costs one amount, the full depth another; filling takes the smaller of
        // the two, and whatever does not fit runs off the edge.
        let coveredHalfDepth = switch mode {
        case .fill: min(halfDepth, halfWidth / aspect) / zoom
        case .fit: max(halfDepth, halfWidth / aspect) / zoom
        }
        let coveredHalfWidth = coveredHalfDepth * aspect

        // The frustum, as tangents at unit depth. Fixed by the field of view
        // alone, which is what makes the projection's shape independent of the
        // level: only the camera's height changes with the level's size.
        let frustumHalfHeight = tan(fieldOfViewDegrees * .pi / 360)
        let frustumHalfWidth = frustumHalfHeight * aspect

        // How far the camera stands above the wall tops for that frustum to
        // cover exactly the part of the frame the screen has room for.
        let anchorDistance = coveredHalfDepth / frustumHalfHeight

        let clamped = control.clampedToLevel(
            bounds: bounds,
            metrics: metrics,
            visibleWidth: coveredHalfWidth * 2,
            visibleDepth: coveredHalfDepth * 2
        )

        let centre = metrics.worldPoint(bounds.center)
        let anchor = WorldPoint(
            x: centre.x + clamped.focusOffset.x,
            y: metrics.wallHeight,
            z: centre.z + clamped.focusOffset.z
        )

        // Leaning, as a shear about the anchor plane. The signs put the floor
        // under the finger: drag right and the floor goes right, which reveals
        // the inside of the wall it moves away from.
        let shear = ViewShear(
            acrossX: -tan(clamped.leanHorizontal * .pi / 180),
            acrossZ: -tan(clamped.leanVertical * .pi / 180),
            anchorHeight: metrics.wallHeight
        )

        // Straight above the anchor. The gesture does not move the camera at
        // all — if it did, the frame would move with it.
        let position = WorldPoint(x: anchor.x, y: anchor.y + anchorDistance, z: anchor.z)

        return CameraFraming(
            position: position,
            anchor: anchor,
            halfWidth: frustumHalfWidth,
            halfHeight: frustumHalfHeight,
            shear: shear,
            croppedWidth: max(0, levelWidth - coveredHalfWidth * 2),
            croppedDepth: max(0, levelDepth - coveredHalfDepth * 2)
        )
    }
}
