import Foundation
import RealityKit
import HeistCore

/// A blueprint turned into a live RealityKit scene.
public struct BuiltLevel {
    public let blueprint: LevelBlueprint
    public let geometry: LevelGeometry
    public let root: Entity
    /// Actor entities by stable blueprint ID.
    public let actors: [String: Entity]
    /// Baked navigation mesh, nil if baking failed.
    public let navigationMesh: NavigationMeshResource?
    /// Problems the validator found. Errors mean the level is not trustworthy.
    public let issues: [LevelIssue]
}

/// Builds a RealityKit scene from level data.
///
/// There is no per-level code here on purpose: everything this reads comes from
/// the blueprint and the catalog, so a second level costs data, not Swift.
@MainActor
public enum LevelSceneBuilder {
    public static func build(
        _ blueprint: LevelBlueprint,
        catalog: PropCatalog = .standard
    ) -> BuiltLevel {
        let issues = LevelValidator.validate(blueprint, catalog: catalog)
        let geometry = LevelGeometryBuilder.build(blueprint, catalog: catalog)

        let root = Entity()
        root.name = "level.\(blueprint.id)"

        for box in geometry.floors {
            let entity = GreyboxKit.entity(for: box)
            entity.components.set(LevelEntityComponent(id: box.sourceID, kind: .architecture))
            entity.components.set(NavigableSurfaceComponent())
            entity.collision = CollisionComponent(shapes: [collisionShape(for: box)])
            entity.components.set(InputTargetComponent())
            root.addChild(entity)
        }

        for box in geometry.walls {
            let entity = GreyboxKit.entity(for: box)
            entity.components.set(LevelEntityComponent(id: box.sourceID, kind: .architecture))
            // Walls carry collision for line-of-sight queries later, but they
            // are not input targets: tapping a wall should not steal the tap.
            entity.collision = CollisionComponent(shapes: [collisionShape(for: box)])
            root.addChild(entity)
        }

        for prop in geometry.props {
            let entity = GreyboxKit.entity(for: prop.box, name: prop.id)
            entity.components.set(LevelEntityComponent(id: prop.id, kind: prop.prototype.kind))
            entity.collision = CollisionComponent(shapes: [collisionShape(for: prop.box)])
            if !prop.prototype.interactions.isEmpty {
                entity.components.set(
                    InteractableComponent(id: prop.id, interactions: prop.prototype.interactions)
                )
                entity.components.set(InputTargetComponent())
            }
            root.addChild(entity)
        }

        var actorEntities: [String: Entity] = [:]
        for actor in geometry.actors {
            let entity = actorEntity(for: actor)
            root.addChild(entity)
            actorEntities[actor.id] = entity
        }

        addLighting(to: root, geometry: geometry, metrics: blueprint.metrics)

        let navigationMesh = NavigationBaker.bake(geometry: geometry)
        if let navigationMesh {
            root.components.set(NavigationMeshComponent(navigationMeshes: [navigationMesh]))
        }

        return BuiltLevel(
            blueprint: blueprint,
            geometry: geometry,
            root: root,
            actors: actorEntities,
            navigationMesh: navigationMesh,
            issues: issues
        )
    }

    // MARK: - Pieces

    private static func collisionShape(for box: WorldBox) -> ShapeResource {
        .generateBox(
            width: Float(box.width),
            height: Float(box.height),
            depth: Float(box.depth)
        )
    }

    /// Placeholder actor: a body and a head so facing is readable from above.
    ///
    /// Kept as a container entity with visual children so swapping in a rigged
    /// character later does not disturb movement, selection or navigation.
    private static func actorEntity(for actor: PlacedProp) -> Entity {
        let container = Entity()
        container.name = actor.id
        container.setPosition(
            SIMD3<Float>(Float(actor.box.center.x), 0, Float(actor.box.center.z)),
            relativeTo: nil
        )
        container.setOrientation(
            simd_quatf(angle: Float(actor.box.yaw * .pi / 180), axis: SIMD3<Float>(0, 1, 0)),
            relativeTo: nil
        )

        let height = Float(actor.prototype.height)
        let radius = Float(actor.prototype.footprint.width / 2)
        let isGuard = actor.prototype.id == "actor.guard"
        let bodyColor = isGuard
            ? PlatformColor(red: 0.62, green: 0.24, blue: 0.22, alpha: 1)
            : PlatformColor(red: 0.20, green: 0.34, blue: 0.52, alpha: 1)

        var bodyMaterial = PhysicallyBasedMaterial()
        bodyMaterial.baseColor = .init(tint: bodyColor)
        bodyMaterial.roughness = .init(floatLiteral: 0.85)

        let bodyHeight = height * 0.75
        let body = ModelEntity(
            mesh: .generateCylinder(height: bodyHeight, radius: radius),
            materials: [bodyMaterial]
        )
        body.name = "\(actor.id).body"
        body.setPosition(SIMD3<Float>(0, bodyHeight / 2, 0), relativeTo: nil)
        container.addChild(body)

        let head = ModelEntity(
            mesh: .generateSphere(radius: radius * 0.75),
            materials: [bodyMaterial]
        )
        head.name = "\(actor.id).head"
        head.setPosition(SIMD3<Float>(0, bodyHeight + radius * 0.6, 0), relativeTo: nil)
        container.addChild(head)

        // Nose cone: with no skeletal animation yet, this is what makes facing
        // legible from a top-down camera.
        var noseMaterial = PhysicallyBasedMaterial()
        noseMaterial.baseColor = .init(tint: PlatformColor(red: 0.92, green: 0.86, blue: 0.62, alpha: 1))
        noseMaterial.roughness = .init(floatLiteral: 0.6)
        let nose = ModelEntity(
            mesh: .generateBox(width: radius * 0.4, height: radius * 0.4, depth: radius * 1.2),
            materials: [noseMaterial]
        )
        nose.name = "\(actor.id).facing"
        nose.setPosition(SIMD3<Float>(0, bodyHeight * 0.9, radius * 0.9), relativeTo: nil)
        container.addChild(nose)

        container.components.set(LevelEntityComponent(id: actor.id, kind: .actor))
        container.components.set(NavigationComponent())

        if actor.prototype.id == "actor.thief" {
            container.components.set(
                PlayableActorComponent(id: actor.id, walkSpeed: Float(actor.walkSpeed))
            )
        }

        container.components.set(CollisionComponent(
            shapes: [.generateCapsule(height: height, radius: radius)]
        ))
        container.components.set(InputTargetComponent())

        return container
    }

    /// Key light plus practicals.
    ///
    /// Shadows are what stop an orthographic top-down view from reading flat, so
    /// the directional light is deliberately angled rather than straight down.
    private static func addLighting(to root: Entity, geometry: LevelGeometry, metrics: LevelMetrics) {
        let key = Entity()
        key.name = "light.key"
        key.components.set(DirectionalLightComponent(
            color: PlatformColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1),
            intensity: 3200
        ))
        key.components.set(DirectionalLightComponent.Shadow(depthBias: 1.5))

        let bounds = boundsOfFloors(geometry)
        key.look(
            at: SIMD3<Float>(Float(bounds.centerX), 0, Float(bounds.centerZ)),
            from: SIMD3<Float>(Float(bounds.centerX - 8), 14, Float(bounds.centerZ - 10)),
            relativeTo: nil
        )
        root.addChild(key)

        let fill = Entity()
        fill.name = "light.fill"
        fill.components.set(DirectionalLightComponent(
            color: PlatformColor(red: 0.62, green: 0.72, blue: 0.95, alpha: 1),
            intensity: 900
        ))
        fill.look(
            at: SIMD3<Float>(Float(bounds.centerX), 0, Float(bounds.centerZ)),
            from: SIMD3<Float>(Float(bounds.centerX + 10), 10, Float(bounds.centerZ + 8)),
            relativeTo: nil
        )
        root.addChild(fill)

        // Practicals: one warm ceiling lamp per floor quadrant, so rooms read as
        // lit spaces rather than a uniformly bright plan.
        let lampHeight = Float(metrics.wallHeight - 0.3)
        for (index, position) in practicalPositions(bounds).enumerated() {
            let lamp = Entity()
            lamp.name = "light.practical.\(index)"
            lamp.components.set(PointLightComponent(
                color: PlatformColor(red: 1.0, green: 0.90, blue: 0.75, alpha: 1),
                intensity: 12000,
                attenuationRadius: 7
            ))
            lamp.setPosition(SIMD3<Float>(position.0, lampHeight, position.1), relativeTo: nil)
            root.addChild(lamp)
        }
    }

    private static func boundsOfFloors(_ geometry: LevelGeometry)
        -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double, centerX: Double, centerZ: Double) {
        guard let first = geometry.floors.first else {
            return (0, 0, 0, 0, 0, 0)
        }
        var minX = first.center.x - first.width / 2
        var maxX = first.center.x + first.width / 2
        var minZ = first.center.z - first.depth / 2
        var maxZ = first.center.z + first.depth / 2
        for floor in geometry.floors.dropFirst() {
            minX = min(minX, floor.center.x - floor.width / 2)
            maxX = max(maxX, floor.center.x + floor.width / 2)
            minZ = min(minZ, floor.center.z - floor.depth / 2)
            maxZ = max(maxZ, floor.center.z + floor.depth / 2)
        }
        return (minX, maxX, minZ, maxZ, (minX + maxX) / 2, (minZ + maxZ) / 2)
    }

    private static func practicalPositions(
        _ bounds: (minX: Double, maxX: Double, minZ: Double, maxZ: Double, centerX: Double, centerZ: Double)
    ) -> [(Float, Float)] {
        let quarterX = bounds.minX + (bounds.maxX - bounds.minX) * 0.25
        let threeQuarterX = bounds.minX + (bounds.maxX - bounds.minX) * 0.75
        let quarterZ = bounds.minZ + (bounds.maxZ - bounds.minZ) * 0.25
        let threeQuarterZ = bounds.minZ + (bounds.maxZ - bounds.minZ) * 0.8
        return [
            (Float(quarterX), Float(quarterZ)),
            (Float(threeQuarterX), Float(quarterZ)),
            (Float(quarterX), Float(threeQuarterZ)),
            (Float(threeQuarterX), Float(threeQuarterZ))
        ]
    }
}
