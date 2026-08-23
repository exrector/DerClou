import GameplayKit
import HeistCore

/// Apple-native local steering isolated from RealityKit presentation.
///
/// `GKAgent2D` is intentionally created, advanced, sampled and destroyed inside
/// one call. It never owns an entity transform and never observes render-frame
/// delta time. The returned polyline is immutable mission data, so replay and
/// arbitrary timeline seeking remain functions of the committed task.
public enum GameplayKitSteeringAdapter {
    public struct Configuration: Sendable, Equatable {
        public var fixedStep: Double
        public var maximumDurationMultiplier: Double
        public var terminalJoinDistance: Double
        public var bodySafetyMargin: Double
        public var pathRadius: Double
        public var sampleSpacing: Double

        public init(
            fixedStep: Double = 1.0 / 60.0,
            maximumDurationMultiplier: Double = 3,
            terminalJoinDistance: Double = 0.4,
            bodySafetyMargin: Double = 0.08,
            pathRadius: Double = 1.1,
            sampleSpacing: Double = 0.06
        ) {
            self.fixedStep = fixedStep
            self.maximumDurationMultiplier = maximumDurationMultiplier
            self.terminalJoinDistance = terminalJoinDistance
            self.bodySafetyMargin = bodySafetyMargin
            self.pathRadius = pathRadius
            self.sampleSpacing = sampleSpacing
        }

        public static let production = Configuration()
    }

    public enum Rejection: String, Sendable, Equatable {
        case invalidInput
        case leftWalkableSpace
        case violatedBodyClearance
        case stalled
        case didNotReachDestination
    }

    public struct Result: Sendable, Equatable {
        public var path: PathResult?
        public var rejection: Rejection?
        public var fixedSteps: Int

        public init(path: PathResult?, rejection: Rejection?, fixedSteps: Int) {
            self.path = path
            self.rejection = rejection
            self.fixedSteps = fixedSteps
        }
    }

    /// Refines an already legal global path. Only stationary right-of-way
    /// actors are handed to `GKGoal(toAvoid:)`; moving/moving priority remains
    /// the job of `TimedTrajectoryPlanner`, which reasons in absolute mission
    /// time before this local curve is sampled.
    public static func refine(
        request: NavigationPlanRequest,
        path: PathResult,
        grid: NavGrid,
        configuration: Configuration = .production
    ) -> Result {
        let source = normalizedPoints(start: request.start, path: path)
        guard source.count >= 2,
              request.character.walkSpeed > 0,
              request.character.acceleration > 0,
              configuration.fixedStep > 0 else {
            return Result(path: nil, rejection: .invalidInput, fixedSteps: 0)
        }

        let stationaryReservations = request.reservedTrajectories
            .filter { ownsRightOfWay($0, over: request) && $0.isStationary }
            .compactMap { reservation -> (ReservedAgentTrajectory, WorldPoint)? in
                guard let position = reservation.position(at: request.startedAt) else { return nil }
                return (reservation, position)
            }

        let mover = GKAgent2D()
        mover.position = source[0].gameplayKitPoint
        mover.rotation = Float(request.initialFacing * .pi / 180)
        mover.radius = Float(request.character.radius)
        mover.mass = 1
        mover.maxSpeed = Float(request.character.walkSpeed)
        mover.maxAcceleration = Float(request.character.acceleration)

        let target = GKAgent2D()
        target.position = source[source.count - 1].gameplayKitPoint

        let pathPoints = source.map(\.gameplayKitPoint)
        let steeringPath = GKPath(
            points: pathPoints,
            radius: Float(max(configuration.pathRadius, request.character.radius * 2)),
            cyclical: false
        )
        let follow = GKGoal(
            toFollow: steeringPath,
            maxPredictionTime: 0.8,
            forward: true
        )
        let stayOn = GKGoal(toStayOn: steeringPath, maxPredictionTime: 0.6)
        let seek = GKGoal(toSeekAgent: target)
        let targetSpeed = GKGoal(toReachTargetSpeed: Float(request.character.walkSpeed))

        let blockerAgents: [(agent: GKAgent2D, position: WorldPoint, radius: Double)] =
            stationaryReservations.map { reservation, position in
                let agent = GKAgent2D()
                agent.position = position.gameplayKitPoint
                agent.radius = Float(reservation.radius + configuration.bodySafetyMargin)
                agent.maxSpeed = 0
                agent.maxAcceleration = 0
                return (agent, position, reservation.radius)
            }

        let behavior = GKBehavior()
        behavior.setWeight(1.5, for: follow)
        behavior.setWeight(0.25, for: stayOn)
        behavior.setWeight(0.45, for: seek)
        behavior.setWeight(0.4, for: targetSpeed)
        if !blockerAgents.isEmpty {
            let avoid = GKGoal(
                toAvoid: blockerAgents.map(\.agent),
                maxPredictionTime: 1.2
            )
            behavior.setWeight(8, for: avoid)
        }
        mover.behavior = behavior

        let directTravelTime = max(
            configuration.fixedStep,
            path.length / request.character.walkSpeed
        )
        let maximumDuration = directTravelTime * configuration.maximumDurationMultiplier + 2
        let maximumSteps = max(1, Int((maximumDuration / configuration.fixedStep).rounded(.up)))
        let terminalDistance = max(
            configuration.terminalJoinDistance,
            request.character.walkSpeed * 0.25
        )
        let destination = source[source.count - 1]
        let sampleSpacing = max(configuration.sampleSpacing, grid.cellSize)
        var sampled = [source[0]]
        var previous = source[0]
        var lastSample = source[0]
        var stagnantSteps = 0

        for step in 1...maximumSteps {
            mover.update(deltaTime: configuration.fixedStep)
            let current = WorldPoint(gameplayKitPoint: mover.position)

            guard grid.isWalkable(grid.cell(at: current)),
                  PathFinder.hasLineOfSight(from: previous, to: current, in: grid) else {
                return Result(path: nil, rejection: .leftWalkableSpace, fixedSteps: step)
            }
            guard clearsBodies(
                current,
                moverRadius: request.character.radius,
                blockers: blockerAgents,
                margin: configuration.bodySafetyMargin
            ) else {
                return Result(path: nil, rejection: .violatedBodyClearance, fixedSteps: step)
            }

            if current.planarDistance(to: previous) < 1e-5 {
                stagnantSteps += 1
            } else {
                stagnantSteps = 0
            }
            if stagnantSteps > 120 {
                return Result(path: nil, rejection: .stalled, fixedSteps: step)
            }

            if current.planarDistance(to: lastSample) >= sampleSpacing {
                sampled.append(current)
                lastSample = current
            }
            previous = current

            if current.planarDistance(to: destination) <= terminalDistance,
               PathFinder.hasLineOfSight(from: current, to: destination, in: grid),
               terminalSegmentClearsBodies(
                    from: current,
                    to: destination,
                    moverRadius: request.character.radius,
                    blockers: blockerAgents,
                    margin: configuration.bodySafetyMargin
               ) {
                if sampled.last?.planarDistance(to: current) ?? 0 > 1e-5 {
                    sampled.append(current)
                }
                if sampled.last?.planarDistance(to: destination) ?? 0 > 1e-5 {
                    sampled.append(destination)
                }
                return Result(
                    path: pathResult(points: sampled),
                    rejection: nil,
                    fixedSteps: step
                )
            }
        }

        return Result(path: nil, rejection: .didNotReachDestination, fixedSteps: maximumSteps)
    }

    private static func ownsRightOfWay(
        _ reservation: ReservedAgentTrajectory,
        over request: NavigationPlanRequest
    ) -> Bool {
        guard !reservation.isStationary else { return true }
        switch reservation.committedAt {
        case .some(let time) where time < request.trajectoryCommittedAt:
            return true
        case .some(let time) where time == request.trajectoryCommittedAt:
            return reservation.tieBreakerPriority < request.tieBreakerPriority
                || (reservation.tieBreakerPriority == request.tieBreakerPriority
                    && reservation.actorID < request.actorID)
        default:
            return false
        }
    }

    private static func normalizedPoints(start: WorldPoint, path: PathResult) -> [WorldPoint] {
        ([start] + path.waypoints).reduce(into: []) { points, point in
            let floorPoint = point.onFloorPlane
            if points.last?.planarDistance(to: floorPoint) ?? .infinity > 1e-6 {
                points.append(floorPoint)
            }
        }
    }

    private static func clearsBodies(
        _ point: WorldPoint,
        moverRadius: Double,
        blockers: [(agent: GKAgent2D, position: WorldPoint, radius: Double)],
        margin: Double
    ) -> Bool {
        blockers.allSatisfy {
            point.planarDistance(to: $0.position) + 1e-5
                >= moverRadius + $0.radius + margin
        }
    }

    private static func terminalSegmentClearsBodies(
        from: WorldPoint,
        to: WorldPoint,
        moverRadius: Double,
        blockers: [(agent: GKAgent2D, position: WorldPoint, radius: Double)],
        margin: Double
    ) -> Bool {
        blockers.allSatisfy {
            distanceFromPoint($0.position, toSegmentFrom: from, to: to) + 1e-5
                >= moverRadius + $0.radius + margin
        }
    }

    private static func distanceFromPoint(
        _ point: WorldPoint,
        toSegmentFrom start: WorldPoint,
        to end: WorldPoint
    ) -> Double {
        let segment = end - start
        let lengthSquared = segment.x * segment.x + segment.z * segment.z
        guard lengthSquared > 1e-12 else { return point.planarDistance(to: start) }
        let relative = point - start
        let projection = max(0, min(1,
            (relative.x * segment.x + relative.z * segment.z) / lengthSquared
        ))
        return point.planarDistance(to: start + segment * projection)
    }

    private static func pathResult(points: [WorldPoint]) -> PathResult {
        let length = zip(points, points.dropFirst()).reduce(0) {
            $0 + $1.0.planarDistance(to: $1.1)
        }
        return PathResult(waypoints: Array(points.dropFirst()), length: length)
    }
}

private extension WorldPoint {
    var gameplayKitPoint: SIMD2<Float> { SIMD2(Float(x), Float(z)) }

    init(gameplayKitPoint: SIMD2<Float>) {
        self.init(x: Double(gameplayKitPoint.x), y: 0, z: Double(gameplayKitPoint.y))
    }
}

/// Worker entry point that preserves the HeistCore response contract. A
/// rejected GameplayKit curve is a safe optimization miss, never a failed
/// semantic route.
public enum AppleNavigationPlanner {
    public static func resolve(_ request: NavigationPlanRequest) -> NavigationPlanResponse {
        var response = NavigationPlanner.resolve(request)
        guard case .success(let path) = response.result else { return response }
        let grid: NavGrid? = request.avoidanceGrid ?? {
            if case .grid(let grid) = request.topology { return grid }
            return nil
        }()
        guard let grid else { return response }

        let steering = GameplayKitSteeringAdapter.refine(
            request: request,
            path: path,
            grid: grid
        )
        if let refined = steering.path {
            response.result = .success(refined)
        }
        return response
    }
}
