import RealityKit
import HeistCore

/// Presentation adapter for every vision source. Rays are clipped against the
/// same occluder boxes used by detection; they never influence movement.
public struct VisionPresentationSystem: System {
    private static let query = EntityQuery(where: .has(VisionSourceComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var source = entity.components[VisionSourceComponent.self], source.isEnabled else {
                continue
            }

            let pose: (position: WorldPoint, facing: Double) = if
                let guardComponent = entity.components[GuardComponent.self]
            {
                {
                    if let task = entity.components[AgentNavigationComponent.self]?.task {
                        let state = task.state(at: source.missionTime)
                        return (state.position, state.facing)
                    }
                    let patrol = guardComponent.route.state(
                        at: guardComponent.patrolTime(at: source.missionTime)
                    )
                    return (patrol.position, patrol.facing)
                }()
            } else {
                (
                    WorldPoint(
                        x: Double(entity.position.x),
                        y: Double(entity.position.y),
                        z: Double(entity.position.z)
                    ),
                    source.facing
                )
            }

            if source.kind == .securityCamera {
                entity.orientation = simd_quatf(
                    angle: Float(pose.facing * .pi / 180),
                    axis: SIMD3<Float>(0, 1, 0)
                )
            }

            let observer = WorldPoint(
                x: pose.position.x,
                y: source.kind == .guardActor ? source.eyeHeight : pose.position.y,
                z: pose.position.z
            )

            let presentationStep = Int((source.missionTime * 12).rounded(.down))
            guard presentationStep != source.lastPresentationStep,
                  let cone = entity.children.first(where: { $0.name == "vision.cone" }) as? ModelEntity else {
                continue
            }
            let rayCount = 41
            let halfAngle = source.config.fieldOfViewDegrees / 2
            var positions = [SIMD3<Float>(0, 0, 0)]
            for index in 0..<rayCount {
                let progress = Double(index) / Double(rayCount - 1)
                let localAngle = -halfAngle + source.config.fieldOfViewDegrees * progress
                let reach = VisionSolver.visibleReach(
                    observer: observer,
                    targetHeight: 1.5,
                    facingDegrees: pose.facing + localAngle,
                    maxRange: source.config.range,
                    occluders: source.occluders
                )
                let angle = localAngle * .pi / 180
                positions.append(SIMD3<Float>(
                    Float(sin(angle) * reach), 0, Float(cos(angle) * reach)
                ))
            }
            var indices: [UInt32] = []
            for index in 1..<positions.count - 1 {
                indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
            }
            var descriptor = MeshDescriptor(name: "vision.cone.live")
            descriptor.positions = MeshBuffer(positions)
            descriptor.primitives = .triangles(indices)
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                cone.model?.mesh = mesh
            }
            source.lastPresentationStep = presentationStep
            entity.components[VisionSourceComponent.self] = source
        }
    }
}
