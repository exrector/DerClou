import Foundation
import RealityKit
import HeistCore

/// A blueprint turned into a live RealityKit scene.
public struct BuiltLevel {
    /// Everything computed from the blueprint: geometry, navigation, issues.
    public let build: LevelBuild
    public let root: Entity
    /// Actor entities by stable blueprint ID.
    public let actors: [String: Entity]

    public var blueprint: LevelBlueprint { build.blueprint }
    public var geometry: LevelGeometry { build.geometry }
    public var navGrid: NavGrid { build.grid }
    public var issues: [LevelIssue] { build.issues }
}

/// Builds a RealityKit scene from level data.
///
/// There is no per-level code here on purpose: everything this reads comes from
/// the blueprint and the catalog, so a second level costs data, not Swift.
@MainActor
public enum LevelSceneBuilder {
    public static func build(
        _ blueprint: LevelBlueprint,
        catalog: PropCatalog = .standard,
        quality: RenderQuality = .recommended()
    ) -> BuiltLevel {
        build(LevelBuild.make(blueprint, catalog: catalog), quality: quality)
    }

    /// Renders an already-prepared level.
    public static func build(_ prepared: LevelBuild, quality: RenderQuality = .recommended()) -> BuiltLevel {
        let blueprint = prepared.blueprint
        let geometry = prepared.geometry

        let root = Entity()
        root.name = "level.\(blueprint.id)"

        // The land first: grass, a path, planting, a couple of trees. Scenery
        // only, but it is what stops the level reading as a sealed box.
        root.addChild(GreyboxKit.surroundings(around: geometry))

        for box in geometry.floors {
            let entity = GreyboxKit.entity(for: box)
            entity.components.set(LevelEntityComponent(id: box.sourceID, kind: .architecture))
            entity.collision = CollisionComponent(shapes: [collisionShape(for: box)])
            root.addChild(entity)
        }

        for box in geometry.walls {
            let entity = GreyboxKit.entity(for: box)
            entity.components.set(LevelEntityComponent(id: box.sourceID, kind: .architecture))
            // Walls carry collision for line-of-sight queries later, but they
            // are not input targets: tapping a wall should not steal the tap.
            entity.collision = CollisionComponent(shapes: [collisionShape(for: box)])
            entity.components.set(OccludingWallComponent(
                height: box.height,
                centre: WorldPoint(x: box.center.x, y: box.center.y, z: box.center.z),
                halfWidth: box.width / 2,
                halfDepth: box.depth / 2
            ))
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
            }
            root.addChild(entity)
        }

        var actorEntities: [String: Entity] = [:]
        for actor in geometry.actors {
            // A patrol route turns a placement into a guard. Levels say where
            // the route goes; the system decides how to walk it.
            let spec = blueprint.actors.first { $0.id == actor.id }
            let route = spec.flatMap {
                PatrolRoute(actor: $0, metrics: blueprint.metrics, character: actor.character)
            }
            let entity = actorEntity(for: actor, route: route)
            root.addChild(entity)
            actorEntities[actor.id] = entity
        }

        addLighting(to: root, geometry: geometry, metrics: blueprint.metrics, quality: quality)

        return BuiltLevel(build: prepared, root: root, actors: actorEntities)
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
    private static func actorEntity(for actor: PlacedProp, route: PatrolRoute?) -> Entity {
        let container = Entity()
        container.name = actor.id
        container.position = SIMD3<Float>(Float(actor.box.center.x), 0, Float(actor.box.center.z))
        container.orientation = simd_quatf(
            angle: Float(actor.box.yaw * .pi / 180), axis: SIMD3<Float>(0, 1, 0)
        )

        let height = Float(actor.prototype.height)
        let radius = Float(actor.prototype.footprint.width / 2)
        let isGuard = actor.prototype.id == "actor.guard"
        let bodyColor = isGuard
            ? PlatformColor(red: 0.78, green: 0.34, blue: 0.30, alpha: 1)
            : PlatformColor(red: 0.28, green: 0.46, blue: 0.72, alpha: 1)

        // A pawn: a base, a tapered body and a head. It reads as a figure from
        // above *and* from the tactical angle, which a cylinder does not, and it
        // is the shape a board game would use.
        let material = GreyboxKit.flat(bodyColor, roughness: 0.55)

        let base = ModelEntity(
            mesh: .generateCylinder(height: 0.06, radius: radius * 1.25),
            materials: [material]
        )
        base.name = "\(actor.id).base"
        base.position = SIMD3<Float>(0, 0.03, 0)
        container.addChild(base)

        let bodyHeight = height * 0.62
        let body = ModelEntity(
            mesh: .generateCone(height: bodyHeight, radius: radius * 0.95),
            materials: [material]
        )
        body.name = "\(actor.id).body"
        body.position = SIMD3<Float>(0, 0.06 + bodyHeight / 2, 0)
        container.addChild(body)

        let head = ModelEntity(
            mesh: .generateSphere(radius: radius * 0.66),
            materials: [material]
        )
        head.name = "\(actor.id).head"
        head.position = SIMD3<Float>(0, 0.06 + bodyHeight + radius * 0.5, 0)
        container.addChild(head)

        // Facing, as a wedge on the base. Legible from any of the angles the
        // camera can reach, unlike a nose on the body.
        let facing = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(radius * 0.5, 0.05, radius * 0.9), cornerRadius: 0.02),
            materials: [GreyboxKit.flat(
                PlatformColor(red: 0.98, green: 0.92, blue: 0.72, alpha: 1),
                roughness: 0.5
            )]
        )
        facing.name = "\(actor.id).facing"
        facing.position = SIMD3<Float>(0, 0.07, radius * 1.15)
        container.addChild(facing)

        container.components.set(LevelEntityComponent(id: actor.id, kind: .actor))

        if actor.prototype.id == "actor.thief" {
            container.components.set(
                PlayableActorComponent(id: actor.id, walkSpeed: Float(actor.character.walkSpeed))
            )
        }

        if let route {
            container.components.set(GuardComponent(id: actor.id, route: route))
        }

        container.components.set(CollisionComponent(
            shapes: [.generateCapsule(height: height, radius: radius)]
        ))

        return container
    }

    /// One warm key with shadows, a cool sky fill, and practicals inside.
    ///
    /// The key is angled rather than overhead: a tilted view lives on the shadows
    /// that walls and furniture cast across the floor, and straight-down light
    /// gives none. The fill is blue because the light not coming from the sun
    /// comes from the sky, and that is what keeps the shadow sides from going
    /// muddy — it is most of what makes the scene read as airy rather than sealed.
    private static func addLighting(
        to root: Entity,
        geometry: LevelGeometry,
        metrics: LevelMetrics,
        quality: RenderQuality
    ) {
        let bounds = boundsOfFloors(geometry)
        let centre = SIMD3<Float>(Float(bounds.centerX), 0, Float(bounds.centerZ))

        let key = Entity()
        key.name = "light.key"
        key.components.set(DirectionalLightComponent(
            color: PlatformColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 1),
            intensity: 8000
        ))
        // The shadow's reach has to be stated: it defaults to five metres, and a
        // level is twenty-four across, so with the default the scene renders
        // completely unshadowed and reads as flat paper. Measured, not guessed.
        let reach = Float(max(
            bounds.maxX - bounds.minX,
            bounds.maxZ - bounds.minZ
        ) * 1.6 + 20)
        key.components.set(DirectionalLightComponent.Shadow(
            shadowProjection: .automatic(maximumDistance: reach),
            depthBias: quality.shadowDepthBias
        ))
        key.look(
            at: centre,
            from: centre + SIMD3<Float>(-11, 9, -6),
            relativeTo: nil
        )
        root.addChild(key)

        let sky = Entity()
        sky.name = "light.sky"
        sky.components.set(DirectionalLightComponent(
            color: PlatformColor(red: 0.66, green: 0.78, blue: 0.98, alpha: 1),
            intensity: 1400
        ))
        sky.look(
            at: centre,
            from: centre + SIMD3<Float>(8, 11, 9),
            relativeTo: nil
        )
        root.addChild(sky)

        let bounce = Entity()
        bounce.name = "light.bounce"
        bounce.components.set(DirectionalLightComponent(
            color: PlatformColor(red: 0.85, green: 0.82, blue: 0.74, alpha: 1),
            intensity: 450
        ))
        bounce.look(at: centre, from: centre + SIMD3<Float>(2, 3, -12), relativeTo: nil)
        root.addChild(bounce)

        // Practicals: one warm lamp per quadrant of the plan, so rooms read as
        // lit spaces rather than as a uniformly bright drawing.
        let lampHeight = Float(metrics.wallHeight - 0.3)
        for (index, position) in practicalPositions(bounds, budget: quality.practicalLightBudget).enumerated() {
            let lamp = Entity()
            lamp.name = "light.practical.\(index)"
            lamp.components.set(PointLightComponent(
                color: PlatformColor(red: 1.0, green: 0.92, blue: 0.80, alpha: 1),
                intensity: 6000,
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

    /// Ceiling lamps spread over the floor plan, so rooms read as lit spaces
    /// rather than a uniformly bright plan. Count scales with the device.
    private static func practicalPositions(
        _ bounds: (minX: Double, maxX: Double, minZ: Double, maxZ: Double, centerX: Double, centerZ: Double),
        budget: Int
    ) -> [(Float, Float)] {
        let width = bounds.maxX - bounds.minX
        let depth = bounds.maxZ - bounds.minZ

        // Lay the budget out as a grid biased to the wider axis.
        let columns = max(1, Int((Double(budget) * width / max(depth, 0.001)).squareRoot().rounded()))
        let rows = max(1, Int((Double(budget) / Double(columns)).rounded(.up)))

        var positions: [(Float, Float)] = []
        for row in 0..<rows {
            for column in 0..<columns where positions.count < budget {
                let x = bounds.minX + width * (Double(column) + 0.5) / Double(columns)
                let z = bounds.minZ + depth * (Double(row) + 0.5) / Double(rows)
                positions.append((Float(x), Float(z)))
            }
        }
        return positions
    }
}
