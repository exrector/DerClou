import RealityKit
import HeistCore

/// The only RealityKit system allowed to write character locomotion transforms.
/// Authoritative mission state is resolved first; the shared GameplayKit-backed
/// action state machine then presents the matching animation block for every
/// actor role.
public struct AgentLocomotionSystem: System {
    private static let query = EntityQuery(where: .has(AgentNavigationComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var navigation = entity.components[AgentNavigationComponent.self] else { continue }

            let pose: PatrolRoute.State
            let intent: CharacterActionIntent
            let taskActivity: AgentNavigationTask.Activity?

            if let active = entity.components[ActiveInteractionComponent.self] {
                pose = PatrolRoute.State(
                    position: navigation.restingPosition,
                    facing: navigation.restingFacing,
                    activity: .waiting
                )
                intent = CharacterActionIntentResolver.interaction(active.interaction)
                taskActivity = nil
            } else if let task = navigation.task {
                let state = task.state(at: navigation.missionTime)
                let translates = switch state.activity {
                case .starting, .walking, .braking, .shortStep: true
                case .turningLeft, .turningRight, .turningAround, .arrived, .blocked: false
                }
                pose = PatrolRoute.State(
                    position: state.position,
                    facing: state.facing,
                    activity: translates ? .walking : .waiting
                )
                intent = CharacterActionIntentResolver.task(
                    state,
                    character: navigation.character
                )
                taskActivity = state.activity
            } else if let guardComponent = entity.components[GuardComponent.self] {
                let state = guardComponent.route.state(
                    at: guardComponent.patrolTime(at: navigation.missionTime)
                )
                pose = state
                intent = CharacterActionIntentResolver.patrol(
                    state,
                    speed: guardComponent.route.speed,
                    character: navigation.character
                )
                taskActivity = nil
            } else {
                pose = PatrolRoute.State(
                    position: navigation.restingPosition,
                    facing: navigation.restingFacing,
                    activity: .waiting
                )
                intent = CharacterActionIntentResolver.idle
                taskActivity = nil
            }

            entity.position = SIMD3<Float>(Float(pose.position.x), 0, Float(pose.position.z))
            entity.orientation = simd_quatf(
                angle: Float(pose.facing * .pi / 180),
                axis: SIMD3<Float>(0, 1, 0)
            )

            var actionState = entity.components[CharacterActionStateComponent.self]
                ?? CharacterActionStateComponent(missionTime: navigation.missionTime)
            actionState.synchronize(
                to: intent,
                on: entity,
                missionTime: navigation.missionTime
            )
            entity.components[CharacterActionStateComponent.self] = actionState

            // Compatibility fields remain readable during migration, but all
            // animation decisions now come from CharacterActionStateComponent.
            navigation.isAnimating = intent.phase != .idle && intent.phase != .blocked
            navigation.walkLoopStartsAt = nil
            navigation.presentedActivity = taskActivity
            entity.components[AgentNavigationComponent.self] = navigation
        }
    }
}
