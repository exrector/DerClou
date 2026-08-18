import SwiftUI
import RealityKit
import HeistCore

/// Same scene as before, but floor/block/light are children of a wrapper
/// `root` entity — the way the real level builds it — instead of being top
/// -level siblings in `content.entities`. Isolating whether nesting under a
/// container is what breaks the shadow.
///
/// Launch with `PROBE=1`.
struct ShadowProbe: View {
    var body: some View {
        RealityView { content in
            content.camera = .virtual

            let camera = Entity()
            var camComponent = PerspectiveCameraComponent(near: 0.05, far: 400, fieldOfViewInDegrees: 3)
            camComponent.fieldOfViewOrientation = .vertical
            camera.components.set(camComponent)
            camera.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(0, 200, 0), relativeTo: nil)
            content.entities.append(camera)

            // The wrapper. Everything else becomes its children instead of
            // going straight into content.entities.
            let root = Entity()
            content.entities.append(root)

            var floorMaterial = PhysicallyBasedMaterial()
            floorMaterial.baseColor = .init(tint: .init(white: 0.85, alpha: 1))
            floorMaterial.roughness = .init(floatLiteral: 0.9)
            floorMaterial.metallic = .init(floatLiteral: 0)
            let floor = ModelEntity(
                mesh: .generateBox(width: 10, height: 0.2, depth: 10),
                materials: [floorMaterial]
            )
            floor.position = SIMD3<Float>(0, -0.1, 0)
            floor.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
            root.addChild(floor)

            var blockMaterial = PhysicallyBasedMaterial()
            blockMaterial.baseColor = .init(tint: .init(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
            blockMaterial.roughness = .init(floatLiteral: 0.7)
            blockMaterial.metallic = .init(floatLiteral: 0)
            let block = ModelEntity(
                mesh: .generateBox(width: 1, height: 3, depth: 1),
                materials: [blockMaterial]
            )
            block.position = SIMD3<Float>(0, 1.5, 0)
            block.components.set(DynamicLightShadowComponent(castsShadow: true))
            block.components.set(GroundingShadowComponent(castsShadow: true, receivesShadow: false))
            root.addChild(block)

            let key = Entity()
            let dist = Float(ProcessInfo.processInfo.environment["DIST"] ?? "") ?? 200
            let bias = Float(ProcessInfo.processInfo.environment["BIAS"] ?? "") ?? 1.0
            key.components.set(DirectionalLightComponent(color: .white, intensity: 5000))
            key.components.set(DirectionalLightComponent.Shadow(
                shadowProjection: .automatic(maximumDistance: dist), depthBias: bias
            ))
            key.look(at: .zero, from: SIMD3<Float>(-6, 6, -3), relativeTo: nil)
            root.addChild(key)
        }
        .ignoresSafeArea()
        .background(.black)
    }
}
