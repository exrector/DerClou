import Foundation
import OSLog
import RealityKit
import HeistCore

/// Drives entities along their route and turns them to face travel.
///
/// A thin adapter: the walking itself is `PathWalker` in `HeistCore`, which is
/// where it can be unit tested. This system only converts between RealityKit
/// transforms and world points, and reports stalls.
public struct PathFollowingSystem: System {
    private static let log = Logger(subsystem: "com.exrector.DerClou", category: "movement")

    private static let query = EntityQuery(
        where: .has(PathFollowingComponent.self) && .has(PlayableActorComponent.self)
    )

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        let deltaTime = Double(context.deltaTime)
        guard deltaTime > 0 else { return }

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var component = entity.components[PathFollowingComponent.self],
                  let actor = entity.components[PlayableActorComponent.self] else { continue }

            // Level space, not world space: the scene may be leaning, and
            // walking a route must not care how it is being drawn.
            let position = entity.position
            let step = component.walker.advance(
                from: WorldPoint(x: Double(position.x), y: 0, z: Double(position.z)),
                speed: Double(actor.walkSpeed),
                deltaTime: deltaTime
            )

            entity.position = SIMD3<Float>(
                Float(step.position.x), position.y, Float(step.position.z)
            )

            if let facing = step.facing {
                face(entity: entity, direction: facing)
            }

            if !component.isAnimating {
                startWalkingAnimation(for: entity, walkSpeed: actor.walkSpeed)
                component.isAnimating = true
            }

            if step.isStalled {
                let actorID = actor.id
                Self.log.error("""
                    \(actorID, privacy: .public) made no progress toward waypoint \
                    \(component.walker.index, privacy: .public); abandoning route
                    """)
                stopWalkingAnimation(for: entity)
                entity.components.remove(PathFollowingComponent.self)
                continue
            }

            if step.isFinished {
                stopWalkingAnimation(for: entity)
                entity.components.remove(PathFollowingComponent.self)
                continue
            }

            entity.components[PathFollowingComponent.self] = component
        }
    }

    /// The real-world pace the current "Walk" clip (a retargeted Mixamo
    /// mocap cycle, applied to every character via
    /// ArtSource/Tools/apply_animation.py from Standard Walk.fbx) was
    /// actually captured at — measured, not assumed: the clip's Hips bone
    /// travels 174.23 raw Blender units (== 1.7423 m once the standard
    /// Mixamo-import 0.01 object scale is applied) over 35 frames at the
    /// file's own 30 fps, i.e. 1.167 s, giving 1.7423 / 1.167 ≈ 1.49 m/s.
    /// apply_animation.py strips that drift back out of the exported asset
    /// — it keeps only the cyclic sway/bob — but the *rate* the clip was
    /// captured at still has to be known so playback can be re-timed to
    /// each entity's actual `walkSpeed`, per CLAUDE.md's "Locomotion versus
    /// game movement" (animation presents movement, it does not drive it:
    /// the entity's translation comes entirely from `PathWalker` above).
    ///
    /// This replaced an earlier clip (plain "Walking.fbx" from the same
    /// Mixamo download batch) captured at an unusually slow ≈0.27 m/s — a
    /// leisurely amble, not a normal walking pace. Matching that to this
    /// project's actual walkSpeeds (1.1-1.4 m/s) meant playing it back at
    /// 4-5x its own rate, and no amount of linear time-scaling makes mocap
    /// look right stretched that far — stride timing and ground contact
    /// stop reading as a real gait, which is exactly the "walks like a
    /// heron" the owner flagged. Standard Walk.fbx's native pace needs only
    /// about a 1x multiplier at these walkSpeeds, close enough to its own
    /// capture rate to look like an actual person walking.
    ///
    /// That split is exactly why the cycle *rate* still has to track speed
    /// even though position does not: two actors with different `walkSpeed`
    /// cover different ground per second while their legs would otherwise
    /// cycle at the identical fixed rate, which reads as the slower one's
    /// feet sliding and the faster one's legs lagging behind its own body.
    private static let referenceWalkSpeed: Float = 1.49

    @MainActor
    private func startWalkingAnimation(for entity: Entity, walkSpeed: Float) {
        // How much faster or slower than the speed the cycle was authored
        // for — `AnimationPlaybackController.speed` is a rate multiplier,
        // not a duration, so this is the whole adjustment.
        let rate = walkSpeed / Self.referenceWalkSpeed
        for child in entity.children {
            if let anim = child.availableAnimations.first {
                let controller = child.playAnimation(anim.repeat(), transitionDuration: 0.15)
                controller.speed = rate
            }
        }
    }

    @MainActor
    private func stopWalkingAnimation(for entity: Entity) {
        for child in entity.children {
            if let anim = child.availableAnimations.first {
                let controller = child.playAnimation(anim, transitionDuration: 0.15)
                controller.time = 0.0
                controller.pause()
            } else {
                child.stopAllAnimations()
            }
        }
    }

    @MainActor
    private func face(entity: Entity, direction: WorldPoint) {
        guard direction.planarLength > 0.0001 else { return }
        // Model forward is +z, matching the blueprint's rotation convention.
        let yaw = atan2(Float(direction.x), Float(direction.z))
        entity.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
}
