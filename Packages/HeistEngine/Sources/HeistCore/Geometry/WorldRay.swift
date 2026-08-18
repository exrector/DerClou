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

    /// Where the ray crosses a horizontal plane, or nil if it never does in
    /// front of its origin.
    public func hit(planeY: Double = 0) -> WorldPoint? {
        guard abs(direction.y) > 1e-6 else { return nil }
        let distance = (planeY - origin.y) / direction.y
        guard distance > 0 else { return nil }
        return origin + direction * distance
    }
}
