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
    public enum Activity: String, Sendable, Equatable {
        case turning
        case waiting
        case walking
    }

    public enum TurnDirection: String, Sendable, Equatable {
        case left
        case right
        case around
    }

    /// Waypoints in world meters. The guard walks them in order.
    public var waypoints: [WorldPoint]
    /// Meters per second.
    public var speed: Double
    /// Seconds spent standing still at each waypoint.
    public var pauseAtWaypoint: Double
    /// Visual/gameplay turn rate. Turns are explicit timeline intervals rather
    /// than instantaneous transform snaps at a waypoint.
    public var turnSpeedDegreesPerSecond: Double
    public var initialFacing: Double
    /// Whether the guard returns to the first waypoint and repeats.
    public var isLoop: Bool

    public init(
        waypoints: [WorldPoint],
        speed: Double,
        pauseAtWaypoint: Double = 2.0,
        turnSpeedDegreesPerSecond: Double = 0,
        initialFacing: Double = 0,
        isLoop: Bool = true
    ) {
        self.waypoints = waypoints
        self.speed = speed
        self.pauseAtWaypoint = pauseAtWaypoint
        self.turnSpeedDegreesPerSecond = turnSpeedDegreesPerSecond
        self.initialFacing = initialFacing
        self.isLoop = isLoop
    }

    /// Where a guard is, and which way they face, at a given moment.
    public struct State: Sendable, Equatable {
        public var position: WorldPoint
        /// Yaw in degrees, matching the blueprint convention: 0 faces +z.
        public var facing: Double
        public var activity: Activity
        public var turnDirection: TurnDirection?
        /// Compatibility for systems that only distinguish locomotion from rest.
        public var isPaused: Bool { activity != .walking }

        public init(
            position: WorldPoint,
            facing: Double,
            activity: Activity,
            turnDirection: TurnDirection? = nil
        ) {
            self.position = position
            self.facing = facing
            self.activity = activity
            self.turnDirection = turnDirection
        }
    }

    /// An authored patrol node together with the exact route phase at which the
    /// guard reaches it. Detours target anchors, never arbitrary samples on an
    /// old leg: once a leg is obstructed, its remainder is discarded.
    public struct Anchor: Sendable, Equatable {
        public var waypointIndex: Int
        public var position: WorldPoint
        public var routeTime: Double

        public init(waypointIndex: Int, position: WorldPoint, routeTime: Double) {
            self.waypointIndex = waypointIndex
            self.position = position
            self.routeTime = routeTime
        }
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
        return walking + pausing + turnDurations.reduce(0, +)
    }

    /// The guard's state at `time` seconds into the mission.
    public func state(at time: Double) -> State {
        guard let first = waypoints.first else {
            return State(position: .zero, facing: initialFacing, activity: .waiting)
        }
        guard waypoints.count > 1, speed > 0 else {
            return State(position: first, facing: initialFacing, activity: .waiting)
        }

        let cycle = cycleDuration
        guard cycle > 0 else {
            return State(position: first, facing: initialFacing, activity: .waiting)
        }

        // Wrap into one circuit. A non-looping route holds its final pose.
        var cursor = time
        if isLoop {
            cursor = time.truncatingRemainder(dividingBy: cycle)
            if cursor < 0 { cursor += cycle }
        } else if cursor >= cycle {
            let last = waypoints[waypoints.count - 1]
            let previous = waypoints[waypoints.count - 2]
            return State(
                position: last,
                facing: PatrolRoute.yaw(from: previous, to: last),
                activity: .waiting
            )
        }

        for (legIndex, leg) in legs.enumerated() {
            let outgoingFacing = PatrolRoute.yaw(from: leg.from, to: leg.to)
            let incomingFacing = facingBeforeLeg(legIndex)
            let turnDelta = Self.shortestTurn(from: incomingFacing, to: outgoingFacing)
            let turnDuration = durationForTurn(turnDelta)

            if cursor < turnDuration {
                let progress = turnDuration > 0 ? cursor / turnDuration : 1
                return State(
                    position: leg.from,
                    facing: Self.normalizedYaw(incomingFacing + turnDelta * progress),
                    activity: .turning,
                    turnDirection: abs(turnDelta) >= 150
                        ? .around : (turnDelta < 0 ? .left : .right)
                )
            }
            cursor -= turnDuration

            // Pause at the waypoint this leg departs from.
            if cursor < pauseAtWaypoint {
                return State(position: leg.from, facing: outgoingFacing, activity: .waiting)
            }
            cursor -= pauseAtWaypoint

            let distance = leg.from.planarDistance(to: leg.to)
            let duration = distance / speed
            if cursor < duration {
                let progress = duration > 0 ? cursor / duration : 1
                let position = leg.from + (leg.to - leg.from) * progress
                return State(
                    position: position.onFloorPlane,
                    facing: outgoingFacing,
                    activity: .walking
                )
            }
            cursor -= duration
        }

        // Floating-point slack at the very end of a circuit.
        return State(position: first, facing: initialFacing, activity: .waiting)
    }

    /// The first authored node strictly after `time` on the patrol timeline.
    /// For a looping patrol `routeTime` remains monotonic across circuits, so a
    /// pause/resume detour can land on the node without teleporting its phase.
    public func nextAnchor(after time: Double) -> Anchor? {
        guard waypoints.count > 1, speed > 0, cycleDuration > 0 else { return nil }

        let cycle = cycleDuration
        let clampedTime = max(0, time)
        let circuit = isLoop ? floor(clampedTime / cycle) : 0
        var phase = isLoop ? clampedTime - circuit * cycle : clampedTime
        if phase < 0 { phase += cycle }

        var cursor = 0.0
        for (legIndex, leg) in legs.enumerated() {
            let arrival = cursor
                + turnDurations[legIndex]
                + pauseAtWaypoint
                + leg.from.planarDistance(to: leg.to) / speed
            if phase < arrival - 1e-9 {
                return Anchor(
                    waypointIndex: (legIndex + 1) % waypoints.count,
                    position: leg.to,
                    routeTime: circuit * cycle + arrival
                )
            }
            cursor = arrival
        }

        guard isLoop else { return nil }
        let firstArrival = turnDurations[0]
            + pauseAtWaypoint
            + legs[0].from.planarDistance(to: legs[0].to) / speed
        return Anchor(
            waypointIndex: 1,
            position: waypoints[1],
            routeTime: (circuit + 1) * cycle + firstArrival
        )
    }

    private var turnDurations: [Double] {
        legs.indices.map { index in
            durationForTurn(Self.shortestTurn(
                from: facingBeforeLeg(index),
                to: Self.yaw(from: legs[index].from, to: legs[index].to)
            ))
        }
    }

    private func facingBeforeLeg(_ index: Int) -> Double {
        guard index > 0 else {
            if isLoop, let finalLeg = legs.last {
                return Self.yaw(from: finalLeg.from, to: finalLeg.to)
            }
            return initialFacing
        }
        let previous = legs[index - 1]
        return Self.yaw(from: previous.from, to: previous.to)
    }

    private func durationForTurn(_ delta: Double) -> Double {
        guard turnSpeedDegreesPerSecond > 0 else { return 0 }
        return abs(delta) / turnSpeedDegreesPerSecond
    }

    public static func shortestTurn(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    public static func normalizedYaw(_ yaw: Double) -> Double {
        let value = yaw.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
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
            turnSpeedDegreesPerSecond: actor.config["turnSpeed"]?.doubleValue ?? 180,
            initialFacing: actor.facing,
            isLoop: actor.config["patrolLoops"]?.boolValue ?? true
        )
    }
}
