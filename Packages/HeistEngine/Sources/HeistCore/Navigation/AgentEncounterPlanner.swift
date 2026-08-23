import Foundation

/// Immutable motion intent used by the local multi-agent navigation layer.
/// Global pathfinding still owns destinations and corridors; this type only
/// predicts whether two short trajectory windows conflict.
public struct AgentMotionIntent: Sendable, Equatable {
    public var id: String
    public var position: WorldPoint
    public var futurePosition: WorldPoint
    public var radius: Double
    /// Mission time at which this trajectory was committed. An already-owned
    /// corridor has right of way over a route assigned later.
    public var trajectoryCommittedAt: Double?
    /// Lower values have right of way, matching common navigation-agent APIs.
    /// This is only a deterministic tie-breaker for simultaneous commitments.
    public var avoidancePriority: Int

    public init(
        id: String,
        position: WorldPoint,
        futurePosition: WorldPoint,
        radius: Double,
        trajectoryCommittedAt: Double? = nil,
        avoidancePriority: Int
    ) {
        self.id = id
        self.position = position
        self.futurePosition = futurePosition
        self.radius = radius
        self.trajectoryCommittedAt = trajectoryCommittedAt
        self.avoidancePriority = avoidancePriority
    }

    public var isMoving: Bool {
        position.planarDistance(to: futurePosition) > 0.01
    }
}

public struct AgentEncounterDecision: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The moving actor makes one local detour; the blocker keeps its pose.
        case stationaryBlocker
        /// Both trajectories move; the lower-priority actor avoids the swept
        /// future corridor of the higher-priority actor.
        case crossingTrajectories
    }

    public var kind: Kind
    public var maneuveringAgentID: String
    public var rightOfWayAgentID: String
    public var closestApproachTime: Double
    public var predictedMeetingPoint: WorldPoint

    public init(
        kind: Kind,
        maneuveringAgentID: String,
        rightOfWayAgentID: String,
        closestApproachTime: Double,
        predictedMeetingPoint: WorldPoint
    ) {
        self.kind = kind
        self.maneuveringAgentID = maneuveringAgentID
        self.rightOfWayAgentID = rightOfWayAgentID
        self.closestApproachTime = closestApproachTime
        self.predictedMeetingPoint = predictedMeetingPoint
    }
}

/// Deterministic, bounded prediction for a pair of disc-shaped actors.
public enum AgentEncounterPlanner {
    public static func decide(
        first: AgentMotionIntent,
        second: AgentMotionIntent,
        horizon: Double,
        comfortClearance: Double = 0.04
    ) -> AgentEncounterDecision? {
        guard horizon > 0, first.isMoving || second.isMoving else { return nil }

        let firstVelocity = (first.futurePosition - first.position) * (1 / horizon)
        let secondVelocity = (second.futurePosition - second.position) * (1 / horizon)
        let relativePosition = first.position - second.position
        let relativeVelocity = firstVelocity - secondVelocity
        let speedSquared = relativeVelocity.x * relativeVelocity.x
            + relativeVelocity.z * relativeVelocity.z
        let closestTime = speedSquared > 1e-12
            ? min(horizon, max(0, -(
                relativePosition.x * relativeVelocity.x
                    + relativePosition.z * relativeVelocity.z
            ) / speedSquared))
            : 0
        let firstClosest = first.position + firstVelocity * closestTime
        let secondClosest = second.position + secondVelocity * closestTime
        let minimum = first.radius + second.radius + comfortClearance
        guard firstClosest.planarDistance(to: secondClosest) < minimum else { return nil }

        let meeting = WorldPoint(
            x: (firstClosest.x + secondClosest.x) / 2,
            y: 0,
            z: (firstClosest.z + secondClosest.z) / 2
        )

        if first.isMoving != second.isMoving {
            let mover = first.isMoving ? first : second
            let blocker = first.isMoving ? second : first
            return AgentEncounterDecision(
                kind: .stationaryBlocker,
                maneuveringAgentID: mover.id,
                rightOfWayAgentID: blocker.id,
                closestApproachTime: closestTime,
                predictedMeetingPoint: meeting
            )
        }

        let firstWins: Bool
        if first.trajectoryCommittedAt != second.trajectoryCommittedAt {
            switch (first.trajectoryCommittedAt, second.trajectoryCommittedAt) {
            case (.some(let lhs), .some(let rhs)):
                firstWins = lhs < rhs
            case (.some, .none):
                firstWins = true
            case (.none, .some):
                firstWins = false
            case (.none, .none):
                firstWins = first.id < second.id
            }
        } else if first.avoidancePriority != second.avoidancePriority {
            firstWins = first.avoidancePriority < second.avoidancePriority
        } else {
            firstWins = first.id < second.id
        }
        return AgentEncounterDecision(
            kind: .crossingTrajectories,
            maneuveringAgentID: firstWins ? second.id : first.id,
            rightOfWayAgentID: firstWins ? first.id : second.id,
            closestApproachTime: closestTime,
            predictedMeetingPoint: meeting
        )
    }
}
