import Foundation
import RealityKit
import HeistCore

/// Stable link from a RealityKit entity back to its blueprint element.
///
/// Scene graph names are display detail; plans, logs and save data use this ID.
public struct LevelEntityComponent: Component {
    public var id: String
    public var kind: PropKind

    public init(id: String, kind: PropKind) {
        self.id = id
        self.kind = kind
    }
}

/// Marks an entity the player can select and command.
public struct PlayableActorComponent: Component {
    public var id: String
    /// Meters per second. Constant by design: plan timing must be predictable.
    public var walkSpeed: Float

    public init(id: String, walkSpeed: Float) {
        self.id = id
        self.walkSpeed = walkSpeed
    }
}

/// Shared mission-time locomotion storage for every character role.
/// A thief tap, a guard investigation and a future civilian routine all write
/// the same semantic task; only goal selection differs.
public struct AgentNavigationComponent: Component {
    public var id: String
    public var character: CharacterProfile
    public var task: AgentNavigationTask?
    public var missionTime: Double
    /// Authoritative pose while no task owns the actor. Rendering mirrors this
    /// value; it is never used as a source of simulation state.
    public var restingPosition: WorldPoint
    public var restingFacing: Double
    public var isAnimating: Bool
    public var walkLoopStartsAt: Double?
    public var presentedActivity: AgentNavigationTask.Activity?

    public init(
        id: String,
        character: CharacterProfile,
        missionTime: Double = 0,
        restingPosition: WorldPoint = WorldPoint(x: 0, y: 0, z: 0),
        restingFacing: Double = 0
    ) {
        self.id = id
        self.character = character
        self.task = nil
        self.missionTime = missionTime
        self.restingPosition = restingPosition
        self.restingFacing = restingFacing
        self.isAnimating = false
        self.walkLoopStartsAt = nil
        self.presentedActivity = nil
    }
}

/// A guard walking a fixed route.
///
/// Holds the mission time the guard should be posed for, written by the session
/// each frame. The guard's position is then a lookup, not an accumulation.
public struct GuardComponent: Component {
    public var id: String
    public var route: PatrolRoute
    public var patrolPhaseAtAnchor: Double
    public var patrolAnchorMissionTime: Double
    public var isPatrolPaused: Bool

    public init(id: String, route: PatrolRoute) {
        self.id = id
        self.route = route
        self.patrolPhaseAtAnchor = 0
        self.patrolAnchorMissionTime = 0
        self.isPatrolPaused = false
    }

    public func patrolTime(at missionTime: Double) -> Double {
        patrolPhaseAtAnchor + (isPatrolPaused ? 0 : max(0, missionTime - patrolAnchorMissionTime))
    }

    public mutating func pausePatrol(at missionTime: Double) {
        patrolPhaseAtAnchor = patrolTime(at: missionTime)
        patrolAnchorMissionTime = missionTime
        isPatrolPaused = true
    }

    public mutating func resumePatrol(at missionTime: Double, routeTime: Double) {
        patrolPhaseAtAnchor = routeTime
        patrolAnchorMissionTime = missionTime
        isPatrolPaused = false
    }
}

/// One perception source, independent of whether it is carried by a guard or
/// mounted as a camera. Detection and visualization consume this same value.
public struct VisionSourceComponent: Component {
    public var id: String
    public var kind: VisionSourceKind
    public var config: VisionConfig
    public var eyeHeight: Double
    public var baseFacing: Double
    public var scanArc: Double
    public var scanPeriod: Double
    public var missionTime: Double
    public var isEnabled: Bool
    public var occluders: [WorldBox]
    public var lastPresentationStep: Int

    public init(
        id: String,
        kind: VisionSourceKind,
        config: VisionConfig,
        eyeHeight: Double,
        baseFacing: Double,
        scanArc: Double = 0,
        scanPeriod: Double = 0,
        missionTime: Double = 0,
        isEnabled: Bool = true,
        occluders: [WorldBox]
    ) {
        self.id = id
        self.kind = kind
        self.config = config
        self.eyeHeight = eyeHeight
        self.baseFacing = baseFacing
        self.scanArc = scanArc
        self.scanPeriod = scanPeriod
        self.missionTime = missionTime
        self.isEnabled = isEnabled
        self.occluders = occluders
        self.lastPresentationStep = -1
    }

    public var facing: Double {
        switch kind {
        case .guardActor:
            baseFacing
        case .securityCamera:
            VisionScan.facing(
                baseDegrees: baseFacing,
                arcDegrees: scanArc,
                period: scanPeriod,
                time: missionTime
            )
        }
    }
}

public struct VisionRayComponent: Component {
    public var angleDegrees: Double

    public init(angleDegrees: Double) {
        self.angleDegrees = angleDegrees
    }
}

public struct DoorComponent: Component {
    public var id: String
    public var closedBox: WorldBox
    public var hingeSide: DoorHingeSide
    public var openAngleDegrees: Double
    public var initialFraction: Double
    public var settledFraction: Double
    public var transition: DoorTransition?
    public var missionTime: Double

    public init(
        id: String,
        closedBox: WorldBox,
        hingeSide: DoorHingeSide,
        openAngleDegrees: Double,
        isOpen: Bool
    ) {
        self.id = id
        self.closedBox = closedBox
        self.hingeSide = hingeSide
        self.openAngleDegrees = openAngleDegrees
        self.initialFraction = isOpen ? 1 : 0
        self.settledFraction = self.initialFraction
        self.transition = nil
        self.missionTime = 0
    }

    public func openFraction(at time: Double) -> Double {
        transition?.fraction(at: time) ?? settledFraction
    }

    public func liveBox(at time: Double) -> WorldBox {
        DoorGeometry.leafBox(
            closed: closedBox,
            hingeSide: hingeSide,
            openAngleDegrees: openAngleDegrees,
            openFraction: openFraction(at: time)
        )
    }
}

/// Applied to interactable props so the input layer can offer contextual verbs.
///
/// `config` starts as the prop's resolved catalog config (`locked`, `open`,
/// per-verb durations, whatever else a prototype declares) and is what
/// `InteractionResolver` reads and rewrites as interactions complete — this
/// is the *live* state, separate from the level-authored `PlacedProp.config`
/// it was seeded from, which never changes. Runtime-only, so it does not
/// need to be `Codable`: nothing here persists between sessions yet.
public struct InteractableComponent: Component {
    public var id: String
    public var interactions: [InteractionKind]
    public var isEnabled: Bool
    public var config: [String: LevelValue]

    public init(
        id: String,
        interactions: [InteractionKind],
        isEnabled: Bool = true,
        config: [String: LevelValue] = [:]
    ) {
        self.id = id
        self.interactions = interactions
        self.isEnabled = isEnabled
        self.config = config
    }
}

/// An actor en route to interact with something once it arrives.
///
/// Set beside an `AgentNavigationComponent` task when a tap resolves to an
/// interaction rather than a plain move. The session promotes it to an active
/// interaction when the pure mission-time task reports `arrived`.
public struct PendingInteractionComponent: Component {
    public var propID: String
    public var interaction: InteractionKind
    public var arrivalFacingDegrees: Double

    public init(propID: String, interaction: InteractionKind, arrivalFacingDegrees: Double = 0) {
        self.propID = propID
        self.interaction = interaction
        self.arrivalFacingDegrees = arrivalFacingDegrees
    }
}

/// An actor performing a timed interaction right now.
///
/// `startedAt` is mission-clock time, not a render timestamp — per
/// `docs/CLAUDE.md`'s determinism requirement, whether an interaction has
/// finished must be a pure function of mission time so a replayed plan
/// finishes it at the same instant every time, not whenever a particular
/// frame happens to land.
public struct ActiveInteractionComponent: Component {
    public var propID: String
    public var interaction: InteractionKind
    public var startedAt: Double
    public var duration: Double

    public init(propID: String, interaction: InteractionKind, startedAt: Double, duration: Double) {
        self.propID = propID
        self.interaction = interaction
        self.startedAt = startedAt
        self.duration = duration
    }

    public func isFinished(at missionTime: Double) -> Bool {
        missionTime >= startedAt + duration
    }
}

public enum HeistComponents {
    @MainActor private static var isRegistered = false

    /// Registers every component and system exactly once.
    ///
    /// RealityKit traps on a duplicate registration, and this is called from
    /// every session load and every runtime test, so the guard is load-bearing.
    @MainActor
    public static func registerAll() {
        guard !isRegistered else { return }
        isRegistered = true

        LevelEntityComponent.registerComponent()
        PlayableActorComponent.registerComponent()
        AgentNavigationComponent.registerComponent()
        GuardComponent.registerComponent()
        VisionSourceComponent.registerComponent()
        VisionRayComponent.registerComponent()
        DoorComponent.registerComponent()
        InteractableComponent.registerComponent()
        PendingInteractionComponent.registerComponent()
        ActiveInteractionComponent.registerComponent()
        CharacterActionStateComponent.registerComponent()
        AgentLocomotionSystem.registerSystem()
        VisionPresentationSystem.registerSystem()
        DoorPresentationSystem.registerSystem()
    }
}
