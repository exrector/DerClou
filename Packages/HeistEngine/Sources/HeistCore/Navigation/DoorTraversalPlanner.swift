import Foundation

public struct DoorTraversalGate: Sendable, Equatable {
    public var id: String
    public var box: WorldBox

    public init(id: String, box: WorldBox) {
        self.id = id
        self.box = box
    }
}

public struct DoorRouteCrossing: Sendable, Equatable {
    public var gate: DoorTraversalGate
    public var approachSide: ApproachPointSolver.Side
    public var distanceAlongRoute: Double
}

/// Finds smart-object gates crossed by an otherwise geometric route. Doors are
/// portals with actions, not permanent navmesh walls.
public enum DoorTraversalPlanner {
    public static func firstCrossing(
        path: PathResult,
        gates: [DoorTraversalGate]
    ) -> DoorRouteCrossing? {
        var candidates: [DoorRouteCrossing] = []
        var travelled = 0.0
        for (start, end) in zip(path.waypoints, path.waypoints.dropFirst()) {
            let length = start.planarDistance(to: end)
            for gate in gates {
                guard let fraction = WorldSegmentIntersection.entryFraction(
                    from: start, to: end, box: gate.box, expansion: 0.02
                ) else { continue }
                candidates.append(DoorRouteCrossing(
                    gate: gate,
                    approachSide: side(of: start, relativeTo: gate.box),
                    distanceAlongRoute: travelled + length * fraction
                ))
            }
            travelled += length
        }
        return candidates.min {
            if abs($0.distanceAlongRoute - $1.distanceAlongRoute) > 1e-9 {
                return $0.distanceAlongRoute < $1.distanceAlongRoute
            }
            return $0.gate.id < $1.gate.id
        }
    }

    public static func side(
        of point: WorldPoint,
        relativeTo box: WorldBox
    ) -> ApproachPointSolver.Side {
        let yaw = box.yaw * .pi / 180
        let localZ = sin(yaw) * (point.x - box.center.x)
            + cos(yaw) * (point.z - box.center.z)
        return localZ >= 0 ? .front : .back
    }
}
