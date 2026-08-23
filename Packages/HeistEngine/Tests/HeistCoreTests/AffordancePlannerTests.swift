import Testing
@testable import HeistCore

@Suite("Smart-object affordance planner")
struct AffordancePlannerTests {
    let doorID = "door.office"

    @Test("An unlocked closed door advertises open, traverse and optional close")
    func unlockedDoorPlan() throws {
        let initial = DoorAffordanceFactory.facts(
            doorID: doorID, isOpen: false, isLocked: false, actorSide: "a"
        )
        let goal: Set<PlanningFact> = [
            PlanningFact("actor.at.\(doorID).b"),
            PlanningFact("object.\(doorID).closed")
        ]
        let result = try AffordancePlanner.plan(
            initial: initial,
            goal: goal,
            actions: DoorAffordanceFactory.actions(doorID: doorID)
        ).get()

        #expect(result.actions.map(\.id) == [
            "\(doorID).open", "\(doorID).traverse.a-b", "\(doorID).close.b"
        ])
    }

    @Test("A capable actor inserts lockpick before opening a locked door")
    func lockedDoorPlan() throws {
        let initial = DoorAffordanceFactory.facts(
            doorID: doorID,
            isOpen: false,
            isLocked: true,
            actorSide: "a",
            actorFacts: [PlanningFact("actor.can.lockpick")]
        )
        let goal: Set<PlanningFact> = [PlanningFact("actor.at.\(doorID).b")]
        let result = try AffordancePlanner.plan(
            initial: initial,
            goal: goal,
            actions: DoorAffordanceFactory.actions(doorID: doorID)
        ).get()

        #expect(result.actions.map(\.id) == [
            "\(doorID).lockpick", "\(doorID).open", "\(doorID).traverse.a-b"
        ])
    }

    @Test("A guard key unlocks before opening without pretending to lockpick")
    func guardUnlockPlan() throws {
        let initial = DoorAffordanceFactory.facts(
            doorID: doorID,
            isOpen: false,
            isLocked: true,
            actorSide: "a",
            actorFacts: [PlanningFact("actor.can.unlock")]
        )
        let goal: Set<PlanningFact> = [PlanningFact("actor.at.\(doorID).b")]
        let result = try AffordancePlanner.plan(
            initial: initial,
            goal: goal,
            actions: DoorAffordanceFactory.actions(doorID: doorID)
        ).get()
        #expect(result.actions.map(\.id) == [
            "\(doorID).unlock", "\(doorID).open", "\(doorID).traverse.a-b"
        ])
    }

    @Test("A locked door is not magically passable for an incapable actor")
    func lockedDoorCanFail() {
        let initial = DoorAffordanceFactory.facts(
            doorID: doorID, isOpen: false, isLocked: true, actorSide: "a"
        )
        let goal: Set<PlanningFact> = [PlanningFact("actor.at.\(doorID).b")]
        #expect(AffordancePlanner.plan(
            initial: initial,
            goal: goal,
            actions: DoorAffordanceFactory.actions(doorID: doorID)
        ) == .failure(.noPlan))
    }
}
