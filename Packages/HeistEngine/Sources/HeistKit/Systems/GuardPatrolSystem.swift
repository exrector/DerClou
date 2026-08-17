import Foundation
import RealityKit
import HeistCore

/// Places patrolling guards according to the mission clock.
///
/// A pure adapter, like `PathFollowingSystem`: the route logic is `PatrolRoute`
/// in `HeistCore`, which answers "where is the guard at time T" directly. This
/// system only asks, and writes the answer into transforms.
///
/// Because position is a lookup rather than an accumulation, a guard cannot
/// drift out of sync after a pause, a frame hitch or a replay.
public struct GuardPatrolSystem: System {
    private static let query = EntityQuery(where: .has(GuardComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let guardComponent = entity.components[GuardComponent.self] else { continue }

            let state = guardComponent.route.state(at: guardComponent.missionTime)

            entity.setPosition(
                SIMD3<Float>(Float(state.position.x), 0, Float(state.position.z)),
                relativeTo: nil
            )
            entity.setOrientation(
                simd_quatf(angle: Float(state.facing * .pi / 180), axis: SIMD3<Float>(0, 1, 0)),
                relativeTo: nil
            )
        }
    }
}
