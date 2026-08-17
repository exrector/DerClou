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
    /// Meters per second. Constant by design: plan timing must be predictable.
    public var walkSpeed: Double

    public init(width: Double, height: Double, walkSpeed: Double) {
        self.width = width
        self.height = height
        self.walkSpeed = walkSpeed
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
            walkSpeed: resolved["walkSpeed"]?.doubleValue ?? CharacterProfile.fallbackWalkSpeed
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
