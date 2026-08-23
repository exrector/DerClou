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
        in grid: NavGrid,
        character: CharacterProfile = .standard
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

        guard let cells = search(from: startCell, to: goalCell, in: grid, character: character) else {
            return .failure(.noRoute)
        }

        let smoothed = smooth(cells, in: grid, character: character)
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

    /// Reduces a valid route to the fewest steering links obtainable by greedy
    /// farthest-visible shortcuts. This is intentionally separate from A*:
    /// A* finds a safe corridor; this pass removes the obsolete joins that
    /// would otherwise make an actor leave and then rejoin an old segment.
    public static func minimumLinkPath(
        from start: WorldPoint,
        path: PathResult,
        in grid: NavGrid
    ) -> PathResult {
        let points = path.waypoints.filter { start.planarDistance(to: $0) > 1e-9 }
        guard points.count > 1 else { return path }

        var result: [WorldPoint] = []
        var anchor = start
        var nextIndex = 0
        while nextIndex < points.count {
            var furthest = nextIndex
            for candidate in stride(from: points.count - 1, through: nextIndex, by: -1) {
                if hasLineOfSight(from: anchor, to: points[candidate], in: grid) {
                    furthest = candidate
                    break
                }
            }
            let point = points[furthest]
            result.append(point)
            anchor = point
            nextIndex = furthest + 1
        }

        var length = 0.0
        var previous = start
        for point in result {
            length += previous.planarDistance(to: point)
            previous = point
        }
        return PathResult(waypoints: result, length: length)
    }

    // MARK: - A*

    private static func search(
        from start: NavGrid.Cell,
        to goal: NavGrid.Cell,
        in grid: NavGrid,
        character: CharacterProfile
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

                let tentative = costSoFar[current] + traversalCost(
                    stepLength: neighbour.cost,
                    cell: next,
                    grid: grid,
                    character: character
                )
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

    private static func traversalCost(
        stepLength: Double,
        cell: NavGrid.Cell,
        grid: NavGrid,
        character: CharacterProfile
    ) -> Double {
        let desired = character.preferredWallClearance
        guard desired > 0, character.wallAvoidanceWeight > 0 else { return stepLength }
        let deficit = max(0, desired - grid.clearance(at: cell)) / desired
        return stepLength * (1 + character.wallAvoidanceWeight * deficit * deficit)
    }

    // MARK: - Smoothing

    /// Drops intermediate cells whenever a straight line between two waypoints
    /// stays walkable, turning a staircase of grid steps into a few long legs.
    private static func smooth(
        _ cells: [NavGrid.Cell],
        in grid: NavGrid,
        character: CharacterProfile
    ) -> [NavGrid.Cell] {
        guard cells.count > 2 else { return cells }

        var result: [NavGrid.Cell] = []
        var anchor = 0
        result.append(cells[anchor])

        while anchor < cells.count - 1 {
            var furthest = anchor + 1
            // Test longest shortcuts first and stop at the first acceptable
            // one. Testing every shorter candidate after that changes nothing
            // but turns long routes into needless quadratic work.
            for candidate in stride(from: cells.count - 1, through: anchor + 1, by: -1) {
                let direct = weightedSegmentCost(
                    from: grid.worldPoint(cells[anchor]),
                    to: grid.worldPoint(cells[candidate]),
                    in: grid,
                    character: character
                )
                let corridor = weightedCellCost(
                    cells[anchor...candidate],
                    in: grid,
                    character: character
                )
                if let direct, direct <= corridor * 1.02 {
                    furthest = candidate
                    break
                }
            }
            result.append(cells[furthest])
            anchor = furthest
        }

        return result
    }

    private static func weightedCellCost(
        _ cells: ArraySlice<NavGrid.Cell>,
        in grid: NavGrid,
        character: CharacterProfile
    ) -> Double {
        guard var previous = cells.first else { return 0 }
        var result = 0.0
        for cell in cells.dropFirst() {
            let diagonal = cell.column != previous.column && cell.row != previous.row
            result += traversalCost(
                stepLength: diagonal ? sqrt(2.0) : 1,
                cell: cell,
                grid: grid,
                character: character
            )
            previous = cell
        }
        return result * grid.cellSize
    }

    /// Samples a proposed shortcut with the same clearance cost as A*. This is
    /// what prevents smoothing from undoing the wall-safe route A* just found.
    private static func weightedSegmentCost(
        from start: WorldPoint,
        to end: WorldPoint,
        in grid: NavGrid,
        character: CharacterProfile
    ) -> Double? {
        let distance = start.planarDistance(to: end)
        guard distance > 0 else { return 0 }
        let steps = max(1, Int((distance / (grid.cellSize * 0.5)).rounded(.up)))
        let sampleLength = distance / Double(steps)
        var result = 0.0
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let point = (start + (end - start) * t).onFloorPlane
            let cell = grid.cell(at: point)
            guard grid.isWalkable(cell) else { return nil }
            result += traversalCost(
                stepLength: sampleLength / grid.cellSize,
                cell: cell,
                grid: grid,
                character: character
            ) * grid.cellSize
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
