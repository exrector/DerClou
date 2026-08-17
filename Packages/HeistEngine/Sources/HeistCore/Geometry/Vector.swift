import Foundation

/// Vector arithmetic on the floor plane.
///
/// Deliberately not SIMD: `HeistCore` stays free of RealityKit and of any
/// platform graphics type, so the rules of the game can be tested on their own.
/// The runtime converts to `SIMD3<Float>` at the boundary, in one place.
extension WorldPoint {
    public static func + (lhs: WorldPoint, rhs: WorldPoint) -> WorldPoint {
        WorldPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: WorldPoint, rhs: WorldPoint) -> WorldPoint {
        WorldPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (point: WorldPoint, factor: Double) -> WorldPoint {
        WorldPoint(x: point.x * factor, y: point.y * factor, z: point.z * factor)
    }

    public var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// Length ignoring height. Most of the game is a floor plan, so this is the
    /// distance that usually matters.
    public var planarLength: Double {
        (x * x + z * z).squareRoot()
    }

    public var normalized: WorldPoint {
        let length = self.length
        guard length > 1e-9 else { return WorldPoint(x: 0, y: -1, z: 0) }
        return WorldPoint(x: x / length, y: y / length, z: z / length)
    }

    public func distance(to other: WorldPoint) -> Double {
        (self - other).length
    }

    /// Distance on the floor plane, ignoring height.
    public func planarDistance(to other: WorldPoint) -> Double {
        (self - other).planarLength
    }

    public func cross(_ other: WorldPoint) -> WorldPoint {
        WorldPoint(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    /// Drops the height component.
    public var onFloorPlane: WorldPoint {
        WorldPoint(x: x, y: 0, z: z)
    }
}
