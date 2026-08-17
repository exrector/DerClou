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

/// Turns a screen tap into a world ray under the tactical camera, and back.
///
/// Done by hand rather than through RealityKit's entity-targeting gestures: the
/// projection is exactly defined by the camera framing we already compute, so
/// tap resolution becomes deterministic, testable, and independent of how the
/// input stack decides to hit-test entities.
///
/// Two spaces meet here. *Level space* is where the game lives: floors, walls,
/// the navigation grid and every position the rules care about. *World space* is
/// what the renderer draws, which is level space with the lean applied. Rays
/// come out in world space, because that is what the scene is; the caller undoes
/// the lean when it wants an answer the game can use.
public enum ScreenProjection {
    /// - Parameters:
    ///   - screenPoint: tap location in points, origin top-left, y down.
    ///   - viewportSize: view size in points.
    ///   - framing: the framing currently applied to the camera.
    /// - Returns: a ray in world space.
    public static func ray(
        screenPoint: (x: Double, y: Double),
        viewportSize: (width: Double, height: Double),
        framing: CameraFraming
    ) -> WorldRay? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        // Normalised device coordinates: x right, y up, both in -1...1.
        let ndcX = (screenPoint.x / viewportSize.width) * 2 - 1
        let ndcY = 1 - (screenPoint.y / viewportSize.height) * 2

        // The camera looks straight down, so a ray drops one meter for every
        // meter of depth and these are its sideways travel over that meter.
        let across = ndcX * framing.halfWidth
        let up = ndcY * framing.halfHeight

        let direction = WorldPoint(x: across, y: -1, z: -up).normalized
        return WorldRay(origin: framing.position, direction: direction)
    }

    /// Where a point of the level lands on screen, in points.
    ///
    /// Takes a level-space point and applies the lean itself, so callers reason
    /// in the space the game is authored in.
    public static func screenPoint(
        of level: WorldPoint,
        viewportSize: (width: Double, height: Double),
        framing: CameraFraming
    ) -> (x: Double, y: Double)? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        guard framing.halfWidth > 0, framing.halfHeight > 0 else { return nil }

        let world = framing.shear.apply(to: level)

        // How far below the camera it sits. Everything the camera can see is
        // below it, because the camera looks straight down.
        let depth = framing.position.y - world.y
        guard depth > 0.0001 else { return nil }

        let ndcX = (world.x - framing.position.x) / (depth * framing.halfWidth)
        let ndcY = -(world.z - framing.position.z) / (depth * framing.halfHeight)

        return (
            x: (ndcX + 1) / 2 * viewportSize.width,
            y: (1 - ndcY) / 2 * viewportSize.height
        )
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
