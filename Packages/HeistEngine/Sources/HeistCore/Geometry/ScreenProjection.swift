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

        let forward = (framing.focus - framing.position).normalized
        // Screen-right is world +x for a camera that only ever tilts.
        let right = WorldPoint(x: 1, y: 0, z: 0)
        let up = right.cross(forward)

        // Normalised device coordinates: x right, y up, both in -1...1.
        let ndcX = (screenPoint.x / viewportSize.width) * 2 - 1
        let ndcY = 1 - (screenPoint.y / viewportSize.height) * 2

        let aspect = viewportSize.width / viewportSize.height

        switch framing.projection {
        case .orthographic:
            // Rays run parallel to the view direction and start offset from the
            // camera, rather than fanning out from a focal point.
            let halfHeight = framing.verticalExtent / 2
            let halfWidth = halfHeight * aspect
            let origin = framing.position + right * (ndcX * halfWidth) + up * (ndcY * halfHeight)
            return WorldRay(origin: origin, direction: forward)

        case .perspective(let fieldOfViewDegrees):
            // All rays share the camera's position and diverge by the field of
            // view.
            let tangent = tan(fieldOfViewDegrees * .pi / 360)
            let direction = (forward
                + right * (ndcX * aspect * tangent)
                + up * (ndcY * tangent)).normalized
            return WorldRay(origin: framing.position, direction: direction)
        }
    }

    /// Intersects a ray with a horizontal plane, returning nil if it never
    /// crosses it in front of the camera.
    public static func hit(_ ray: WorldRay, planeY: Double = 0) -> WorldPoint? {
        guard abs(ray.direction.y) > 1e-6 else { return nil }
        let distance = (planeY - ray.origin.y) / ray.direction.y
        guard distance > 0 else { return nil }
        return ray.origin + ray.direction * distance
    }
}
