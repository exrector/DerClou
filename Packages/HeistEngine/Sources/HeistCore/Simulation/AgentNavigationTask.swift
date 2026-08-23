import Foundation

public extension AgentGoal {
    /// Concrete point for goals that own a destination. Patrol remains a
    /// separate authored routine and therefore has no single destination.
    var navigationDestination: WorldPoint? {
        switch self {
        case .move(let destination):
            destination
        case .interact(_, let location):
            location
        case .resumePatrol(_, _, let location):
            location
        case .patrol:
            nil
        case .investigate(_, let location), .secure(_, let location):
            location
        case .pursue(_, let lastKnownLocation):
            lastKnownLocation
        }
    }

    var isPatrolResume: Bool {
        if case .resumePatrol = self { return true }
        return false
    }
}

/// A goal-directed route expressed as a pure function of mission time.
///
/// RealityKit transforms, animation playback, vision cones and collision events
/// are presentation/measurement only. None of them advances or cancels this
/// task. A changed `NavigationWorld.revision` produces a replacement task from
/// the old task's exact pose at the same mission time.
public struct AgentNavigationTask: Sendable, Equatable {
    /// Mission time is accumulated and then combined with authored phase
    /// durations. Treat values within this tolerance as the same boundary so
    /// an exact `startedAt + duration` cannot remain in the previous phase
    /// because of binary floating-point subtraction.
    private static let timelineEpsilon = 1e-9

    public enum Activity: String, Sendable, Equatable {
        case turningLeft
        case turningRight
        case turningAround
        case starting
        case walking
        case braking
        case shortStep
        case arrived
        case blocked
    }

    public struct State: Sendable, Equatable {
        public var position: WorldPoint
        public var facing: Double
        public var activity: Activity
        public var speed: Double
        /// True only for the terminal in-place facing correction before an
        /// interaction. Initial route turns and terminal alignment may use the
        /// same direction, but they are different locomotion blocks.
        public var isAlignment: Bool

        public init(
            position: WorldPoint,
            facing: Double,
            activity: Activity,
            speed: Double = 0,
            isAlignment: Bool = false
        ) {
            self.position = position
            self.facing = facing
            self.activity = activity
            self.speed = speed
            self.isAlignment = isAlignment
        }
    }

    public var goal: AgentGoal
    /// Includes the exact task start followed by pathfinder waypoints.
    public var waypoints: [WorldPoint]
    public var startedAt: Double
    public var speed: Double
    public var initialSpeed: Double
    public var initialFacing: Double
    public var finalFacing: Double?
    public var acceleration: Double
    public var deceleration: Double
    public var maximumTurnRateDegrees: Double
    public var shortStepThreshold: Double
    public var worldRevision: Int
    public var isBlocked: Bool

    public init(
        goal: AgentGoal,
        start: WorldPoint,
        path: PathResult,
        startedAt: Double,
        speed: Double,
        initialFacing: Double,
        initialSpeed: Double = 0,
        finalFacing: Double? = nil,
        worldRevision: Int,
        acceleration: Double = .infinity,
        deceleration: Double = .infinity,
        maximumTurnRateDegrees: Double = .infinity,
        shortStepThreshold: Double = 0.65
    ) {
        self.goal = goal
        self.waypoints = [start] + path.waypoints.filter { start.planarDistance(to: $0) > 1e-9 }
        self.startedAt = startedAt
        self.speed = speed
        self.initialSpeed = min(max(0, initialSpeed), max(0, speed))
        self.initialFacing = initialFacing
        self.finalFacing = finalFacing
        self.acceleration = acceleration
        self.deceleration = deceleration
        self.maximumTurnRateDegrees = maximumTurnRateDegrees
        self.shortStepThreshold = shortStepThreshold
        self.worldRevision = worldRevision
        self.isBlocked = false
    }

    public static func blocked(
        goal: AgentGoal,
        at position: WorldPoint,
        facing: Double,
        startedAt: Double,
        worldRevision: Int
    ) -> AgentNavigationTask {
        AgentNavigationTask(
            goal: goal,
            waypoints: [position],
            startedAt: startedAt,
            speed: 0,
            initialSpeed: 0,
            initialFacing: facing,
            finalFacing: nil,
            acceleration: .infinity,
            deceleration: .infinity,
            maximumTurnRateDegrees: .infinity,
            shortStepThreshold: 0.65,
            worldRevision: worldRevision,
            isBlocked: true
        )
    }

    private init(
        goal: AgentGoal,
        waypoints: [WorldPoint],
        startedAt: Double,
        speed: Double,
        initialSpeed: Double,
        initialFacing: Double,
        finalFacing: Double?,
        acceleration: Double,
        deceleration: Double,
        maximumTurnRateDegrees: Double,
        shortStepThreshold: Double,
        worldRevision: Int,
        isBlocked: Bool
    ) {
        self.goal = goal
        self.waypoints = waypoints
        self.startedAt = startedAt
        self.speed = speed
        self.initialSpeed = initialSpeed
        self.initialFacing = initialFacing
        self.finalFacing = finalFacing
        self.acceleration = acceleration
        self.deceleration = deceleration
        self.maximumTurnRateDegrees = maximumTurnRateDegrees
        self.shortStepThreshold = shortStepThreshold
        self.worldRevision = worldRevision
        self.isBlocked = isBlocked
    }

    public var length: Double {
        zip(waypoints, waypoints.dropFirst()).reduce(0) { result, pair in
            result + pair.0.planarDistance(to: pair.1)
        }
    }

    public var duration: Double {
        turnDuration + motionProfile.totalTime + finalTurnDuration
    }

    public func state(at missionTime: Double) -> State {
        guard let first = waypoints.first else {
            return State(position: .zero, facing: initialFacing, activity: .blocked)
        }
        guard !isBlocked, waypoints.count > 1, speed > 0 else {
            return State(
                position: first,
                facing: initialFacing,
                activity: isBlocked ? .blocked : .arrived
            )
        }

        let elapsed = max(0, missionTime - startedAt)
        let delta = initialTurnDelta
        if elapsed + Self.timelineEpsilon < turnDuration {
            let progress = turnDuration > 0 ? elapsed / turnDuration : 1
            let turnActivity: Activity
            if abs(delta) >= 150 {
                turnActivity = .turningAround
            } else {
                turnActivity = delta < 0 ? .turningLeft : .turningRight
            }
            return State(
                position: first,
                facing: PatrolRoute.normalizedYaw(initialFacing + delta * progress),
                activity: turnActivity,
                speed: 0
            )
        }

        let motionTime = elapsed - turnDuration
        let profile = motionProfile
        let travelled = profile.distance(at: motionTime)
        if motionTime + Self.timelineEpsilon < profile.totalTime {
            let position = position(atDistance: travelled)
            let tangentFacing = facing(atDistance: travelled)
            let activity: Activity
            if length <= shortStepThreshold {
                activity = .shortStep
            } else if initialSpeed <= 0.05, motionTime < profile.accelerationTime {
                activity = .starting
            } else if motionTime >= profile.accelerationTime + profile.cruiseTime {
                activity = .braking
            } else {
                activity = .walking
            }
            return State(
                position: position,
                facing: tangentFacing,
                activity: activity,
                speed: profile.speed(at: motionTime)
            )
        }

        let endFacing = facing(atDistance: length)
        let alignmentTime = motionTime - profile.totalTime
        if alignmentTime + Self.timelineEpsilon < finalTurnDuration {
            let delta = finalTurnDelta(from: endFacing)
            let progress = finalTurnDuration > 0 ? alignmentTime / finalTurnDuration : 1
            let activity: Activity
            if abs(delta) >= 150 { activity = .turningAround }
            else { activity = delta < 0 ? .turningLeft : .turningRight }
            return State(
                position: waypoints.last ?? first,
                facing: PatrolRoute.normalizedYaw(endFacing + delta * progress),
                activity: activity,
                speed: 0,
                isAlignment: true
            )
        }
        return State(
            position: waypoints.last ?? first,
            facing: finalFacing ?? endFacing,
            activity: .arrived,
            speed: 0
        )
    }

    /// The live pose followed only by the still-untravelled authored/sampled
    /// links. Navigation-world mutations use this instead of the historical
    /// whole route, so an obstacle placed behind an actor cannot invalidate a
    /// corridor the actor has already consumed.
    public func remainingWaypoints(at missionTime: Double) -> [WorldPoint] {
        guard let first = waypoints.first else { return [] }
        guard waypoints.count > 1, !isBlocked else { return [first] }

        let elapsed = max(0, missionTime - startedAt)
        if elapsed <= turnDuration { return waypoints }

        let travelled = motionProfile.distance(at: elapsed - turnDuration)
        let current = position(atDistance: travelled)
        if travelled >= length - 1e-9 { return [current] }

        var remainingDistance = travelled
        for (index, pair) in zip(waypoints, waypoints.dropFirst()).enumerated() {
            let segmentLength = pair.0.planarDistance(to: pair.1)
            guard segmentLength > 1e-9 else { continue }
            if remainingDistance < segmentLength {
                return [current] + Array(waypoints.dropFirst(index + 1))
            }
            remainingDistance -= segmentLength
        }
        return [current]
    }

    private var initialTurnDelta: Double {
        guard waypoints.count > 1 else { return 0 }
        // Use the first sampled chord here, not the normal 12 cm look-ahead:
        // on a deliberately curved start the latter already sees well into
        // the bend and mistakes steering curvature for a required pivot.
        let startTangent = PatrolRoute.yaw(from: waypoints[0], to: waypoints[1])
        let delta = PatrolRoute.shortestTurn(from: initialFacing, to: startTangent)
        // A sampled tangent can differ by a few degrees from the mathematical
        // curve tangent. Locomotion blending absorbs that naturally; treating
        // it as a separate turn clip creates a visible one-frame hesitation.
        return abs(delta) < 4 ? 0 : delta
    }

    private var turnDuration: Double {
        guard maximumTurnRateDegrees.isFinite, maximumTurnRateDegrees > 0 else { return 0 }
        return abs(initialTurnDelta) / maximumTurnRateDegrees
    }

    private func finalTurnDelta(from endFacing: Double) -> Double {
        guard let finalFacing else { return 0 }
        return PatrolRoute.shortestTurn(from: endFacing, to: finalFacing)
    }

    private var finalTurnDuration: Double {
        guard maximumTurnRateDegrees.isFinite, maximumTurnRateDegrees > 0 else { return 0 }
        return abs(finalTurnDelta(from: facing(atDistance: length))) / maximumTurnRateDegrees
    }

    private var motionProfile: MotionProfile {
        MotionProfile(
            distance: length,
            maximumSpeed: speed,
            initialSpeed: initialSpeed,
            acceleration: acceleration,
            deceleration: deceleration
        )
    }

    private func position(atDistance requested: Double) -> WorldPoint {
        guard let first = waypoints.first else { return .zero }
        var remaining = max(0, requested)
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let segment = from.planarDistance(to: to)
            guard segment > 1e-9 else { continue }
            if remaining < segment {
                return (from + (to - from) * (remaining / segment)).onFloorPlane
            }
            remaining -= segment
        }
        return waypoints.last ?? first
    }

    private func facing(atDistance distance: Double) -> Double {
        let look = min(0.12, max(0.02, length * 0.1))
        let before = position(atDistance: max(0, distance - look))
        let after = position(atDistance: min(length, distance + look))
        guard before.planarDistance(to: after) > 1e-9 else { return initialFacing }
        return PatrolRoute.yaw(from: before, to: after)
    }
}

private struct MotionProfile {
    var distance: Double
    var maximumSpeed: Double
    var initialSpeed: Double
    var acceleration: Double
    var deceleration: Double
    var accelerationTime: Double
    var cruiseTime: Double
    var decelerationTime: Double
    var peakSpeed: Double

    init(
        distance: Double,
        maximumSpeed: Double,
        initialSpeed: Double,
        acceleration: Double,
        deceleration: Double
    ) {
        self.distance = max(0, distance)
        self.maximumSpeed = max(0, maximumSpeed)
        self.initialSpeed = min(max(0, initialSpeed), self.maximumSpeed)
        self.acceleration = acceleration
        self.deceleration = deceleration
        if !acceleration.isFinite || !deceleration.isFinite || acceleration <= 0 || deceleration <= 0 {
            accelerationTime = 0
            cruiseTime = maximumSpeed > 0 ? self.distance / maximumSpeed : 0
            decelerationTime = 0
            peakSpeed = self.maximumSpeed
            return
        }
        let accelerationDistance = max(
            0,
            (maximumSpeed * maximumSpeed - self.initialSpeed * self.initialSpeed)
                / (2 * acceleration)
        )
        let decelerationDistance = maximumSpeed * maximumSpeed / (2 * deceleration)
        if accelerationDistance + decelerationDistance <= self.distance {
            peakSpeed = self.maximumSpeed
            accelerationTime = max(0, (peakSpeed - self.initialSpeed) / acceleration)
            decelerationTime = peakSpeed / deceleration
            cruiseTime = peakSpeed > 0
                ? (self.distance - accelerationDistance - decelerationDistance) / peakSpeed : 0
        } else {
            peakSpeed = sqrt(max(
                0,
                (2 * self.distance * acceleration * deceleration
                    + self.initialSpeed * self.initialSpeed * deceleration)
                    / (acceleration + deceleration)
            ))
            if peakSpeed >= self.initialSpeed {
                accelerationTime = (peakSpeed - self.initialSpeed) / acceleration
            } else {
                // The replacement route is too short to preserve its incoming
                // speed. Brake immediately, increasing the effective rate only
                // when required to stop exactly at the goal.
                peakSpeed = self.initialSpeed
                accelerationTime = 0
                self.deceleration = max(
                    deceleration,
                    self.initialSpeed * self.initialSpeed / max(2 * self.distance, 1e-9)
                )
            }
            cruiseTime = 0
            decelerationTime = peakSpeed / self.deceleration
        }
    }

    var totalTime: Double { accelerationTime + cruiseTime + decelerationTime }

    func speed(at requestedTime: Double) -> Double {
        let time = min(max(0, requestedTime), totalTime)
        if accelerationTime > 0, time < accelerationTime {
            return initialSpeed + acceleration * time
        }
        if time < accelerationTime + cruiseTime { return peakSpeed }
        let brakingTime = time - accelerationTime - cruiseTime
        return max(0, peakSpeed - deceleration * brakingTime)
    }

    func distance(at requestedTime: Double) -> Double {
        let time = min(max(0, requestedTime), totalTime)
        if accelerationTime > 0, time < accelerationTime {
            return initialSpeed * time + 0.5 * acceleration * time * time
        }
        let accelerationDistance = accelerationTime > 0
            ? initialSpeed * accelerationTime
                + 0.5 * acceleration * accelerationTime * accelerationTime
            : 0
        if time < accelerationTime + cruiseTime {
            return accelerationDistance + peakSpeed * (time - accelerationTime)
        }
        let brakingTime = time - accelerationTime - cruiseTime
        return min(distance,
            accelerationDistance + peakSpeed * cruiseTime
                + peakSpeed * brakingTime - 0.5 * deceleration * brakingTime * brakingTime
        )
    }
}
