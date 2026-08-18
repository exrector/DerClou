import Foundation

/// The horizontal plane the view is anchored to, and the rectangle of it that
/// frames the level on screen.
///
/// Version 1 of the level format takes this from the level's own outline at the
/// height of the exterior walls, which is why those walls are currently a
/// rectangle of one height. That is a property of the format, not of the camera:
/// the anchor plane is just a plane, and a later format can put an explicit one
/// over an L-shaped building, a courtyard or walls of differing height without
/// the camera changing at all.
public struct ProjectionAnchorPlane: Sendable, Equatable {
    /// Height above the floor, in meters.
    public var height: Double
    /// Middle of the framed rectangle.
    public var centre: WorldPoint
    /// Half the rectangle's width, in meters.
    public var halfWidth: Double
    /// Half its depth.
    public var halfDepth: Double

    public init(height: Double, centre: WorldPoint, halfWidth: Double, halfDepth: Double) {
        self.height = height
        self.centre = centre
        self.halfWidth = halfWidth
        self.halfDepth = halfDepth
    }
}

/// The tactical camera, as one value: where it stands, what it looks through,
/// and the matrix that expresses it.
///
/// **A fixed top-plane anchored off-axis perspective camera.** Three properties
/// hold at all times:
///
/// * It looks straight down and never rotates. Screen right is world +x. Every
///   exterior wall stays parallel to an edge of the display, and the frame stays
///   a rectangle — as soon as the camera tips, a rectangle becomes a trapezium
///   and nothing can pin it again.
/// * Peeking moves the camera sideways, which is a real change of viewpoint.
/// * The projection is off axis by exactly the amount that cancels that movement
///   **at the anchor plane**. A shift of the principal point moves the image by
///   an amount independent of depth; moving the camera moves it by an amount
///   inversely proportional to depth. Matching the two at one depth cancels
///   there and nowhere else, so the tops of the walls hold still while the floor
///   below them slides by `anchor height × tan(peek)`.
///
/// Nothing in the world moves for any of this. One set of coordinates serves
/// rendering, navigation, collision, patrols, lighting and interaction.
///
/// This is the single source of truth: the matrix handed to the renderer, the
/// ray a tap turns into, and the screen position of a world point are all built
/// from the numbers below. Two implementations of the same projection would
/// drift, and the symptom would be taps landing away from the finger.
public struct CameraProjection: Sendable, Equatable {
    /// Viewport width divided by height.
    public var aspectRatio: Double
    public var near: Double
    public var far: Double
    /// Vertical field of view, in degrees.
    public var fieldOfViewDegrees: Double

    /// The plane held still on screen.
    public var anchor: ProjectionAnchorPlane
    /// How far the camera stands above that plane, in meters.
    public var anchorDistance: Double

    /// Peek across the screen, as a slope: `tan` of the angle. Positive slides
    /// the floor right.
    public var peekAcross: Double
    /// Peek up the screen. Positive slides the floor down.
    public var peekUp: Double

    /// How much of the level's own width falls outside the view, in meters.
    public var croppedWidth: Double
    /// How much of its depth falls outside, in meters.
    public var croppedDepth: Double

    public init(
        aspectRatio: Double,
        near: Double = 0.05,
        far: Double = 400,
        fieldOfViewDegrees: Double,
        anchor: ProjectionAnchorPlane,
        anchorDistance: Double,
        peekAcross: Double = 0,
        peekUp: Double = 0,
        croppedWidth: Double = 0,
        croppedDepth: Double = 0
    ) {
        self.aspectRatio = aspectRatio
        self.near = near
        self.far = far
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.anchor = anchor
        self.anchorDistance = anchorDistance
        self.peekAcross = peekAcross
        self.peekUp = peekUp
        self.croppedWidth = croppedWidth
        self.croppedDepth = croppedDepth
    }

    // MARK: - The frustum

    /// Half-height of the frustum at unit depth — a tangent, not a distance.
    public var halfHeight: Double { tan(fieldOfViewDegrees * .pi / 360) }

    /// Half-width at unit depth.
    public var halfWidth: Double { halfHeight * aspectRatio }

    /// Sideways offset of the principal point. Opposite in sign to the camera's
    /// slide, which is what makes them cancel at the anchor plane.
    public var offsetAcross: Double { -peekAcross }

    /// Vertical offset. Same sign as the slide, because screen up is world -z.
    public var offsetUp: Double { peekUp }

    /// Where the camera stands.
    public var position: WorldPoint {
        WorldPoint(
            x: anchor.centre.x + anchorDistance * peekAcross,
            y: anchor.height + anchorDistance,
            z: anchor.centre.z + anchorDistance * peekUp
        )
    }

    /// The camera's axes. Constant: it does not rotate, ever.
    public var basis: (right: WorldPoint, up: WorldPoint, forward: WorldPoint) {
        (
            right: WorldPoint(x: 1, y: 0, z: 0),
            up: WorldPoint(x: 0, y: 0, z: -1),
            forward: WorldPoint(x: 0, y: -1, z: 0)
        )
    }

    /// World meters spanned by the height of the screen, measured on the floor.
    public var verticalExtent: Double { 2 * halfHeight * position.y }

    /// True when the whole level is on screen.
    public var showsWholeLevel: Bool {
        croppedDepth <= 0.001 && croppedWidth <= 0.001
    }

    // MARK: - The matrix

    /// The projection matrix, column-major, as plain numbers.
    ///
    /// Given to the renderer as-is. `HeistCore` stays free of platform graphics
    /// types, so the conversion to a 4x4 happens at the boundary — but the
    /// numbers are these and only these.
    ///
    /// RealityKit's projective camera uses **reverse depth**: the near plane maps
    /// to 1 and the far plane to 0. The implementation was additionally validated
    /// experimentally against the built-in perspective camera at zero offset.
    ///
    /// The third column is the whole difference from an ordinary camera: it adds
    /// a multiple of the depth to the clip-space x and y, and since the divide
    /// that follows is by that same depth, the result is a constant offset of the
    /// image. That is the off-axis shift.
    public var matrixColumns: [[Double]] {
        let x = 1 / halfWidth
        let y = 1 / halfHeight
        return [
            [x, 0, 0, 0],
            [0, y, 0, 0],
            [offsetAcross * x, offsetUp * y, near / (far - near), -1],
            [0, 0, far * near / (far - near), 0]
        ]
    }

    // MARK: - Projecting, and going back

    /// Where a world point lands on screen, in points from the top left.
    public func screenPoint(
        of world: WorldPoint,
        viewportSize: (width: Double, height: Double)
    ) -> (x: Double, y: Double)? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let camera = position
        // Everything the camera can see is below it, because it looks straight
        // down.
        let depth = camera.y - world.y
        guard depth > 0.0001 else { return nil }

        let across = (world.x - camera.x) / depth - offsetAcross
        let up = -(world.z - camera.z) / depth - offsetUp

        return (
            x: (across / halfWidth + 1) / 2 * viewportSize.width,
            y: (1 - up / halfHeight) / 2 * viewportSize.height
        )
    }

    /// The ray a screen point casts into the world.
    public func ray(
        screenPoint: (x: Double, y: Double),
        viewportSize: (width: Double, height: Double)
    ) -> WorldRay? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        // Normalised device coordinates: x right, y up, both in -1...1.
        let ndcX = (screenPoint.x / viewportSize.width) * 2 - 1
        let ndcY = 1 - (screenPoint.y / viewportSize.height) * 2

        let across = ndcX * halfWidth + offsetAcross
        let up = ndcY * halfHeight + offsetUp

        // One meter down for every meter of depth, so these are read straight
        // off as the sideways travel over that meter.
        return WorldRay(
            origin: position,
            direction: WorldPoint(x: across, y: -1, z: -up).normalized
        )
    }
}

/// How the level is fitted to the viewport.
public enum FramingMode: String, Sendable, Codable, CaseIterable {
    /// Show the whole anchor rectangle, letterboxing whichever axis does not
    /// match the viewport. Nothing is ever cropped.
    case fit
    /// Fill the viewport edge to edge, cropping whichever axis overflows.
    ///
    /// The default: the display must never show anything that is not the game.
    /// `CameraProjection.croppedWidth` reports what it costs, so a level can be
    /// checked in a test.
    case fill
}

/// What the player can do to the camera: peek into the box, and zoom.
///
/// Yaw is deliberately absent, and so is panning. The map is a puzzle: it is
/// only learnable if screen directions never move and the building never slides.
public struct CameraControl: Sendable, Equatable {
    /// Degrees of peek from dragging a finger up and down the screen.
    public var leanVertical: Double
    /// Degrees of peek from dragging across it.
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

    /// How far the view may peek, the same in all four directions.
    ///
    /// The effect is fixed by geometry: a peek of θ slides the floor against the
    /// frame by the anchor height times tan θ, so 20° over a 3 m wall exposes a
    /// little over a third of its inside face.
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
///
/// Pure maths, kept out of the view layer so "does the frame actually hold
/// still" is answered by a unit test rather than by squinting at a screenshot.
public enum CameraProjectionSolver {
    /// Narrow on purpose — telephoto rather than wide angle.
    ///
    /// It sets how strong the perspective is: the wider it goes, the more of
    /// every inside wall face shows before the player peeks at all, and the more
    /// the building reads as a funnel rather than as a plan.
    public static let defaultFieldOfViewDegrees = 26.0

    /// - Parameters:
    ///   - bounds: level bounds, in cells. Their outline at wall-top height is
    ///     the anchor rectangle for this version of the level format.
    ///   - metrics: cell-to-meter conversion.
    ///   - aspectRatio: viewport width divided by height.
    ///   - mode: whether the anchor rectangle is fitted inside the screen or
    ///     fills it.
    ///   - fieldOfViewDegrees: vertical field of view.
    ///   - margin: padding around the level, in meters.
    ///   - anchorHeight: height of the plane held still on screen. Defaults to
    ///     the tops of the walls, which is the game's camera. Zero anchors the
    ///     floor instead — the gameplay plane stays put and everything standing
    ///     on it leans, which is the other way of reading the same scene and is
    ///     under comparison in the labs.
    ///   - control: the player's peek and zoom.
    public static func solve(
        bounds: CellRect,
        metrics: LevelMetrics,
        aspectRatio: Double,
        mode: FramingMode = .fill,
        fieldOfViewDegrees: Double = defaultFieldOfViewDegrees,
        margin: Double = 0,
        anchorHeight: Double? = nil,
        control: CameraControl = .neutral
    ) -> CameraProjection {
        let aspect = max(aspectRatio, 0.01)
        let zoom = max(control.zoom, 0.01)

        let levelWidth = metrics.meters(fromCells: bounds.size.width)
        let levelDepth = metrics.meters(fromCells: bounds.size.depth)
        let halfWidth = (levelWidth + margin * 2) / 2
        let halfDepth = (levelDepth + margin * 2) / 2

        // How much of the anchor rectangle the screen has room for. Showing the
        // full width costs one amount, the full depth another; filling takes the
        // smaller, and the rest runs off the edge.
        let coveredHalfDepth = switch mode {
        case .fill: min(halfDepth, halfWidth / aspect) / zoom
        case .fit: max(halfDepth, halfWidth / aspect) / zoom
        }
        let coveredHalfWidth = coveredHalfDepth * aspect

        let clamped = control.clampedToLevel(
            bounds: bounds,
            metrics: metrics,
            visibleWidth: coveredHalfWidth * 2,
            visibleDepth: coveredHalfDepth * 2
        )

        let centre = metrics.worldPoint(bounds.center)
        let height = anchorHeight ?? metrics.wallHeight
        let anchor = ProjectionAnchorPlane(
            height: height,
            centre: WorldPoint(
                x: centre.x + clamped.focusOffset.x,
                y: height,
                z: centre.z + clamped.focusOffset.z
            ),
            halfWidth: coveredHalfWidth,
            halfDepth: coveredHalfDepth
        )

        // How far above the anchor plane the camera has to stand for the frustum
        // to cover exactly that rectangle.
        let halfAngle = tan(fieldOfViewDegrees * .pi / 360)

        return CameraProjection(
            aspectRatio: aspect,
            fieldOfViewDegrees: fieldOfViewDegrees,
            anchor: anchor,
            anchorDistance: coveredHalfDepth / halfAngle,
            peekAcross: tan(clamped.leanHorizontal * .pi / 180),
            peekUp: tan(clamped.leanVertical * .pi / 180),
            croppedWidth: max(0, levelWidth - coveredHalfWidth * 2),
            croppedDepth: max(0, levelDepth - coveredHalfDepth * 2)
        )
    }
}
