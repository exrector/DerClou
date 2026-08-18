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

    public init(waypoints: [WorldPoint]) {
        self.walker = PathWalker(waypoints: waypoints)
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
public struct InteractableComponent: Component {
    public var id: String
    public var interactions: [InteractionKind]
    public var isEnabled: Bool

    public init(id: String, interactions: [InteractionKind], isEnabled: Bool = true) {
        self.id = id
        self.interactions = interactions
        self.isEnabled = isEnabled
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
        OccludingWallComponent.registerComponent()
        PathFollowingSystem.registerSystem()
        GuardPatrolSystem.registerSystem()
    }
}
