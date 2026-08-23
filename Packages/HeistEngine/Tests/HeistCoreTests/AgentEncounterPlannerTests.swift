import Testing
@testable import HeistCore

@Suite("Agent encounter planning")
struct AgentEncounterPlannerTests {
    @Test("A moving actor detours once around a stationary body")
    func stationaryBlocker() throws {
        let decision = try #require(AgentEncounterPlanner.decide(
            first: AgentMotionIntent(
                id: "guard", position: .init(x: 0, y: 0, z: 0),
                futurePosition: .init(x: 4, y: 0, z: 0), radius: 0.3,
                avoidancePriority: 10
            ),
            second: AgentMotionIntent(
                id: "thief", position: .init(x: 2, y: 0, z: 0),
                futurePosition: .init(x: 2, y: 0, z: 0), radius: 0.3,
                avoidancePriority: 50
            ),
            horizon: 2
        ))

        #expect(decision.kind == .stationaryBlocker)
        #expect(decision.maneuveringAgentID == "guard")
        #expect(decision.rightOfWayAgentID == "thief")
        #expect(abs(decision.closestApproachTime - 1) < 0.001)
    }

    @Test("Crossing movers are negotiated before their lines intersect")
    func crossingTrajectories() throws {
        let decision = try #require(AgentEncounterPlanner.decide(
            first: AgentMotionIntent(
                id: "guard", position: .init(x: -2, y: 0, z: 0),
                futurePosition: .init(x: 2, y: 0, z: 0), radius: 0.3,
                avoidancePriority: 10
            ),
            second: AgentMotionIntent(
                id: "thief", position: .init(x: 0, y: 0, z: -2),
                futurePosition: .init(x: 0, y: 0, z: 2), radius: 0.3,
                avoidancePriority: 50
            ),
            horizon: 2
        ))

        #expect(decision.kind == .crossingTrajectories)
        #expect(decision.maneuveringAgentID == "thief")
        #expect(decision.rightOfWayAgentID == "guard")
        #expect(decision.predictedMeetingPoint.planarDistance(to: .zero) < 0.001)
    }

    @Test("Separated trajectories do not create a reservation")
    func separated() {
        let decision = AgentEncounterPlanner.decide(
            first: AgentMotionIntent(
                id: "a", position: .init(x: 0, y: 0, z: 0),
                futurePosition: .init(x: 2, y: 0, z: 0), radius: 0.3,
                avoidancePriority: 10
            ),
            second: AgentMotionIntent(
                id: "b", position: .init(x: 0, y: 0, z: 2),
                futurePosition: .init(x: 2, y: 0, z: 2), radius: 0.3,
                avoidancePriority: 20
            ),
            horizon: 2
        )
        #expect(decision == nil)
    }

    @Test("The trajectory committed first keeps right of way regardless of role priority")
    func earlierCommitmentWins() throws {
        let decision = try #require(AgentEncounterPlanner.decide(
            first: AgentMotionIntent(
                id: "thief", position: .init(x: -2, y: 0, z: 0),
                futurePosition: .init(x: 2, y: 0, z: 0), radius: 0.3,
                trajectoryCommittedAt: 3,
                avoidancePriority: 50
            ),
            second: AgentMotionIntent(
                id: "guard", position: .init(x: 0, y: 0, z: -2),
                futurePosition: .init(x: 0, y: 0, z: 2), radius: 0.3,
                trajectoryCommittedAt: 5,
                avoidancePriority: 10
            ),
            horizon: 2
        ))

        #expect(decision.rightOfWayAgentID == "thief")
        #expect(decision.maneuveringAgentID == "guard")
    }
}
