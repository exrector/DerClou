import Foundation
import RealityKit
import HeistCore

/// A wall that may need to get out of the way.
///
/// Carries its own dimensions rather than reading them back from the mesh, so
/// the test below is arithmetic on the level's own numbers.
public struct OccludingWallComponent: Component, Sendable {
    public var height: Double
    public var centre: WorldPoint
    public var halfWidth: Double
    public var halfDepth: Double
    /// How faded it currently is, 0 solid to 1 gone. Kept so the fade can be
    /// eased rather than switched.
    public var fade: Float = 0

    public init(height: Double, centre: WorldPoint, halfWidth: Double, halfDepth: Double) {
        self.height = height
        self.centre = centre
        self.halfWidth = halfWidth
        self.halfDepth = halfDepth
    }
}

/// Fades the walls that stand between the camera and the person being watched.
///
/// The standard answer in any game with a fixed oblique view, and the reason the
/// view can be tilted far enough to have depth at all: without it, the near wall
/// of every room hides the room. Better than turning the camera, because the map
/// stays where the player left it.
///
/// The test is geometric and cheap. The camera looks along a known direction, so
/// walking back from the watched actor along that direction gives the segment
/// that anything occluding must cross; a wall occludes when its footprint meets
/// that segment and it is tall enough to matter. No raycast, no physics, and the
/// same answer every frame for the same state — which the replay needs.
@MainActor
public struct WallFadeSystem {
    /// How transparent an occluding wall becomes.
    private static let fadedOpacity: Float = 0.12
    /// Metres of the actor's surroundings that count as "in the way".
    private static let radius = 1.9
    /// How fast the fade eases, in units per second.
    private static let speed: Float = 6

    /// Updates every wall in the level for the current watched position.
    ///
    /// - Parameters:
    ///   - watched: the person the player is following, in level space.
    ///   - direction: the direction the camera looks along.
    public static func update(
        level: BuiltLevel,
        watched: WorldPoint?,
        direction: WorldPoint,
        deltaTime: Double
    ) {
        let step = min(Float(deltaTime) * speed, 1)

        for child in level.root.children {
            guard var wall = child.components[OccludingWallComponent.self] else { continue }

            let wanted: Float = watched.map { occludes(wall, watched: $0, direction: direction) }
                .map { $0 ? 1 : 0 } ?? 0

            guard abs(wall.fade - wanted) > 0.001 else { continue }
            wall.fade += (wanted - wall.fade) * step
            if abs(wall.fade - wanted) < 0.01 { wall.fade = wanted }
            child.components.set(wall)

            apply(fade: wall.fade, to: child)
        }
    }

    /// Whether a wall stands between the camera and the watched point.
    static func occludes(
        _ wall: OccludingWallComponent,
        watched: WorldPoint,
        direction: WorldPoint
    ) -> Bool {
        // Anything shorter than waist height cannot hide a person.
        guard wall.height > 1.0 else { return false }

        // Walk back from the actor toward the camera. A wall is in the way if it
        // covers any of that walk *and* stands higher than the line of sight
        // reaches at that point.
        let back = direction * -1
        var travelled = 0.4
        while travelled < 9 {
            let point = watched + back * travelled
            let inside = abs(point.x - wall.centre.x) <= wall.halfWidth + 0.15
                && abs(point.z - wall.centre.z) <= wall.halfDepth + 0.15
            if inside, point.y < wall.height { return true }
            travelled += 0.35
        }
        return false
    }

    private static func apply(fade: Float, to entity: Entity) {
        guard var model = entity.components[ModelComponent.self] else { return }
        let opacity = 1 - fade * (1 - fadedOpacity)

        model.materials = model.materials.map { material in
            guard var physical = material as? PhysicallyBasedMaterial else { return material }
            physical.blending = opacity < 0.999
                ? .transparent(opacity: .init(floatLiteral: opacity))
                : .opaque
            return physical
        }
        entity.components.set(model)
    }
}
