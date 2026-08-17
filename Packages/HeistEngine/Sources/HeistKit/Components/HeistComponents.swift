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

/// Marks a floor entity as a valid tap-to-move target.
public struct NavigableSurfaceComponent: Component {
    public init() {}
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

/// The path an actor is currently walking.
///
/// Movement is a straight interpolation along explicit waypoints, never a
/// physics force, so arrival time is a pure function of path length and speed.
public struct PathFollowingComponent: Component {
    public var waypoints: [SIMD3<Float>]
    public var index: Int
    /// How close counts as "arrived at this waypoint", in meters.
    public var arrivalTolerance: Float
    /// Seconds spent without meaningful progress toward the current waypoint.
    /// Used to detect an actor wedged against geometry instead of failing
    /// silently, which is exactly how doorway jams present themselves.
    public var stalledFor: Float
    /// Distance to the current waypoint at the previous update.
    public var lastDistance: Float

    public init(waypoints: [SIMD3<Float>], arrivalTolerance: Float = 0.05) {
        self.waypoints = waypoints
        self.index = 0
        self.arrivalTolerance = arrivalTolerance
        self.stalledFor = 0
        self.lastDistance = .greatestFiniteMagnitude
    }

    public var isFinished: Bool { index >= waypoints.count }

    /// Remaining path length in meters, measured from `position`.
    public func remainingDistance(from position: SIMD3<Float>) -> Float {
        guard !isFinished else { return 0 }
        var total = distance(position, waypoints[index])
        var cursor = index
        while cursor + 1 < waypoints.count {
            total += distance(waypoints[cursor], waypoints[cursor + 1])
            cursor += 1
        }
        return total
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
        NavigableSurfaceComponent.registerComponent()
        PlayableActorComponent.registerComponent()
        PathFollowingComponent.registerComponent()
        InteractableComponent.registerComponent()
        PathFollowingSystem.registerSystem()
    }
}
