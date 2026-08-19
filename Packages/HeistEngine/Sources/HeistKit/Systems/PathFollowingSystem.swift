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
                startWalkingAnimation(for: entity)
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

    @MainActor
    private func startWalkingAnimation(for entity: Entity) {
        for child in entity.children {
            if let anim = child.availableAnimations.first {
                _ = child.playAnimation(anim.repeat(), transitionDuration: 0.15)
            }
        }
    }

    @MainActor
    private func stopWalkingAnimation(for entity: Entity) {
        for child in entity.children {
            child.stopAllAnimations()
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
