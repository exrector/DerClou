import Foundation

/// Immutable input to one path query.
///
/// A request owns the exact topology revision and character profile it was
/// planned against. Runtime code may therefore resolve it away from the render
/// actor and discard the answer if the world changed while it was in flight.
public struct NavigationPlanRequest: Sendable, Equatable {
    public var id: UInt64
    public var actorID: String
    public var worldRevision: Int
    public var start: WorldPoint
    public var destination: WorldPoint
    public var character: CharacterProfile
    public var topology: NavigationTopologySnapshot
    public var startedAt: Double
    public var initialFacing: Double
    public var trajectoryCommittedAt: Double
    public var tieBreakerPriority: Int
    public var avoidanceGrid: NavGrid?
    public var reservedTrajectories: [ReservedAgentTrajectory]

    public init(
        id: UInt64,
        actorID: String,
        worldRevision: Int,
        start: WorldPoint,
        destination: WorldPoint,
        character: CharacterProfile,
        topology: NavigationTopologySnapshot,
        startedAt: Double = 0,
        initialFacing: Double = 0,
        trajectoryCommittedAt: Double = 0,
        tieBreakerPriority: Int = 50,
        avoidanceGrid: NavGrid? = nil,
        reservedTrajectories: [ReservedAgentTrajectory] = []
    ) {
        self.id = id
        self.actorID = actorID
        self.worldRevision = worldRevision
        self.start = start
        self.destination = destination
        self.character = character
        self.topology = topology
        self.startedAt = startedAt
        self.initialFacing = initialFacing
        self.trajectoryCommittedAt = trajectoryCommittedAt
        self.tieBreakerPriority = tieBreakerPriority
        self.avoidanceGrid = avoidanceGrid
        self.reservedTrajectories = reservedTrajectories
    }
}

/// Read-only topology consumed by planning workers.
///
/// The enum is an intentional compatibility seam. Production requests use the
/// baked polygon topology; the dense grid case remains useful for bake
/// validation and deterministic regression tests without changing taps, goals,
/// replay commands, or actor locomotion.
public enum NavigationTopologySnapshot: Sendable, Equatable {
    case grid(NavGrid)
    case polygon(BakedNavigationMesh)
}

public struct NavigationPlanResponse: Sendable, Equatable {
    public var requestID: UInt64
    public var actorID: String
    public var worldRevision: Int
    public var result: Result<PathResult, PathFailure>

    public init(
        requestID: UInt64,
        actorID: String,
        worldRevision: Int,
        result: Result<PathResult, PathFailure>
    ) {
        self.requestID = requestID
        self.actorID = actorID
        self.worldRevision = worldRevision
        self.result = result
    }
}

/// Pure planner entry point. It has no UI, RealityKit, clock, or actor state.
public enum NavigationPlanner {
    public static func resolve(_ request: NavigationPlanRequest) -> NavigationPlanResponse {
        let result: Result<PathResult, PathFailure>
        switch request.topology {
        case .grid(let grid):
            result = PathFinder.findPath(
                from: request.start,
                to: request.destination,
                in: grid,
                character: request.character
            )
        case .polygon(let mesh):
            result = PolygonPathFinder.findPath(
                from: request.start,
                to: request.destination,
                in: mesh,
                character: request.character
            )
        }
        let refined: Result<PathResult, PathFailure>
        if case .success(let path) = result,
           let grid = request.avoidanceGrid,
           !request.reservedTrajectories.isEmpty {
            refined = .success(TimedTrajectoryPlanner.refine(
                request: request,
                initialPath: path,
                in: grid
            ))
        } else {
            refined = result
        }
        return NavigationPlanResponse(
            requestID: request.id,
            actorID: request.actorID,
            worldRevision: request.worldRevision,
            result: refined
        )
    }
}

public struct NavigationApproachPlanRequest: Sendable, Equatable {
    public var id: UInt64
    public var actorID: String
    public var worldRevision: Int
    public var start: WorldPoint
    public var objectBox: WorldBox
    public var character: CharacterProfile
    public var topology: NavigationTopologySnapshot
    public var allowedSides: Set<ApproachPointSolver.Side>?

    public init(
        id: UInt64,
        actorID: String,
        worldRevision: Int,
        start: WorldPoint,
        objectBox: WorldBox,
        character: CharacterProfile,
        topology: NavigationTopologySnapshot,
        allowedSides: Set<ApproachPointSolver.Side>? = nil
    ) {
        self.id = id
        self.actorID = actorID
        self.worldRevision = worldRevision
        self.start = start
        self.objectBox = objectBox
        self.character = character
        self.topology = topology
        self.allowedSides = allowedSides
    }
}

public struct NavigationApproachRoute: Sendable, Equatable {
    public var slot: ApproachPointSolver.Slot
    public var path: PathResult

    public init(slot: ApproachPointSolver.Slot, path: PathResult) {
        self.slot = slot
        self.path = path
    }
}

public struct NavigationApproachPlanResponse: Sendable, Equatable {
    public var requestID: UInt64
    public var actorID: String
    public var worldRevision: Int
    public var route: NavigationApproachRoute?
}

public extension NavigationPlanner {
    static func resolveApproach(
        _ request: NavigationApproachPlanRequest
    ) -> NavigationApproachPlanResponse {
        let route: NavigationApproachRoute?
        switch request.topology {
        case .grid(let grid):
            route = ApproachPointSolver.slots(for: request.objectBox, grid: grid)
                .filter { request.allowedSides?.contains($0.side) ?? true }
                .compactMap { slot in
                    guard case .success(let path) = PathFinder.findPath(
                        from: request.start,
                        to: slot.position,
                        in: grid,
                        character: request.character
                    ) else { return nil }
                    return NavigationApproachRoute(slot: slot, path: path)
                }
                .min { lhs, rhs in
                    if abs(lhs.path.length - rhs.path.length) > 1e-9 {
                        return lhs.path.length < rhs.path.length
                    }
                    return lhs.slot.side.rawValue < rhs.slot.side.rawValue
                }
        case .polygon(let mesh):
            route = ApproachPointSolver.slots(for: request.objectBox, mesh: mesh)
                .filter { request.allowedSides?.contains($0.side) ?? true }
                .compactMap { slot in
                    guard case .success(let path) = PolygonPathFinder.findPath(
                        from: request.start,
                        to: slot.position,
                        in: mesh,
                        character: request.character
                    ) else { return nil }
                    return NavigationApproachRoute(slot: slot, path: path)
                }
                .min { lhs, rhs in
                    if abs(lhs.path.length - rhs.path.length) > 1e-9 {
                        return lhs.path.length < rhs.path.length
                    }
                    return lhs.slot.side.rawValue < rhs.slot.side.rawValue
                }
        }
        return NavigationApproachPlanResponse(
            requestID: request.id,
            actorID: request.actorID,
            worldRevision: request.worldRevision,
            route: route
        )
    }
}
