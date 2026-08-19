import Foundation

/// Finds where an actor should stand to interact with a prop.
///
/// A prop's own footprint is not walkable — that is the whole point of
/// `blocksMovement` — so "walk to the door" has to mean "walk to a point just
/// outside the door," not the door's own centre. This is that point.
public enum ApproachPointSolver {
    /// How far outside a prop's footprint counts as "close enough to reach
    /// out and use it." A little more than a body's own radius, so an actor
    /// stands next to a thing rather than inside its collision shape.
    public static let defaultStandoff = 0.5

    /// A walkable point just outside `box`, or nil if none of its sides has
    /// one within `standoff`.
    ///
    /// Tries all four sides of the box in its own rotated frame — forward,
    /// back, left, right — and keeps only the ones that resolve to a walkable
    /// cell. This is deliberately not "guess which side faces the room":
    /// for anything set against a wall (a door, a wall-mounted panel), the
    /// side that faces the wall is inside solid geometry and simply is not
    /// walkable, so it drops out on its own without this needing to know
    /// which side that is. Levels floating in open floor — a crate, a desk —
    /// usually leave every side walkable, and the nearest one to `origin`
    /// wins.
    ///
    /// - Parameters:
    ///   - box: the prop's world-space footprint.
    ///   - grid: the level's walkability grid.
    ///   - standoff: how far outside the footprint to stand, and how far
    ///     `nearestWalkable` is allowed to search from each candidate side.
    ///   - origin: where the requesting actor currently is, used to break a
    ///     tie between multiple open sides. When nil, the first walkable side
    ///     found (forward, back, right, left, in that order) is used —
    ///     deterministic, which is what a level with no actor in it yet
    ///     (e.g. a test) needs.
    public static func approachPoint(
        for box: WorldBox,
        grid: NavGrid,
        standoff: Double = defaultStandoff,
        from origin: WorldPoint? = nil
    ) -> WorldPoint? {
        // The box's local +x ("right") and +z ("forward") axes, rotated into
        // world space by its yaw. Local space is where `width` is the extent
        // along +x and `depth` the extent along +z, matching how every other
        // box-shaped query (NavGridBuilder's own `isInside`) already treats a
        // `WorldBox`.
        let radians = box.yaw * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let right = WorldPoint(x: cosine, y: 0, z: sine)
        let forward = WorldPoint(x: -sine, y: 0, z: cosine)

        let halfWidth = box.width / 2 + standoff
        let halfDepth = box.depth / 2 + standoff

        let sides = [
            box.center + forward * halfDepth,
            box.center - forward * halfDepth,
            box.center + right * halfWidth,
            box.center - right * halfWidth
        ]

        let reachable = sides.compactMap { side -> WorldPoint? in
            guard let cell = grid.nearestWalkable(to: side, maximumRadius: standoff) else { return nil }
            return grid.worldPoint(cell)
        }

        guard let origin else { return reachable.first }
        return reachable.min { $0.planarDistance(to: origin) < $1.planarDistance(to: origin) }
    }
}
