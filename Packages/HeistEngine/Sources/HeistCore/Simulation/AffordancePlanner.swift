import Foundation

/// A small, stable fact vocabulary for goal-oriented use of smart objects.
/// Facts are namespaced strings so new object mechanics do not require changing
/// a central enum or planner switch.
public struct PlanningFact: RawRepresentable, Codable, Sendable, Hashable, Comparable {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func < (lhs: PlanningFact, rhs: PlanningFact) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AgentActionSemantic: Sendable, Equatable {
    case moveToSlot(objectID: String, side: String)
    case faceObject(objectID: String)
    case interact(objectID: String, kind: InteractionKind)
    case traverse(objectID: String, fromSide: String, toSide: String)
}

/// One action advertised by a smart object. The object supplies conditions and
/// effects; the actor supplies the semantic execution and matching animation.
public struct AffordanceAction: Sendable, Equatable {
    public var id: String
    public var semantic: AgentActionSemantic
    public var preconditions: Set<PlanningFact>
    public var adding: Set<PlanningFact>
    public var removing: Set<PlanningFact>
    public var duration: Double
    public var riskCost: Double

    public init(
        id: String,
        semantic: AgentActionSemantic,
        preconditions: Set<PlanningFact> = [],
        adding: Set<PlanningFact> = [],
        removing: Set<PlanningFact> = [],
        duration: Double,
        riskCost: Double = 0
    ) {
        self.id = id
        self.semantic = semantic
        self.preconditions = preconditions
        self.adding = adding
        self.removing = removing
        self.duration = max(0, duration)
        self.riskCost = max(0, riskCost)
    }

    public var cost: Double { duration + riskCost }

    public func isApplicable(to state: Set<PlanningFact>) -> Bool {
        preconditions.isSubset(of: state)
    }

    public func applying(to state: Set<PlanningFact>) -> Set<PlanningFact> {
        state.subtracting(removing).union(adding)
    }
}

public enum AffordancePlanningFailure: Error, Sendable, Equatable {
    case noPlan
    case searchBudgetExceeded
}

public struct AffordancePlan: Sendable, Equatable {
    public var actions: [AffordanceAction]
    public var cost: Double
}

/// Deterministic uniform-cost forward planner. Smart-object action sets are
/// intentionally small; a simple stable search is easier to inspect and replay
/// than a hidden behavior graph per level.
public enum AffordancePlanner {
    public static func plan(
        initial: Set<PlanningFact>,
        goal: Set<PlanningFact>,
        actions: [AffordanceAction],
        maximumExpandedStates: Int = 512
    ) -> Result<AffordancePlan, AffordancePlanningFailure> {
        struct Node {
            var state: Set<PlanningFact>
            var actions: [AffordanceAction]
            var cost: Double

            var signature: String {
                state.sorted().map(\.rawValue).joined(separator: "|")
            }
        }

        let orderedActions = actions.sorted { $0.id < $1.id }
        var open = [Node(state: initial, actions: [], cost: 0)]
        var bestCost = [open[0].signature: 0.0]
        var expanded = 0

        while !open.isEmpty {
            open.sort {
                if abs($0.cost - $1.cost) > 1e-9 { return $0.cost < $1.cost }
                if $0.actions.map(\.id) != $1.actions.map(\.id) {
                    return $0.actions.map(\.id).lexicographicallyPrecedes($1.actions.map(\.id))
                }
                return $0.signature < $1.signature
            }
            let current = open.removeFirst()
            if goal.isSubset(of: current.state) {
                return .success(AffordancePlan(actions: current.actions, cost: current.cost))
            }

            expanded += 1
            guard expanded <= maximumExpandedStates else {
                return .failure(.searchBudgetExceeded)
            }

            for action in orderedActions where action.isApplicable(to: current.state) {
                let nextState = action.applying(to: current.state)
                guard nextState != current.state else { continue }
                let nextCost = current.cost + action.cost
                let signature = nextState.sorted().map(\.rawValue).joined(separator: "|")
                if let known = bestCost[signature], known <= nextCost + 1e-9 { continue }
                bestCost[signature] = nextCost
                open.append(Node(
                    state: nextState,
                    actions: current.actions + [action],
                    cost: nextCost
                ))
            }
        }
        return .failure(.noPlan)
    }
}

/// Standard smart-object action generator for a two-sided hinged door. Level
/// instances supply only state and policy; the same actions work for every door.
public enum DoorAffordanceFactory {
    public static func facts(
        doorID: String,
        isOpen: Bool,
        isLocked: Bool,
        actorSide: String,
        actorFacts: Set<PlanningFact> = []
    ) -> Set<PlanningFact> {
        var facts = actorFacts
        facts.insert(PlanningFact("actor.at.\(doorID).\(actorSide)"))
        facts.insert(PlanningFact("object.\(doorID).\(isOpen ? "open" : "closed")"))
        facts.insert(PlanningFact("object.\(doorID).\(isLocked ? "locked" : "unlocked")"))
        return facts
    }

    public static func actions(
        doorID: String,
        sideA: String = "a",
        sideB: String = "b",
        openDuration: Double = 1,
        closeDuration: Double = 1,
        lockpickDuration: Double = 4
    ) -> [AffordanceAction] {
        let open = PlanningFact("object.\(doorID).open")
        let closed = PlanningFact("object.\(doorID).closed")
        let locked = PlanningFact("object.\(doorID).locked")
        let unlocked = PlanningFact("object.\(doorID).unlocked")
        let canLockpick = PlanningFact("actor.can.lockpick")
        let canUnlock = PlanningFact("actor.can.unlock")
        let atA = PlanningFact("actor.at.\(doorID).\(sideA)")
        let atB = PlanningFact("actor.at.\(doorID).\(sideB)")

        return [
            AffordanceAction(
                id: "\(doorID).unlock",
                semantic: .interact(objectID: doorID, kind: .unlock),
                preconditions: [closed, locked, canUnlock],
                adding: [unlocked], removing: [locked], duration: 0.8
            ),
            AffordanceAction(
                id: "\(doorID).lockpick",
                semantic: .interact(objectID: doorID, kind: .lockpick),
                preconditions: [closed, locked, canLockpick],
                adding: [unlocked], removing: [locked],
                duration: lockpickDuration, riskCost: 2
            ),
            AffordanceAction(
                id: "\(doorID).open",
                semantic: .interact(objectID: doorID, kind: .open),
                preconditions: [closed, unlocked],
                adding: [open], removing: [closed], duration: openDuration
            ),
            AffordanceAction(
                id: "\(doorID).traverse.a-b",
                semantic: .traverse(objectID: doorID, fromSide: sideA, toSide: sideB),
                preconditions: [open, atA], adding: [atB], removing: [atA], duration: 0.8
            ),
            AffordanceAction(
                id: "\(doorID).traverse.b-a",
                semantic: .traverse(objectID: doorID, fromSide: sideB, toSide: sideA),
                preconditions: [open, atB], adding: [atA], removing: [atB], duration: 0.8
            ),
            AffordanceAction(
                id: "\(doorID).close.a",
                semantic: .interact(objectID: doorID, kind: .close),
                preconditions: [open, atA], adding: [closed], removing: [open], duration: closeDuration
            ),
            AffordanceAction(
                id: "\(doorID).close.b",
                semantic: .interact(objectID: doorID, kind: .close),
                preconditions: [open, atB], adding: [closed], removing: [open], duration: closeDuration
            )
        ]
    }
}
