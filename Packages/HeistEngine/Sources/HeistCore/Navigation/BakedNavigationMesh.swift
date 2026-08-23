import Foundation

/// Canonical, runtime-ready navigation topology baked from level walkability.
/// Polygons are deliberately independent of RealityKit and GameplayKit so a
/// committed level asset produces identical corridors on every supported OS.
public struct BakedNavigationMesh: Sendable, Equatable, Codable {
    public struct Polygon: Sendable, Equatable, Codable {
        public var id: Int
        public var minX: Double
        public var maxX: Double
        public var minZ: Double
        public var maxZ: Double
        public var clearance: Double

        public var center: WorldPoint {
            WorldPoint(x: (minX + maxX) / 2, y: 0, z: (minZ + maxZ) / 2)
        }

        /// Membership is half-open on the positive axes. Adjacent polygons
        /// therefore never both claim a point on their shared portal. This
        /// matches the floor-to-cell convention used by the bake source.
        public func contains(_ point: WorldPoint, epsilon: Double = 1e-9) -> Bool {
            point.x >= minX - epsilon && point.x < maxX
                && point.z >= minZ - epsilon && point.z < maxZ
        }

        public func closestPoint(to point: WorldPoint) -> WorldPoint {
            WorldPoint(
                x: min(max(point.x, minX), maxX),
                y: 0,
                z: min(max(point.z, minZ), maxZ)
            )
        }
    }

    public struct Portal: Sendable, Equatable, Codable {
        public var a: Int
        public var b: Int
        public var endpoint0: WorldPoint
        public var endpoint1: WorldPoint

        public func other(than polygon: Int) -> Int? {
            if polygon == a { return b }
            if polygon == b { return a }
            return nil
        }
    }

    public var polygons: [Polygon]
    public var portals: [Portal]
    public var sourceRevision: Int
    /// Resolution of the conservative walkability field used by the bake.
    /// It is retained only for deterministic corridor validation, never for
    /// cell-by-cell actor movement.
    public var sourceCellSize: Double

    public init(
        polygons: [Polygon],
        portals: [Portal],
        sourceRevision: Int = 0,
        sourceCellSize: Double = 0.05
    ) {
        self.polygons = polygons
        self.portals = portals
        self.sourceRevision = sourceRevision
        self.sourceCellSize = sourceCellSize
    }

    public func polygon(containing point: WorldPoint, maximumSnap: Double) -> Int? {
        if let exact = polygons.first(where: { $0.contains(point) }) { return exact.id }
        return polygons.compactMap { polygon -> (Int, Double)? in
            let closest = polygon.closestPoint(to: point)
            let distance = closest.planarDistance(to: point)
            return distance <= maximumSnap ? (polygon.id, distance) : nil
        }.min {
            if abs($0.1 - $1.1) > 1e-9 { return $0.1 < $1.1 }
            return $0.0 < $1.0
        }?.0
    }

    public func portal(from: Int, to: Int) -> Portal? {
        portals.first { ($0.a == from && $0.b == to) || ($0.a == to && $0.b == from) }
    }

    public func neighbours(of polygon: Int) -> [(id: Int, portal: Portal)] {
        portals.compactMap { portal in
            portal.other(than: polygon).map { ($0, portal) }
        }.sorted { $0.id < $1.id }
    }
}

/// Navigation bake for the current planar level format. The permanent modular
/// authoring grid and object footprints produce this dense walkability field;
/// runtime route queries consume continuous rectangles and shared portals.
public enum NavigationMeshBaker {
    public static func bake(from grid: NavGrid, sourceRevision: Int = 0) -> BakedNavigationMesh {
        guard grid.columns > 0, grid.rows > 0 else {
            return BakedNavigationMesh(
                polygons: [], portals: [], sourceRevision: sourceRevision,
                sourceCellSize: grid.cellSize
            )
        }

        var used = [Bool](repeating: false, count: grid.cellCount)
        var polygons: [BakedNavigationMesh.Polygon] = []
        func index(_ column: Int, _ row: Int) -> Int { row * grid.columns + column }

        // Stable greedy rectangle decomposition. It drastically reduces the
        // 75k-cell office field while preserving every eroded walkability edge.
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                guard grid.isWalkable(.init(column: column, row: row)),
                      !used[index(column, row)] else { continue }

                var width = 1
                while column + width < grid.columns,
                      grid.isWalkable(.init(column: column + width, row: row)),
                      !used[index(column + width, row)] {
                    width += 1
                }

                var height = 1
                heightLoop: while row + height < grid.rows {
                    for x in column..<(column + width) {
                        guard grid.isWalkable(.init(column: x, row: row + height)),
                              !used[index(x, row + height)] else { break heightLoop }
                    }
                    height += 1
                }

                var clearance = Double.greatestFiniteMagnitude
                for z in row..<(row + height) {
                    for x in column..<(column + width) {
                        used[index(x, z)] = true
                        clearance = min(clearance, grid.clearance(at: .init(column: x, row: z)))
                    }
                }

                polygons.append(.init(
                    id: polygons.count,
                    minX: grid.minX + Double(column) * grid.cellSize,
                    maxX: grid.minX + Double(column + width) * grid.cellSize,
                    minZ: grid.minZ + Double(row) * grid.cellSize,
                    maxZ: grid.minZ + Double(row + height) * grid.cellSize,
                    clearance: clearance
                ))
            }
        }

        var portals: [BakedNavigationMesh.Portal] = []
        let epsilon = grid.cellSize * 0.01
        for a in polygons.indices {
            for b in (a + 1)..<polygons.count {
                let lhs = polygons[a]
                let rhs = polygons[b]
                if abs(lhs.maxX - rhs.minX) <= epsilon || abs(rhs.maxX - lhs.minX) <= epsilon {
                    let z0 = max(lhs.minZ, rhs.minZ)
                    let z1 = min(lhs.maxZ, rhs.maxZ)
                    if z1 - z0 > epsilon {
                        let x = abs(lhs.maxX - rhs.minX) <= epsilon ? lhs.maxX : rhs.maxX
                        portals.append(.init(
                            a: lhs.id, b: rhs.id,
                            endpoint0: WorldPoint(x: x, y: 0, z: z0),
                            endpoint1: WorldPoint(x: x, y: 0, z: z1)
                        ))
                    }
                } else if abs(lhs.maxZ - rhs.minZ) <= epsilon || abs(rhs.maxZ - lhs.minZ) <= epsilon {
                    let x0 = max(lhs.minX, rhs.minX)
                    let x1 = min(lhs.maxX, rhs.maxX)
                    if x1 - x0 > epsilon {
                        let z = abs(lhs.maxZ - rhs.minZ) <= epsilon ? lhs.maxZ : rhs.maxZ
                        portals.append(.init(
                            a: lhs.id, b: rhs.id,
                            endpoint0: WorldPoint(x: x0, y: 0, z: z),
                            endpoint1: WorldPoint(x: x1, y: 0, z: z)
                        ))
                    }
                }
            }
        }

        return BakedNavigationMesh(
            polygons: polygons,
            portals: portals,
            sourceRevision: sourceRevision,
            sourceCellSize: grid.cellSize
        )
    }
}

public enum PolygonPathFinder {
    public static func findPath(
        from start: WorldPoint,
        to destination: WorldPoint,
        in mesh: BakedNavigationMesh,
        character: CharacterProfile = .standard
    ) -> Result<PathResult, PathFailure> {
        guard let startID = mesh.polygon(containing: start, maximumSnap: 1.5) else {
            return .failure(.startNotOnGrid)
        }
        guard let goalID = mesh.polygon(containing: destination, maximumSnap: 2.0) else {
            return .failure(.destinationNotReachable)
        }
        let resolvedStart = mesh.polygons[startID].closestPoint(to: start)
        let resolvedGoal = mesh.polygons[goalID].closestPoint(to: destination)
        if startID == goalID {
            return .success(.init(
                waypoints: [resolvedGoal],
                length: resolvedStart.planarDistance(to: resolvedGoal)
            ))
        }
        guard let corridor = corridor(from: startID, to: goalID, in: mesh, character: character) else {
            return .failure(.noRoute)
        }
        let pulled = funnel(
            start: resolvedStart,
            goal: resolvedGoal,
            corridor: corridor,
            mesh: mesh
        )
        // A rectangle decomposition can contain T-junctions. Validate the
        // pulled string against the actual polygon union; if a degenerate
        // portal ordering would cut a corner, fall back to portal midpoints
        // and greedily string-pull only proven-visible spans.
        let waypoints = pathStaysOnMesh(start: resolvedStart, waypoints: pulled, mesh: mesh)
            ? pulled
            : conservativeStringPull(
                start: resolvedStart, goal: resolvedGoal,
                corridor: corridor, mesh: mesh
            )
        var length = 0.0
        var previous = resolvedStart
        for point in waypoints {
            length += previous.planarDistance(to: point)
            previous = point
        }
        return .success(.init(waypoints: waypoints, length: length))
    }

    private static func corridor(
        from start: Int,
        to goal: Int,
        in mesh: BakedNavigationMesh,
        character: CharacterProfile
    ) -> [Int]? {
        var open: [(id: Int, f: Double, serial: Int)] = [(start, 0, 0)]
        var serial = 1
        var cost = [Int: Double](minimumCapacity: mesh.polygons.count)
        var parent = [Int: Int](minimumCapacity: mesh.polygons.count)
        cost[start] = 0

        while !open.isEmpty {
            open.sort {
                if abs($0.f - $1.f) > 1e-9 { return $0.f < $1.f }
                if $0.id != $1.id { return $0.id < $1.id }
                return $0.serial < $1.serial
            }
            let current = open.removeFirst().id
            if current == goal {
                var result = [goal]
                var cursor = goal
                while let previous = parent[cursor] {
                    result.append(previous)
                    cursor = previous
                }
                return result.reversed()
            }

            let currentCost = cost[current] ?? .greatestFiniteMagnitude
            for neighbour in mesh.neighbours(of: current) {
                let from = mesh.polygons[current]
                let to = mesh.polygons[neighbour.id]
                let desired = max(character.preferredWallClearance, 0.001)
                let deficit = max(0, desired - to.clearance) / desired
                let step = from.center.planarDistance(to: to.center)
                    * (1 + character.wallAvoidanceWeight * deficit * deficit)
                let tentative = currentCost + step
                if tentative + 1e-9 < (cost[neighbour.id] ?? .greatestFiniteMagnitude) {
                    cost[neighbour.id] = tentative
                    parent[neighbour.id] = current
                    let heuristic = to.center.planarDistance(to: mesh.polygons[goal].center)
                    open.append((neighbour.id, tentative + heuristic, serial))
                    serial += 1
                }
            }
        }
        return nil
    }

    private struct OrientedPortal {
        var left: WorldPoint
        var right: WorldPoint
    }

    private static func funnel(
        start: WorldPoint,
        goal: WorldPoint,
        corridor: [Int],
        mesh: BakedNavigationMesh
    ) -> [WorldPoint] {
        var portals = [OrientedPortal(left: start, right: start)]
        for index in 0..<(corridor.count - 1) {
            guard let portal = mesh.portal(from: corridor[index], to: corridor[index + 1]) else { continue }
            let direction = mesh.polygons[corridor[index + 1]].center - mesh.polygons[corridor[index]].center
            let midpoint = (portal.endpoint0 + portal.endpoint1) * 0.5
            let side0 = cross(direction, portal.endpoint0 - midpoint)
            let oriented = side0 >= 0
                ? OrientedPortal(left: portal.endpoint0, right: portal.endpoint1)
                : OrientedPortal(left: portal.endpoint1, right: portal.endpoint0)
            portals.append(oriented)
        }
        portals.append(.init(left: goal, right: goal))

        var result: [WorldPoint] = []
        var apex = portals[0].left
        var left = apex
        var right = apex
        var apexIndex = 0
        var leftIndex = 0
        var rightIndex = 0
        var index = 1

        while index < portals.count {
            let nextLeft = portals[index].left
            let nextRight = portals[index].right
            if area2(apex, right, nextRight) <= 0 {
                if pointsEqual(apex, right) || area2(apex, left, nextRight) > 0 {
                    right = nextRight
                    rightIndex = index
                } else {
                    result.append(left)
                    apex = left
                    apexIndex = leftIndex
                    left = apex
                    right = apex
                    leftIndex = apexIndex
                    rightIndex = apexIndex
                    index = apexIndex + 1
                    continue
                }
            }
            if area2(apex, left, nextLeft) >= 0 {
                if pointsEqual(apex, left) || area2(apex, right, nextLeft) < 0 {
                    left = nextLeft
                    leftIndex = index
                } else {
                    result.append(right)
                    apex = right
                    apexIndex = rightIndex
                    left = apex
                    right = apex
                    leftIndex = apexIndex
                    rightIndex = apexIndex
                    index = apexIndex + 1
                    continue
                }
            }
            index += 1
        }

        if result.last.map({ !pointsEqual($0, goal) }) ?? true { result.append(goal) }
        return result
    }

    private static func area2(_ a: WorldPoint, _ b: WorldPoint, _ c: WorldPoint) -> Double {
        (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
    }

    private static func cross(_ a: WorldPoint, _ b: WorldPoint) -> Double {
        a.x * b.z - a.z * b.x
    }

    private static func pointsEqual(_ a: WorldPoint, _ b: WorldPoint) -> Bool {
        abs(a.x - b.x) <= 1e-9 && abs(a.z - b.z) <= 1e-9
    }

    private static func conservativeStringPull(
        start: WorldPoint,
        goal: WorldPoint,
        corridor: [Int],
        mesh: BakedNavigationMesh
    ) -> [WorldPoint] {
        var candidates: [WorldPoint] = []
        for index in 0..<(corridor.count - 1) {
            guard let portal = mesh.portal(from: corridor[index], to: corridor[index + 1]) else {
                continue
            }
            candidates.append((portal.endpoint0 + portal.endpoint1) * 0.5)
        }
        candidates.append(goal)

        var result: [WorldPoint] = []
        var anchor = start
        var cursor = 0
        while cursor < candidates.count {
            var farthest = cursor
            for candidateIndex in cursor..<candidates.count {
                if segmentStaysOnMesh(from: anchor, to: candidates[candidateIndex], mesh: mesh) {
                    farthest = candidateIndex
                }
            }
            let point = candidates[farthest]
            if !pointsEqual(anchor, point) { result.append(point) }
            anchor = point
            cursor = farthest + 1
        }
        return result
    }

    private static func pathStaysOnMesh(
        start: WorldPoint,
        waypoints: [WorldPoint],
        mesh: BakedNavigationMesh
    ) -> Bool {
        var previous = start
        for point in waypoints {
            guard segmentStaysOnMesh(from: previous, to: point, mesh: mesh) else { return false }
            previous = point
        }
        return true
    }

    private static func segmentStaysOnMesh(
        from start: WorldPoint,
        to end: WorldPoint,
        mesh: BakedNavigationMesh
    ) -> Bool {
        let distance = start.planarDistance(to: end)
        let resolution = max(0.001, mesh.sourceCellSize * 0.5)
        let steps = max(1, Int((distance / resolution).rounded(.up)))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let point = (start + (end - start) * t).onFloorPlane
            guard mesh.polygon(containing: point, maximumSnap: resolution * 0.02) != nil else {
                return false
            }
        }
        return true
    }
}
