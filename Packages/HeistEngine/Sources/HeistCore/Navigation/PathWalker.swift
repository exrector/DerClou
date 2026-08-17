import Foundation

/// Advances an actor along a route at a constant speed.
///
/// This is game logic, not rendering, so it lives here rather than in the
/// RealityKit system that drives it. Arrival time is a pure function of path
/// length and speed — no physics, no frame-rate dependency — which is what makes
/// a planned route's ETA something the player can rely on.
public struct PathWalker: Sendable, Equatable {
    /// Remaining waypoints, in world meters.
    public private(set) var waypoints: [WorldPoint]
    /// Index of the waypoint currently being walked toward.
    public private(set) var index: Int
    /// How close counts as reaching a waypoint, in meters.
    public var arrivalTolerance: Double
    /// Seconds spent without getting closer to the current waypoint.
    ///
    /// A wedged actor otherwise just stands there and the only symptom is a
    /// player wondering why nothing happens.
    public private(set) var stalledFor: Double
    private var lastDistance: Double

    public init(waypoints: [WorldPoint], arrivalTolerance: Double = 0.05) {
        self.waypoints = waypoints
        self.index = 0
        self.arrivalTolerance = arrivalTolerance
        self.stalledFor = 0
        self.lastDistance = .greatestFiniteMagnitude
    }

    public var isFinished: Bool { index >= waypoints.count }

    /// The waypoint being walked toward, if any.
    public var currentTarget: WorldPoint? {
        isFinished ? nil : waypoints[index]
    }

    /// Result of advancing one step.
    public struct Step: Sendable, Equatable {
        /// Where the actor ends up.
        public var position: WorldPoint
        /// Direction of travel, or nil when the actor did not move.
        public var facing: WorldPoint?
        /// True once the last waypoint has been reached.
        public var isFinished: Bool
        /// True when no progress has been made for longer than the stall limit.
        public var isStalled: Bool
    }

    /// Moves `speed * deltaTime` meters along the route.
    ///
    /// - Parameters:
    ///   - position: where the actor is now.
    ///   - speed: meters per second.
    ///   - deltaTime: seconds elapsed.
    ///   - stallLimit: how long without progress before reporting a stall.
    public mutating func advance(
        from position: WorldPoint,
        speed: Double,
        deltaTime: Double,
        stallLimit: Double = 1.5
    ) -> Step {
        guard deltaTime > 0, speed > 0 else {
            return Step(position: position, facing: nil, isFinished: isFinished, isStalled: false)
        }

        var current = position.onFloorPlane
        var budget = speed * deltaTime
        var facing: WorldPoint?

        while budget > 0, !isFinished {
            let target = waypoints[index].onFloorPlane
            let toTarget = target - current
            let remaining = toTarget.planarLength

            if remaining <= max(arrivalTolerance, budget) {
                current = target
                budget -= remaining
                index += 1
                lastDistance = .greatestFiniteMagnitude
                continue
            }

            let direction = toTarget.normalized
            current = current + direction * budget
            facing = direction
            budget = 0
        }

        if isFinished {
            return Step(position: current, facing: facing, isFinished: true, isStalled: false)
        }

        let distance = current.planarDistance(to: waypoints[index])
        if distance < lastDistance - 0.001 {
            stalledFor = 0
        } else {
            stalledFor += deltaTime
        }
        lastDistance = distance

        return Step(
            position: current,
            facing: facing,
            isFinished: false,
            isStalled: stalledFor >= stallLimit
        )
    }
}
