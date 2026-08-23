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
    /// Approximate extra distance from each cell centre to non-walkable space.
    /// Physical body radius has already been eroded from `walkable`; this field
    /// is the remaining comfort clearance used to avoid wall-hugging.
    public let clearance: [Double]

    public init(
        minX: Double,
        minZ: Double,
        cellSize: Double,
        columns: Int,
        rows: Int,
        walkable: [Bool],
        clearance: [Double]? = nil
    ) {
        self.minX = minX
        self.minZ = minZ
        self.cellSize = cellSize
        self.columns = columns
        self.rows = rows
        self.walkable = walkable
        self.clearance = clearance ?? Self.makeClearanceField(
            cellSize: cellSize,
            columns: columns,
            rows: rows,
            walkable: walkable
        )
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

    public func clearance(at cell: Cell) -> Double {
        guard contains(cell) else { return 0 }
        return clearance[cell.row * columns + cell.column]
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

    /// Returns a short-lived planning view with moving bodies masked out.
    ///
    /// Static geometry and material world changes are already baked into this
    /// grid. Rebuilding all of that geometry — including the global clearance
    /// transform — merely because another actor occupies a few cells stalls
    /// the render thread on every tap. Actor bodies are transient avoidance,
    /// not walls: copy the existing walkability once, touch only cells inside
    /// their local bounds, and deliberately retain the static clearance field.
    public func blockingTransientObstacles(
        _ obstacles: [WorldBox],
        characterRadius: Double,
        characterHeight: Double
    ) -> NavGrid {
        guard !obstacles.isEmpty, columns > 0, rows > 0 else { return self }
        var masked = walkable

        for obstacle in obstacles {
            let bottom = obstacle.center.y - obstacle.height / 2
            let top = obstacle.center.y + obstacle.height / 2
            guard bottom < characterHeight, top > 0.05 else { continue }

            let radians = obstacle.yaw * .pi / 180
            let cosine = cos(radians)
            let sine = sin(radians)
            let halfWidth = obstacle.width / 2 + characterRadius
            let halfDepth = obstacle.depth / 2 + characterRadius
            let extentX = abs(cosine) * halfWidth + abs(sine) * halfDepth
            let extentZ = abs(sine) * halfWidth + abs(cosine) * halfDepth

            let minColumn = max(0, Int(floor((obstacle.center.x - extentX - minX) / cellSize)))
            let maxColumn = min(columns - 1, Int(floor((obstacle.center.x + extentX - minX) / cellSize)))
            let minRow = max(0, Int(floor((obstacle.center.z - extentZ - minZ) / cellSize)))
            let maxRow = min(rows - 1, Int(floor((obstacle.center.z + extentZ - minZ) / cellSize)))
            guard minColumn <= maxColumn, minRow <= maxRow else { continue }

            // Rotate candidate cell centres into the obstacle's own frame.
            let inverseCosine = cos(-radians)
            let inverseSine = sin(-radians)
            for row in minRow...maxRow {
                for column in minColumn...maxColumn {
                    let point = worldPoint(Cell(column: column, row: row))
                    let dx = point.x - obstacle.center.x
                    let dz = point.z - obstacle.center.z
                    let localX = dx * inverseCosine + dz * inverseSine
                    let localZ = -dx * inverseSine + dz * inverseCosine
                    if abs(localX) <= halfWidth, abs(localZ) <= halfDepth {
                        masked[row * columns + column] = false
                    }
                }
            }
        }

        return NavGrid(
            minX: minX,
            minZ: minZ,
            cellSize: cellSize,
            columns: columns,
            rows: rows,
            walkable: masked,
            clearance: clearance
        )
    }

    /// Two-pass octile distance transform. It is deterministic, allocation-free
    /// after construction and sufficiently accurate for route preference. The
    /// actual collision guarantee still comes from the eroded walkability grid.
    private static func makeClearanceField(
        cellSize: Double,
        columns: Int,
        rows: Int,
        walkable: [Bool]
    ) -> [Double] {
        guard columns > 0, rows > 0, walkable.count == columns * rows else { return [] }

        let diagonal = sqrt(2.0)
        let infinity = Double.greatestFiniteMagnitude / 4
        var distances = walkable.map { $0 ? infinity : 0 }

        func index(_ column: Int, _ row: Int) -> Int { row * columns + column }

        for row in 0..<rows {
            for column in 0..<columns where walkable[index(column, row)] {
                let current = index(column, row)
                var best = distances[current]
                if column > 0 { best = min(best, distances[index(column - 1, row)] + 1) }
                if row > 0 { best = min(best, distances[index(column, row - 1)] + 1) }
                if column > 0, row > 0 {
                    best = min(best, distances[index(column - 1, row - 1)] + diagonal)
                }
                if column + 1 < columns, row > 0 {
                    best = min(best, distances[index(column + 1, row - 1)] + diagonal)
                }
                // Treat outside the grid as blocked even when custom test data
                // marks a boundary cell walkable.
                best = min(best, Double(column + 1), Double(row + 1))
                distances[current] = best
            }
        }

        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1)
                where walkable[index(column, row)] {
                let current = index(column, row)
                var best = distances[current]
                if column + 1 < columns { best = min(best, distances[index(column + 1, row)] + 1) }
                if row + 1 < rows { best = min(best, distances[index(column, row + 1)] + 1) }
                if column + 1 < columns, row + 1 < rows {
                    best = min(best, distances[index(column + 1, row + 1)] + diagonal)
                }
                if column > 0, row + 1 < rows {
                    best = min(best, distances[index(column - 1, row + 1)] + diagonal)
                }
                best = min(best, Double(columns - column), Double(rows - row))
                distances[current] = best
            }
        }

        return distances.map { $0 == infinity ? 0 : $0 * cellSize }
    }
}

/// Builds the walkability grid from level geometry.
public enum NavGridBuilder {
    /// - Parameters:
    ///   - geometry: world-space boxes for the level.
    ///   - budget: who the grid is for, and at what resolution.
    public static func build(
        geometry: LevelGeometry,
        budget: NavigationBudget = .standard,
        additionalObstacles: [WorldBox] = []
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
        let blockers = (geometry.obstacleBoxes + additionalObstacles).filter { box in
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
