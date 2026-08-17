import Foundation
import RealityKit

/// Walks entities along their path at a constant speed and turns them to face
/// the direction of travel.
///
/// Deliberately kinematic: transforms are written directly, never nudged by
/// physics. Timing stays a function of distance and speed, which is what makes
/// a plan's ETA trustworthy.
public struct PathFollowingSystem: System {
    private static let query = EntityQuery(
        where: .has(PathFollowingComponent.self) && .has(PlayableActorComponent.self)
    )

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        guard deltaTime > 0 else { return }

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var path = entity.components[PathFollowingComponent.self],
                  let actor = entity.components[PlayableActorComponent.self] else { continue }

            if path.isFinished {
                entity.components.remove(PathFollowingComponent.self)
                continue
            }

            var position = entity.position(relativeTo: nil)
            var budget = actor.walkSpeed * deltaTime

            while budget > 0, !path.isFinished {
                let target = path.waypoints[path.index]
                let toTarget = target - position
                let remaining = length(toTarget)

                if remaining <= max(path.arrivalTolerance, budget) {
                    position = target
                    budget -= remaining
                    path.index += 1
                    continue
                }

                let direction = toTarget / remaining
                position += direction * budget
                budget = 0
                face(entity: entity, direction: direction)
            }

            if path.isFinished, path.index > 0 {
                // Keep the final facing rather than snapping back to identity.
                entity.setPosition(position, relativeTo: nil)
                entity.components.remove(PathFollowingComponent.self)
                continue
            }

            entity.setPosition(position, relativeTo: nil)
            entity.components[PathFollowingComponent.self] = path
        }
    }

    private func face(entity: Entity, direction: SIMD3<Float>) {
        let flat = SIMD3<Float>(direction.x, 0, direction.z)
        guard length(flat) > 0.0001 else { return }
        // Model forward is +z, matching the blueprint's rotation convention.
        let yaw = atan2(flat.x, flat.z)
        entity.setOrientation(simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)), relativeTo: nil)
    }
}
