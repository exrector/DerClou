import Foundation

/// Why a path request produced nothing useful.
public enum PathFailure: String, Error, Sendable, Equatable {
    /// The actor is not standing anywhere the grid considers walkable.
    case startNotOnGrid
    /// The destination has no walkable cell near it — a wall, a desk, outside.
    case destinationNotReachable
    /// Both ends are valid but no route connects them.
    case noRoute
}

public struct PathResult: Sendable, Equatable {
    /// Waypoints in world meters, starting near the actor and ending at the goal.
    public var waypoints: [WorldPoint]
    /// Total length along the waypoints, in meters.
    public var length: Double

    public init(waypoints: [WorldPoint], length: Double) {
        self.waypoints = waypoints
        self.length = length
    }
}

/// Grid A* with line-of-sight smoothing.
///
/// Deterministic by construction: ties break on a fixed ordering, so the same
/// request always returns the same path. Planning depends on that — a plan whose
/// route silently changes between runs is not a plan.
public enum PathFinder {
    /// Eight-way movement. Diagonals are only allowed when both orthogonal
    /// neighbours are clear, so an actor never squeezes through the corner
    /// between two walls.
    private static let neighbours: [(dx: Int, dz: Int, cost: Double)] = [
        (0, -1, 1), (1, 0, 1), (0, 1, 1), (-1, 0, 1),
        (1, -1, 1.4142135), (1, 1, 1.4142135), (-1, 1, 1.4142135), (-1, -1, 1.4142135)
    ]

    public static func findPath(
        from start: WorldPoint,
        to destination: WorldPoint,
        in grid: NavGrid
    ) -> Result<PathResult, PathFailure> {
        guard grid.cellCount > 0 else { return .failure(.startNotOnGrid) }

        guard let startCell = grid.nearestWalkable(to: start, maximumRadius: 1.5) else {
            return .failure(.startNotOnGrid)
        }
        guard let goalCell = grid.nearestWalkable(to: destination, maximumRadius: 2.0) else {
            return .failure(.destinationNotReachable)
        }

        if startCell == goalCell {
            let point = grid.worldPoint(goalCell)
            return .success(PathResult(waypoints: [point], length: start.planarDistance(to: point)))
        }

        guard let cells = search(from: startCell, to: goalCell, in: grid) else {
            return .failure(.noRoute)
        }

        let smoothed = smooth(cells, in: grid)
        var waypoints = smoothed.map { grid.worldPoint($0) }

        // Finish on the requested point when it is itself walkable, so tapping a
        // specific spot puts the actor there rather than on the nearest cell
        // centre.
        if grid.isWalkable(grid.cell(at: destination)),
           let last = waypoints.last,
           hasLineOfSight(from: last, to: destination, in: grid) {
            waypoints[waypoints.count - 1] = WorldPoint(x: destination.x, y: 0, z: destination.z)
        }

        var length = 0.0
        var previous = start
        for point in waypoints {
            length += previous.planarDistance(to: point)
            previous = point
        }

        return .success(PathResult(waypoints: waypoints, length: length))
    }

    // MARK: - A*

    private static func search(
        from start: NavGrid.Cell,
        to goal: NavGrid.Cell,
        in grid: NavGrid
    ) -> [NavGrid.Cell]? {
        let count = grid.cellCount
        func index(_ cell: NavGrid.Cell) -> Int { cell.row * grid.columns + cell.column }

        var cameFrom = [Int](repeating: -1, count: count)
        var costSoFar = [Double](repeating: .greatestFiniteMagnitude, count: count)
        var closed = [Bool](repeating: false, count: count)

        var open = BinaryHeap()
        costSoFar[index(start)] = 0
        open.push(node: index(start), priority: heuristic(start, goal))

        while let current = open.pop() {
            if closed[current] { continue }
            closed[current] = true

            let cell = NavGrid.Cell(column: current % grid.columns, row: current / grid.columns)
            if cell == goal {
                return reconstruct(from: cameFrom, goal: current, grid: grid)
            }

            for neighbour in neighbours {
                let next = NavGrid.Cell(column: cell.column + neighbour.dx, row: cell.row + neighbour.dz)
                guard grid.isWalkable(next) else { continue }

                // No corner cutting: a diagonal step needs both of its
                // orthogonal components to be clear.
                if neighbour.dx != 0, neighbour.dz != 0 {
                    let sideA = NavGrid.Cell(column: cell.column + neighbour.dx, row: cell.row)
                    let sideB = NavGrid.Cell(column: cell.column, row: cell.row + neighbour.dz)
                    guard grid.isWalkable(sideA), grid.isWalkable(sideB) else { continue }
                }

                let nextIndex = index(next)
                guard !closed[nextIndex] else { continue }

                let tentative = costSoFar[current] + neighbour.cost
                if tentative < costSoFar[nextIndex] {
                    costSoFar[nextIndex] = tentative
                    cameFrom[nextIndex] = current
                    open.push(node: nextIndex, priority: tentative + heuristic(next, goal))
                }
            }
        }

        return nil
    }

    private static func heuristic(_ cell: NavGrid.Cell, _ goal: NavGrid.Cell) -> Double {
        // Octile distance: admissible for eight-way movement.
        let dx = Double(abs(cell.column - goal.column))
        let dz = Double(abs(cell.row - goal.row))
        return (dx + dz) + (1.4142135 - 2) * min(dx, dz)
    }

    private static func reconstruct(
        from cameFrom: [Int],
        goal: Int,
        grid: NavGrid
    ) -> [NavGrid.Cell] {
        var cells: [NavGrid.Cell] = []
        var cursor = goal
        while cursor >= 0 {
            cells.append(NavGrid.Cell(column: cursor % grid.columns, row: cursor / grid.columns))
            cursor = cameFrom[cursor]
        }
        return cells.reversed()
    }

    // MARK: - Smoothing

    /// Drops intermediate cells whenever a straight line between two waypoints
    /// stays walkable, turning a staircase of grid steps into a few long legs.
    private static func smooth(_ cells: [NavGrid.Cell], in grid: NavGrid) -> [NavGrid.Cell] {
        guard cells.count > 2 else { return cells }

        var result: [NavGrid.Cell] = []
        var anchor = 0
        result.append(cells[anchor])

        while anchor < cells.count - 1 {
            var furthest = anchor + 1
            for candidate in (anchor + 1)..<cells.count {
                if hasLineOfSight(
                    from: grid.worldPoint(cells[anchor]),
                    to: grid.worldPoint(cells[candidate]),
                    in: grid
                ) {
                    furthest = candidate
                }
            }
            result.append(cells[furthest])
            anchor = furthest
        }

        return result
    }

    /// True when every cell the segment passes through is walkable.
    ///
    /// Samples at half-cell steps: enough to catch a corner clipped by a
    /// diagonal, cheap enough to run inside the smoothing loop.
    public static func hasLineOfSight(
        from start: WorldPoint,
        to end: WorldPoint,
        in grid: NavGrid
    ) -> Bool {
        let distance = start.planarDistance(to: end)
        guard distance > 0 else { return grid.isWalkable(grid.cell(at: start)) }

        let steps = max(1, Int((distance / (grid.cellSize * 0.5)).rounded(.up)))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let point = (start + (end - start) * t).onFloorPlane
            guard grid.isWalkable(grid.cell(at: point)) else { return false }
        }
        return true
    }

}

/// Minimal binary heap keyed on priority. Avoids pulling in a dependency for
/// the one thing A* needs.
private struct BinaryHeap {
    private var storage: [(node: Int, priority: Double)] = []

    var isEmpty: Bool { storage.isEmpty }

    mutating func push(node: Int, priority: Double) {
        storage.append((node, priority))
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].priority < storage[parent].priority else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Int? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let smallest = storage.removeLast()

        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var candidate = parent
            if left < storage.count, storage[left].priority < storage[candidate].priority {
                candidate = left
            }
            if right < storage.count, storage[right].priority < storage[candidate].priority {
                candidate = right
            }
            guard candidate != parent else { break }
            storage.swapAt(parent, candidate)
            parent = candidate
        }

        return smallest.node
    }
}
