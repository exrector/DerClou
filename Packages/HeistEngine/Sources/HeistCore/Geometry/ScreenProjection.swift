import Foundation

/// A ray in world space, in meters.
public struct WorldRay: Sendable, Equatable {
    public var origin: WorldPoint
    /// Unit direction.
    public var direction: WorldPoint

    public init(origin: WorldPoint, direction: WorldPoint) {
        self.origin = origin
        self.direction = direction
    }
}

/// Turns a screen tap into a world ray under the tactical camera.
///
/// Done by hand rather than through RealityKit's entity-targeting gestures: the
/// projection is exactly defined by the camera framing we already compute, so
/// tap resolution becomes deterministic, testable, and independent of how the
/// input stack decides to hit-test entities.
///
/// The tactical camera never rotates around the vertical axis, which keeps this
/// simple: screen-right is always world +x, and the camera basis follows from
/// the framing alone.
public enum ScreenProjection {
    /// - Parameters:
    ///   - screenPoint: tap location in points, origin top-left, y down.
    ///   - viewportSize: view size in points.
    ///   - framing: the framing currently applied to the camera.
    public static func ray(
        screenPoint: (x: Double, y: Double),
        viewportSize: (width: Double, height: Double),
        framing: CameraFraming
    ) -> WorldRay? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let forward = normalize(subtract(framing.focus, framing.position))
        // Screen-right is world +x for a camera that only ever tilts.
        let right = WorldPoint(x: 1, y: 0, z: 0)
        let up = cross(right, forward)

        // Normalised device coordinates: x right, y up, both in -1...1.
        let ndcX = (screenPoint.x / viewportSize.width) * 2 - 1
        let ndcY = 1 - (screenPoint.y / viewportSize.height) * 2

        let halfHeight = framing.verticalExtent / 2
        let halfWidth = halfHeight * (viewportSize.width / viewportSize.height)

        // Orthographic: the ray starts offset from the camera and runs parallel
        // to the view direction, rather than fanning out from a focal point.
        let origin = add(
            framing.position,
            add(scale(right, ndcX * halfWidth), scale(up, ndcY * halfHeight))
        )

        return WorldRay(origin: origin, direction: forward)
    }

    /// Intersects a ray with a horizontal plane, returning nil if it never
    /// crosses it in front of the camera.
    public static func hit(_ ray: WorldRay, planeY: Double = 0) -> WorldPoint? {
        guard abs(ray.direction.y) > 1e-6 else { return nil }
        let distance = (planeY - ray.origin.y) / ray.direction.y
        guard distance > 0 else { return nil }
        return add(ray.origin, scale(ray.direction, distance))
    }

    // MARK: - Small vector helpers

    private static func add(_ lhs: WorldPoint, _ rhs: WorldPoint) -> WorldPoint {
        WorldPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    private static func subtract(_ lhs: WorldPoint, _ rhs: WorldPoint) -> WorldPoint {
        WorldPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    private static func scale(_ point: WorldPoint, _ factor: Double) -> WorldPoint {
        WorldPoint(x: point.x * factor, y: point.y * factor, z: point.z * factor)
    }

    private static func normalize(_ point: WorldPoint) -> WorldPoint {
        let length = (point.x * point.x + point.y * point.y + point.z * point.z).squareRoot()
        guard length > 1e-9 else { return WorldPoint(x: 0, y: -1, z: 0) }
        return WorldPoint(x: point.x / length, y: point.y / length, z: point.z / length)
    }

    private static func cross(_ lhs: WorldPoint, _ rhs: WorldPoint) -> WorldPoint {
        WorldPoint(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }
}
