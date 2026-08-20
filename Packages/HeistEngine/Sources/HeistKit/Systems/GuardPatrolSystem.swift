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
            guard var guardComponent = entity.components[GuardComponent.self] else { continue }

            let state = guardComponent.route.state(at: guardComponent.missionTime)

            // Level space: a patrol is a function of mission time, not of how
            // the scene happens to be leaning.
            entity.position = SIMD3<Float>(Float(state.position.x), 0, Float(state.position.z))
            entity.orientation = simd_quatf(
                angle: Float(state.facing * .pi / 180), axis: SIMD3<Float>(0, 1, 0)
            )

            // A guard's position is a pure time lookup (see PatrolRoute's own
            // docs) rather than something PathFollowingSystem accumulates for
            // it, so nothing else here was ever driving its Walk animation —
            // it moved while its model stayed frozen on whatever frame
            // LevelSceneBuilder had paused it on at load, i.e. it slid rather
            // than walked. Same rule as the Thief now: play while moving,
            // rest at the waypoint pause.
            if state.isPaused {
                if guardComponent.isAnimating {
                    WalkAnimationSync.stopWalking(for: entity)
                    guardComponent.isAnimating = false
                }
            } else if !guardComponent.isAnimating {
                WalkAnimationSync.startWalking(for: entity, walkSpeed: Float(guardComponent.route.speed))
                guardComponent.isAnimating = true
            }

            entity.components[GuardComponent.self] = guardComponent
        }
    }
}
