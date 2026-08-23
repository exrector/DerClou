import Foundation

public struct TimedAgentPosition: Sendable, Equatable {
    public var missionTime: Double
    public var position: WorldPoint

    public init(missionTime: Double, position: WorldPoint) {
        self.missionTime = missionTime
        self.position = position
    }
}

/// Immutable future corridor owned by an actor whose command was committed
/// before the route currently being planned.
public struct ReservedAgentTrajectory: Sendable, Equatable {
    public enum Motion: Sendable, Equatable {
        case stationary(WorldPoint)
        case navigation(AgentNavigationTask)
        case patrol(route: PatrolRoute, phaseAtStart: Double, missionStart: Double)
        case samples([TimedAgentPosition])
    }

    public var actorID: String
    public var radius: Double
    public var committedAt: Double?
    public var tieBreakerPriority: Int
    public var motion: Motion

    public init(
        actorID: String,
        radius: Double,
        committedAt: Double?,
        tieBreakerPriority: Int,
        samples: [TimedAgentPosition]
    ) {
        self.actorID = actorID
        self.radius = radius
        self.committedAt = committedAt
        self.tieBreakerPriority = tieBreakerPriority
        self.motion = .samples(samples.sorted { $0.missionTime < $1.missionTime })
    }

    public init(
        actorID: String,
        radius: Double,
        committedAt: Double?,
        tieBreakerPriority: Int,
        motion: Motion
    ) {
        self.actorID = actorID
        self.radius = radius
        self.committedAt = committedAt
        self.tieBreakerPriority = tieBreakerPriority
        self.motion = motion
    }

    public var isStationary: Bool {
        switch motion {
        case .stationary:
            return true
        case .navigation(let task):
            return task.length < 0.01 || task.isBlocked
        case .patrol:
            return false
        case .samples(let samples):
            guard let first = samples.first, let last = samples.last else { return true }
            return first.position.planarDistance(to: last.position) < 0.01
        }
    }

    public func position(at missionTime: Double) -> WorldPoint? {
        switch motion {
        case .stationary(let position):
            return position
        case .navigation(let task):
            return task.state(at: missionTime).position
        case .patrol(let route, let phaseAtStart, let missionStart):
            return route.state(at: phaseAtStart + max(0, missionTime - missionStart)).position
        case .samples(let samples):
            return Self.interpolatedPosition(in: samples, at: missionTime)
        }
    }

    private static func interpolatedPosition(
        in samples: [TimedAgentPosition],
        at missionTime: Double
    ) -> WorldPoint? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if missionTime <= first.missionTime { return first.position }
        if missionTime >= last.missionTime { return last.position }
        for index in 1..<samples.count where missionTime <= samples[index].missionTime {
            let left = samples[index - 1]
            let right = samples[index]
            let duration = right.missionTime - left.missionTime
            let progress = duration > 0 ? (missionTime - left.missionTime) / duration : 1
            return (left.position + (right.position - left.position) * progress).onFloorPlane
        }
        return last.position
    }
}

/// Time-aware refinement used for a newly assigned player route. It never asks
/// an older actor to yield. Conflicts become a small set of predicted meeting
/// points, then one stable path is solved before movement begins.
public enum TimedTrajectoryPlanner {
    public static func refine(
        request: NavigationPlanRequest,
        initialPath: PathResult,
        in baseGrid: NavGrid,
        sampleInterval: Double = 0.15,
        maximumPasses: Int = 3
    ) -> PathResult {
        let reservations = request.reservedTrajectories.filter {
            ownsRightOfWay($0, over: request)
        }
        guard !reservations.isEmpty else {
            return PathFinder.minimumLinkPath(from: request.start, path: initialPath, in: baseGrid)
        }

        var blockers: [WorldBox] = reservations.compactMap { reservation in
            guard reservation.isStationary,
                  let position = reservation.position(at: request.startedAt) else {
                return nil
            }
            return bodyBox(at: position, radius: reservation.radius, height: request.character.height)
        }
        var grid = baseGrid.blockingTransientObstacles(
            blockers,
            characterRadius: request.character.radius + 0.08,
            characterHeight: request.character.height
        )
        var path = PathFinder.findPath(
            from: request.start,
            to: request.destination,
            in: grid,
            character: request.character
        ).successValue ?? initialPath

        for _ in 0..<maximumPasses {
            let task = AgentNavigationTask(
                goal: .move(destination: request.destination),
                start: request.start,
                path: path,
                startedAt: request.startedAt,
                speed: request.character.walkSpeed,
                initialFacing: request.initialFacing,
                worldRevision: request.worldRevision,
                acceleration: request.character.acceleration,
                deceleration: request.character.deceleration,
                maximumTurnRateDegrees: request.character.maximumTurnRateDegrees
            )
            let endTime = request.startedAt + task.duration
            var newBlockers: [WorldBox] = []

            for reservation in reservations where !reservation.isStationary {
                var time = request.startedAt
                while time <= endTime + 1e-9 {
                    let moving = task.state(at: time).position
                    if let reserved = reservation.position(at: time),
                       moving.planarDistance(to: reserved)
                        < request.character.radius + reservation.radius + 0.08 {
                        newBlockers.append(bodyBox(
                            at: reserved,
                            radius: reservation.radius,
                            height: request.character.height
                        ))
                        break
                    }
                    time += sampleInterval
                }
            }

            guard !newBlockers.isEmpty else {
                return PathFinder.minimumLinkPath(from: request.start, path: path, in: grid)
            }
            blockers.append(contentsOf: newBlockers)
            grid = baseGrid.blockingTransientObstacles(
                blockers,
                characterRadius: request.character.radius + 0.08,
                characterHeight: request.character.height
            )
            guard case .success(let replacement) = PathFinder.findPath(
                from: request.start,
                to: request.destination,
                in: grid,
                character: request.character
            ) else { break }
            path = replacement
        }
        return PathFinder.minimumLinkPath(from: request.start, path: path, in: grid)
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

    private static func bodyBox(at position: WorldPoint, radius: Double, height: Double) -> WorldBox {
        WorldBox(
            center: WorldPoint(x: position.x, y: height / 2, z: position.z),
            width: radius * 2,
            height: height,
            depth: radius * 2,
            surface: .fabric,
            sourceID: "reserved-agent"
        )
    }
}

private extension Result where Success == PathResult, Failure == PathFailure {
    var successValue: PathResult? {
        if case .success(let value) = self { return value }
        return nil
    }
}
