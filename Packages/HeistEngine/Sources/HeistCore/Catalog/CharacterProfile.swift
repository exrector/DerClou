import Foundation

/// The physical dimensions of a character, and everything derived from them.
///
/// **Single source of truth.** Navigation erosion, doorway validation, collision
/// capsules and walk timing all read from here, and here reads from the actor's
/// own catalog prototype. Before this existed the radius, the height and the walk
/// speed were each written down separately in three files, so changing the
/// character in the catalog would silently leave navigation built for the old one
/// — the kind of drift that is invisible until an actor sticks in a doorway.
public struct CharacterProfile: Sendable, Equatable {
    /// Shoulder width, in meters.
    public var width: Double
    /// Standing height, in meters.
    public var height: Double
    /// Maximum comfortable walking speed in meters per second.
    public var walkSpeed: Double
    /// Deterministic locomotion envelope in meters per second squared.
    public var acceleration: Double
    public var deceleration: Double
    /// Additional preferred space between the body's edge and a wall. This is
    /// comfort, not collision clearance: a narrow door may legitimately force
    /// it lower, while an open corridor should not be wall-hugged.
    public var preferredWallClearance: Double
    /// How strongly route cost favours comfortable clearance over raw distance.
    public var wallAvoidanceWeight: Double
    /// Maximum visual/kinematic turn rate used by the trajectory follower.
    public var maximumTurnRateDegrees: Double
    /// Radius used when rounding a path corner, constrained by free space.
    public var preferredCornerRadius: Double
    /// Distance from an interaction slot at which the actor is considered
    /// aligned and may begin a door/tool/object action.
    public var interactionArrivalTolerance: Double

    public init(
        width: Double,
        height: Double,
        walkSpeed: Double,
        acceleration: Double = 2.8,
        deceleration: Double = 3.2,
        preferredWallClearance: Double = 0.45,
        wallAvoidanceWeight: Double = 4,
        maximumTurnRateDegrees: Double = 240,
        preferredCornerRadius: Double = 0.45,
        interactionArrivalTolerance: Double = 0.08
    ) {
        self.width = width
        self.height = height
        self.walkSpeed = walkSpeed
        self.acceleration = acceleration
        self.deceleration = deceleration
        self.preferredWallClearance = preferredWallClearance
        self.wallAvoidanceWeight = wallAvoidanceWeight
        self.maximumTurnRateDegrees = maximumTurnRateDegrees
        self.preferredCornerRadius = preferredCornerRadius
        self.interactionArrivalTolerance = interactionArrivalTolerance
    }

    /// Radius used to erode walkable space and to size the collision capsule.
    public var radius: Double { width / 2 }

    /// How long it takes to walk `distance` meters.
    public func duration(forDistance distance: Double) -> Double {
        guard walkSpeed > 0 else { return .infinity }
        return distance / walkSpeed
    }

    /// Derives the profile from a catalog prototype.
    public init(prototype: PropPrototype, config: [String: LevelValue] = [:]) {
        let resolved = prototype.resolvedConfig(overrides: config)
        self.init(
            width: prototype.footprint.width,
            height: prototype.height,
            walkSpeed: resolved["walkSpeed"]?.doubleValue ?? CharacterProfile.fallbackWalkSpeed,
            acceleration: resolved["acceleration"]?.doubleValue ?? 2.8,
            deceleration: resolved["deceleration"]?.doubleValue ?? 3.2,
            preferredWallClearance: resolved["preferredWallClearance"]?.doubleValue ?? 0.45,
            wallAvoidanceWeight: resolved["wallAvoidanceWeight"]?.doubleValue ?? 4,
            maximumTurnRateDegrees: resolved["maximumTurnRateDegrees"]?.doubleValue ?? 240,
            preferredCornerRadius: resolved["preferredCornerRadius"]?.doubleValue ?? 0.45,
            interactionArrivalTolerance: resolved["interactionArrivalTolerance"]?.doubleValue ?? 0.08
        )
    }

    /// Only used when a prototype declares no walk speed at all.
    public static let fallbackWalkSpeed = 1.4

    /// The profile navigation is built for.
    ///
    /// A level's walkable space is shared by everyone in it, so the mesh has to
    /// suit the widest and tallest actor present — otherwise a guard fits through
    /// a gap the thief was routed around, or vice versa.
    public static func navigationProfile(for prototypes: [PropPrototype]) -> CharacterProfile {
        let actors = prototypes.filter { $0.kind == .actor }
        guard !actors.isEmpty else { return .standard }

        return CharacterProfile(
            width: actors.map(\.footprint.width).max() ?? standard.width,
            height: actors.map(\.height).max() ?? standard.height,
            walkSpeed: standard.walkSpeed
        )
    }

    /// Fallback for levels with no actors at all.
    public static let standard = CharacterProfile(width: 0.6, height: 1.75, walkSpeed: 1.4)
}
