import Foundation

/// A guard's route, expressed as a function of time.
///
/// The important design choice: a patrol is **not** a state machine that ticks
/// forward. Ask it where the guard is at 31.4 seconds and it answers directly,
/// without having simulated the 31.4 seconds before it.
///
/// That is what makes the planning loop possible. Replaying a plan, scrubbing a
/// timeline, or checking "would the guard have seen me here" all become lookups
/// rather than re-simulations, and they give the same answer every time.
public struct PatrolRoute: Sendable, Equatable {
    /// Waypoints in world meters. The guard walks them in order.
    public var waypoints: [WorldPoint]
    /// Meters per second.
    public var speed: Double
    /// Seconds spent standing still at each waypoint.
    public var pauseAtWaypoint: Double
    /// Whether the guard returns to the first waypoint and repeats.
    public var isLoop: Bool

    public init(
        waypoints: [WorldPoint],
        speed: Double,
        pauseAtWaypoint: Double = 2.0,
        isLoop: Bool = true
    ) {
        self.waypoints = waypoints
        self.speed = speed
        self.pauseAtWaypoint = pauseAtWaypoint
        self.isLoop = isLoop
    }

    /// Where a guard is, and which way they face, at a given moment.
    public struct State: Sendable, Equatable {
        public var position: WorldPoint
        /// Yaw in degrees, matching the blueprint convention: 0 faces +z.
        public var facing: Double
        /// True while standing at a waypoint rather than walking.
        public var isPaused: Bool
    }

    /// The legs of the route, as (from, to) pairs.
    private var legs: [(from: WorldPoint, to: WorldPoint)] {
        guard waypoints.count > 1 else { return [] }
        var result: [(WorldPoint, WorldPoint)] = []
        for index in 0..<(waypoints.count - 1) {
            result.append((waypoints[index], waypoints[index + 1]))
        }
        if isLoop {
            result.append((waypoints[waypoints.count - 1], waypoints[0]))
        }
        return result
    }

    /// How long one full circuit takes, in seconds.
    ///
    /// This is the number a player learns. It has to be stable, so it is derived
    /// from geometry rather than measured at runtime.
    public var cycleDuration: Double {
        guard speed > 0, waypoints.count > 1 else { return 0 }
        let walking = legs.reduce(0.0) { $0 + $1.from.planarDistance(to: $1.to) / speed }
        let pausing = pauseAtWaypoint * Double(isLoop ? waypoints.count : waypoints.count - 1)
        return walking + pausing
    }

    /// The guard's state at `time` seconds into the mission.
    public func state(at time: Double) -> State {
        guard let first = waypoints.first else {
            return State(position: .zero, facing: 0, isPaused: true)
        }
        guard waypoints.count > 1, speed > 0 else {
            return State(position: first, facing: 0, isPaused: true)
        }

        let cycle = cycleDuration
        guard cycle > 0 else {
            return State(position: first, facing: 0, isPaused: true)
        }

        // Wrap into one circuit. A non-looping route holds its final pose.
        var cursor = time
        if isLoop {
            cursor = time.truncatingRemainder(dividingBy: cycle)
            if cursor < 0 { cursor += cycle }
        } else if cursor >= cycle {
            let last = waypoints[waypoints.count - 1]
            let previous = waypoints[waypoints.count - 2]
            return State(position: last, facing: PatrolRoute.yaw(from: previous, to: last), isPaused: true)
        }

        for leg in legs {
            // Pause at the waypoint this leg departs from.
            if cursor < pauseAtWaypoint {
                let facing = PatrolRoute.yaw(from: leg.from, to: leg.to)
                return State(position: leg.from, facing: facing, isPaused: true)
            }
            cursor -= pauseAtWaypoint

            let distance = leg.from.planarDistance(to: leg.to)
            let duration = distance / speed
            if cursor < duration {
                let progress = duration > 0 ? cursor / duration : 1
                let position = leg.from + (leg.to - leg.from) * progress
                return State(
                    position: position.onFloorPlane,
                    facing: PatrolRoute.yaw(from: leg.from, to: leg.to),
                    isPaused: false
                )
            }
            cursor -= duration
        }

        // Floating-point slack at the very end of a circuit.
        return State(position: first, facing: 0, isPaused: true)
    }

    /// Yaw in degrees for travel from one point to another.
    public static func yaw(from: WorldPoint, to: WorldPoint) -> Double {
        let delta = to - from
        guard delta.planarLength > 1e-9 else { return 0 }
        return atan2(delta.x, delta.z) * 180 / .pi
    }
}

extension PatrolRoute {
    /// Builds a route from a blueprint actor.
    public init?(actor: ActorSpec, metrics: LevelMetrics, character: CharacterProfile) {
        guard actor.route.count > 1 else { return nil }
        self.init(
            waypoints: actor.route.map { metrics.worldPoint($0) },
            speed: character.walkSpeed,
            pauseAtWaypoint: actor.config["patrolPause"]?.doubleValue ?? 2.0,
            isLoop: actor.config["patrolLoops"]?.boolValue ?? true
        )
    }
}
