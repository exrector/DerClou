import RealityKit

/// Applies the pure mission-time `DoorTransition` to a hinge transform.
public struct DoorPresentationSystem: System {
    private static let query = EntityQuery(where: .has(DoorComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var door = entity.components[DoorComponent.self],
                  let hinge = entity.children.first(where: { $0.name == "door.hinge" }) else {
                continue
            }
            let fraction = door.openFraction(at: door.missionTime)
            hinge.orientation = simd_quatf(
                angle: Float(door.openAngleDegrees * fraction * .pi / 180),
                axis: SIMD3<Float>(0, 1, 0)
            )
            if let transition = door.transition, transition.isFinished(at: door.missionTime) {
                door.settledFraction = transition.toFraction
                door.transition = nil
                entity.components[DoorComponent.self] = door
            }
        }
    }
}
