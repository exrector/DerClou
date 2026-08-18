import Foundation

/// How far the view is leaning into the building, as a shear about the plane of
/// the wall tops.
///
/// This is the peek gesture, and it is a shear rather than a camera move for one
/// reason: a shear about a plane leaves that plane exactly where it was. The
/// tops of the exterior walls frame the level on screen, and that frame must not
/// move, scale or skew for any gesture — so the frame is made the fixed plane of
/// the transform, and the question stops being "how much correction does the
/// camera need" and becomes arithmetic that cannot drift.
///
/// Everything at any other height moves, by an amount proportional to how far
/// below the frame it is: the floor most of all, then the furniture standing on
/// it, the people, and the inside faces of the walls, which is what the player
/// sees as looking into the box from one side.
///
/// It is applied to the scene, not to the game: navigation, patrols and every
/// position the rules care about stay in the level's own space, which this
/// converts to and from.
public struct ViewShear: Sendable, Equatable {
    /// Meters of sideways travel per meter below the anchor plane.
    public var acrossX: Double
    /// Meters of travel up and down the screen per meter below the anchor.
    public var acrossZ: Double
    /// Height of the fixed plane: the top of the walls.
    public var anchorHeight: Double

    public init(acrossX: Double = 0, acrossZ: Double = 0, anchorHeight: Double = 0) {
        self.acrossX = acrossX
        self.acrossZ = acrossZ
        self.anchorHeight = anchorHeight
    }

    public static let none = ViewShear()

    public var isFlat: Bool { acrossX == 0 && acrossZ == 0 }

    /// Level space to world space.
    public func apply(to point: WorldPoint) -> WorldPoint {
        let below = point.y - anchorHeight
        return WorldPoint(
            x: point.x + acrossX * below,
            y: point.y,
            z: point.z + acrossZ * below
        )
    }

    /// World space back to level space.
    public func undo(_ point: WorldPoint) -> WorldPoint {
        let below = point.y - anchorHeight
        return WorldPoint(
            x: point.x - acrossX * below,
            y: point.y,
            z: point.z - acrossZ * below
        )
    }

    /// World space back to level space, for a ray.
    ///
    /// The shear is linear and leaves height alone, so the direction transforms
    /// the same way the difference of two points does.
    public func undo(_ ray: WorldRay) -> WorldRay {
        let origin = undo(ray.origin)
        let ahead = undo(ray.origin + ray.direction)
        return WorldRay(origin: origin, direction: (ahead - origin).normalized)
    }

    /// The shear as a 4x4 matrix, in column-major order, ready for the scene.
    public var columns: [[Double]] {
        [
            [1, 0, 0, 0],
            [acrossX, 1, acrossZ, 0],
            [0, 0, 1, 0],
            [-acrossX * anchorHeight, 0, -acrossZ * anchorHeight, 1]
        ]
    }
}
