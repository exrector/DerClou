import Foundation

/// A walkability grid over the level's floor plane.
///
/// Built from the blueprint's own geometry rather than by voxelising the whole
/// scene. That distinction matters: a voxeliser sees a doorway lintel and a
/// desktop as horizontal surfaces and happily walks actors over them, whereas
/// here an obstacle is only an obstacle if it actually blocks the band of space
/// a person occupies.
///
/// Obstacles are dilated by the character radius when the grid is built, so any
/// path along cell centres automatically keeps its distance from walls.
public struct NavGrid: Sendable, Equatable {
    /// World position of the grid's lower corner, in meters.
    public let minX: Double
    public let minZ: Double
    public let cellSize: Double
    public let columns: Int
    public let rows: Int
    /// Row-major walkability, `columns * rows` entries.
    public let walkable: [Bool]

    public init(
        minX: Double,
        minZ: Double,
        cellSize: Double,
        columns: Int,
        rows: Int,
        walkable: [Bool]
    ) {
        self.minX = minX
        self.minZ = minZ
        self.cellSize = cellSize
        self.columns = columns
        self.rows = rows
        self.walkable = walkable
    }

    public struct Cell: Sendable, Equatable, Hashable {
        public var column: Int
        public var row: Int

        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }
    }

    public var cellCount: Int { columns * rows }

    public func contains(_ cell: Cell) -> Bool {
        cell.column >= 0 && cell.column < columns && cell.row >= 0 && cell.row < rows
    }

    public func isWalkable(_ cell: Cell) -> Bool {
        guard contains(cell) else { return false }
        return walkable[cell.row * columns + cell.column]
    }

    /// Centre of a cell, in world meters.
    public func worldPoint(_ cell: Cell) -> WorldPoint {
        WorldPoint(
            x: minX + (Double(cell.column) + 0.5) * cellSize,
            y: 0,
            z: minZ + (Double(cell.row) + 0.5) * cellSize
        )
    }

    /// Cell containing a world point, whether or not it is walkable.
    public func cell(at point: WorldPoint) -> Cell {
        Cell(
            column: Int(((point.x - minX) / cellSize).rounded(.down)),
            row: Int(((point.z - minZ) / cellSize).rounded(.down))
        )
    }

    /// Nearest walkable cell to a point, searched outward in rings.
    ///
    /// Lets a tap just outside a wall, or an actor standing a few centimetres
    /// off the grid, still resolve to something sensible.
    public func nearestWalkable(to point: WorldPoint, maximumRadius: Double = 3.0) -> Cell? {
        let start = cell(at: point)
        if isWalkable(start) { return start }

        let maximumRings = max(1, Int((maximumRadius / cellSize).rounded(.up)))
        for ring in 1...maximumRings {
            var best: Cell?
            var bestDistance = Double.greatestFiniteMagnitude

            for offset in -ring...ring {
                let candidates = [
                    Cell(column: start.column + offset, row: start.row - ring),
                    Cell(column: start.column + offset, row: start.row + ring),
                    Cell(column: start.column - ring, row: start.row + offset),
                    Cell(column: start.column + ring, row: start.row + offset)
                ]
                for candidate in candidates where isWalkable(candidate) {
                    let centre = worldPoint(candidate)
                    let distance = (centre.x - point.x) * (centre.x - point.x)
                        + (centre.z - point.z) * (centre.z - point.z)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = candidate
                    }
                }
            }

            if let best { return best }
        }
        return nil
    }
}

/// Builds the walkability grid from level geometry.
public enum NavGridBuilder {
    /// - Parameters:
    ///   - geometry: world-space boxes for the level.
    ///   - budget: who the grid is for, and at what resolution.
    public static func build(
        geometry: LevelGeometry,
        budget: NavigationBudget = .standard
    ) -> NavGrid {
        let cellSize = budget.cellSize
        let radius = budget.characterRadius
        let characterHeight = budget.characterHeight

        guard !geometry.floors.isEmpty else {
            return NavGrid(minX: 0, minZ: 0, cellSize: cellSize, columns: 0, rows: 0, walkable: [])
        }

        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude
        for floor in geometry.floors {
            minX = min(minX, floor.center.x - floor.width / 2)
            maxX = max(maxX, floor.center.x + floor.width / 2)
            minZ = min(minZ, floor.center.z - floor.depth / 2)
            maxZ = max(maxZ, floor.center.z + floor.depth / 2)
        }

        let columns = max(1, Int(((maxX - minX) / cellSize).rounded(.up)))
        let rows = max(1, Int(((maxZ - minZ) / cellSize).rounded(.up)))

        // Only obstacles that occupy the band a person walks through count. A
        // doorway lintel sits above it; a desk sits inside it.
        let blockers = geometry.obstacleBoxes.filter { box in
            let bottom = box.center.y - box.height / 2
            let top = box.center.y + box.height / 2
            return bottom < characterHeight && top > 0.05
        }

        var walkable = [Bool](repeating: false, count: columns * rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let point = WorldPoint(
                    x: minX + (Double(column) + 0.5) * cellSize,
                    y: 0,
                    z: minZ + (Double(row) + 0.5) * cellSize
                )

                // Inside the floor, inset by the character radius so an actor
                // never straddles the edge of the world.
                let onFloor = geometry.floors.contains { floor in
                    isInside(point, box: floor, inset: radius)
                }
                guard onFloor else { continue }

                // Clear of every blocker, dilated by the character radius.
                let blockedByProp = blockers.contains { blocker in
                    isInside(point, box: blocker, expandedBy: radius)
                }
                walkable[row * columns + column] = !blockedByProp
            }
        }

        return NavGrid(
            minX: minX,
            minZ: minZ,
            cellSize: cellSize,
            columns: columns,
            rows: rows,
            walkable: walkable
        )
    }

    /// Point-in-yawed-box test on the floor plane, with the box grown by
    /// `expandedBy` and shrunk by `inset`.
    private static func isInside(
        _ point: WorldPoint,
        box: WorldBox,
        expandedBy expansion: Double = 0,
        inset: Double = 0
    ) -> Bool {
        let radians = -box.yaw * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        let dx = point.x - box.center.x
        let dz = point.z - box.center.z

        // Rotate into the box's own frame.
        let localX = dx * cosine + dz * sine
        let localZ = -dx * sine + dz * cosine

        let halfWidth = box.width / 2 + expansion - inset
        let halfDepth = box.depth / 2 + expansion - inset

        return abs(localX) <= halfWidth && abs(localZ) <= halfDepth
    }
}
