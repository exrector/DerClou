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

/// The route an actor is currently walking.
///
/// Holds a `PathWalker` from `HeistCore`: the component is storage, the walking
/// rules live where they can be tested.
public struct PathFollowingComponent: Component {
    public var walker: PathWalker
    public var isAnimating: Bool

    public init(waypoints: [WorldPoint]) {
        self.walker = PathWalker(waypoints: waypoints)
        self.isAnimating = false
    }
}

/// A guard walking a fixed route.
///
/// Holds the mission time the guard should be posed for, written by the session
/// each frame. The guard's position is then a lookup, not an accumulation.
public struct GuardComponent: Component {
    public var id: String
    public var route: PatrolRoute
    /// Seconds into the mission, as of the last update.
    public var missionTime: Double

    public init(id: String, route: PatrolRoute, missionTime: Double = 0) {
        self.id = id
        self.route = route
        self.missionTime = missionTime
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
/// Set alongside `PathFollowingComponent` when a tap resolves to an
/// interaction rather than a plain move. The session watches for this
/// component surviving *without* `PathFollowingComponent` any more — that is
/// what "arrived" means — and promotes it to `ActiveInteractionComponent`.
/// Two components rather than one combined "walking to interact" component
/// because `PathFollowingSystem` only ever needs to know about
/// `PathFollowingComponent`; teaching it about interactions too would mean a
/// generic movement system reaching into a concern that is not its own.
public struct PendingInteractionComponent: Component {
    public var propID: String
    public var interaction: InteractionKind

    public init(propID: String, interaction: InteractionKind) {
        self.propID = propID
        self.interaction = interaction
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
        PathFollowingComponent.registerComponent()
        GuardComponent.registerComponent()
        InteractableComponent.registerComponent()
        PendingInteractionComponent.registerComponent()
        ActiveInteractionComponent.registerComponent()
        PathFollowingSystem.registerSystem()
        GuardPatrolSystem.registerSystem()
    }
}
