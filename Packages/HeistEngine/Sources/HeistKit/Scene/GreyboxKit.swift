import Foundation
import RealityKit
import HeistCore

#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#else
import AppKit
public typealias PlatformColor = NSColor
#endif

/// Procedural geometry and materials for the environment kit.
///
/// The art direction, in one place. Settled 2026-08-18 after comparing the
/// original grey-box against a tabletop diorama: the grey-box read as a prison
/// cell — a sealed dark box with nothing outside it — and the diorama read as
/// light, airy and made of real materials. The diorama wins.
///
/// So: warm pale plaster, painted wood, light coming from one warm key with a
/// cool sky fill, and a building that stands *in* somewhere rather than in a
/// void — grass around it, a path up to it, planting near the walls. The
/// exterior is scenery and carries no gameplay, but it is what stops the level
/// feeling sealed, and it gives the eye somewhere for the building to sit.
///
/// Shapes are still primitives. Every prototype carries its final footprint, so
/// replacing one with an authored USDZ is a line in `PropCatalog` and touches no
/// level data.
public enum GreyboxKit {
    /// Colour and PBR response per surface family.
    public static func material(for surface: SurfaceKey) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()

        let (color, roughness, metallic): (PlatformColor, Float, Float) = switch surface {
        case .concrete:
            (PlatformColor(red: 0.83, green: 0.79, blue: 0.72, alpha: 1), 0.92, 0.0)
        case .plaster:
            (PlatformColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1), 0.94, 0.0)
        case .wood:
            (PlatformColor(red: 0.72, green: 0.52, blue: 0.34, alpha: 1), 0.60, 0.0)
        case .metal:
            (PlatformColor(red: 0.72, green: 0.74, blue: 0.77, alpha: 1), 0.35, 1.0)
        case .darkMetal:
            (PlatformColor(red: 0.32, green: 0.34, blue: 0.38, alpha: 1), 0.35, 1.0)
        case .glass:
            (PlatformColor(red: 0.72, green: 0.84, blue: 0.88, alpha: 1), 0.08, 0.0)
        case .fabric:
            (PlatformColor(red: 0.36, green: 0.55, blue: 0.52, alpha: 1), 0.95, 0.0)
        case .emissive:
            (PlatformColor(red: 0.30, green: 0.88, blue: 0.60, alpha: 1), 0.60, 0.0)
        }

        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)

        if surface == .emissive {
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = 2.0
        }

        return material
    }

    /// Builds a model entity for one world box, positioned and yawed in place.
    @MainActor
    public static func entity(for box: WorldBox, name: String? = nil) -> ModelEntity {
        let mesh = MeshResource.generateBox(
            width: Float(box.width),
            height: Float(box.height),
            depth: Float(box.depth)
        )
        let entity = ModelEntity(mesh: mesh, materials: [material(for: box.surface)])
        entity.name = name ?? box.sourceID
        entity.setPosition(
            SIMD3<Float>(Float(box.center.x), Float(box.center.y), Float(box.center.z)),
            relativeTo: nil
        )
        entity.setOrientation(
            simd_quatf(angle: Float(box.yaw * .pi / 180), axis: SIMD3<Float>(0, 1, 0)),
            relativeTo: nil
        )
        return entity
    }

    /// A border of outside, run around the building like the rim of a diorama.
    ///
    /// Deliberately narrow. An earlier version put the building in a landscape
    /// with a path and trees, and the owner's objection was exact: the outside
    /// was eating the playfield. The job here is only to stop the level reading
    /// as a sealed box — a strip of ground, a kerb, and a little planting is
    /// enough to say "this has an outside", and everything past that is screen
    /// the game is not using.
    @MainActor
    public static func surroundings(around geometry: LevelGeometry) -> Entity {
        var minX = 0.0, maxX = 0.0, minZ = 0.0, maxZ = 0.0
        for floor in geometry.floors {
            minX = min(minX, floor.center.x - floor.width / 2)
            maxX = max(maxX, floor.center.x + floor.width / 2)
            minZ = min(minZ, floor.center.z - floor.depth / 2)
            maxZ = max(maxZ, floor.center.z + floor.depth / 2)
        }

        let container = Entity()
        container.name = "environment"

        let width = Float(maxX - minX)
        let depth = Float(maxZ - minZ)
        let centre = SIMD3<Float>(Float((minX + maxX) / 2), 0, Float((minZ + maxZ) / 2))

        /// How far out the rim goes, in meters. One pace of paving and one of
        /// grass, and that is the whole exterior.
        let paving: Float = 1.0
        let grassBand: Float = 1.6
        let rim = paving + grassBand

        let grass = ModelEntity(
            mesh: .generateBox(
                size: SIMD3<Float>(width + rim * 2, 0.24, depth + rim * 2),
                cornerRadius: 0.12
            ),
            materials: [flat(PlatformColor(red: 0.55, green: 0.66, blue: 0.42, alpha: 1), roughness: 0.95)]
        )
        grass.name = "environment.grass"
        // Every layer of ground sits strictly below the level's own floor, whose
        // top is at zero. Getting this wrong buries the floor and every shadow
        // on it under the paving.
        grass.position = centre + SIMD3<Float>(0, -0.26, 0)
        container.addChild(grass)

        let apron = ModelEntity(
            mesh: .generateBox(width: width + paving * 2, height: 0.16, depth: depth + paving * 2),
            materials: [flat(PlatformColor(red: 0.80, green: 0.78, blue: 0.72, alpha: 1), roughness: 0.9)]
        )
        apron.name = "environment.apron"
        apron.position = centre + SIMD3<Float>(0, -0.16, 0)
        container.addChild(apron)

        // Planting on the grass band, spaced along the long sides. Small, and
        // outside the walls, so they never argue with anything in the level.
        let hedge = flat(PlatformColor(red: 0.36, green: 0.50, blue: 0.31, alpha: 1), roughness: 0.95)
        let stride = Double(width) / 6
        for index in 0..<6 {
            let x = Float(minX + stride * (Double(index) + 0.5))
            for z in [centre.z - depth / 2 - rim * 0.6, centre.z + depth / 2 + rim * 0.6] {
                let shrub = ModelEntity(mesh: .generateSphere(radius: 0.34), materials: [hedge])
                shrub.name = "environment.shrub"
                shrub.position = SIMD3<Float>(x, -0.06, z)
                shrub.scale = SIMD3<Float>(1, 0.62, 1)
                container.addChild(shrub)
            }
        }
        for z in [centre.z - depth / 4, centre.z + depth / 4] {
            for x in [centre.x - width / 2 - rim * 0.6, centre.x + width / 2 + rim * 0.6] {
                let shrub = ModelEntity(mesh: .generateSphere(radius: 0.34), materials: [hedge])
                shrub.name = "environment.shrub"
                shrub.position = SIMD3<Float>(x, -0.06, z)
                shrub.scale = SIMD3<Float>(1, 0.62, 1)
                container.addChild(shrub)
            }
        }

        return container
    }

    /// Where the sun is, expressed as what a shadow does.
    ///
    /// The direction it falls, and how far it runs per meter of height. The sun
    /// sits over the left shoulder at about fifty-five degrees, so a two-metre
    /// wall throws about a metre and a half — long enough to read from directly
    /// above, short enough not to swamp the floor plan.
    ///
    /// This one constant is what makes the scene consistent: every shadow in the
    /// level agrees about where the light is.
    public static let sun = (
        direction: (x: 0.88, z: 0.48),
        runPerMeter: 0.70
    )

    /// The shadow something throws on the floor.
    ///
    /// Seen from straight above, a shadow tucked under its own object is
    /// invisible, so it has to be offset by what the sun's angle actually gives:
    /// height times the run. That is also what makes the height of a thing
    /// legible in a plan view — the long shadow of a wall and the short one of a
    /// crate are the depth cue.
    ///
    /// RealityKit's own dynamic shadows are configured and correct here — reach
    /// set against the level's size, small bias, a single directional light,
    /// which is all RealityKit supports — and they do not render in the
    /// simulator, a known weak spot of simulated environments. These are not a
    /// workaround for that: a stylised board-game look wants clean even shadows
    /// anyway, and this is what such games ship.
    @MainActor
    public static func contactShadow(under box: WorldBox) -> ModelEntity {
        let run = box.height * sun.runPerMeter
        let offset = (x: run * sun.direction.x, z: run * sun.direction.z)

        return shadowPatch(
            width: box.width + abs(offset.x),
            depth: box.depth + abs(offset.z),
            at: (x: box.center.x + offset.x / 2, z: box.center.z + offset.z / 2),
            cornerRadius: min(box.width, box.depth) * 0.2,
            opacity: 0.22
        )
    }

    /// The same, for a person: a round footprint and a softer edge.
    @MainActor
    public static func contactShadow(radius: Double, height: Double, at point: WorldPoint) -> ModelEntity {
        let run = height * sun.runPerMeter
        let offset = (x: run * sun.direction.x, z: run * sun.direction.z)

        return shadowPatch(
            width: radius * 2 + abs(offset.x),
            depth: radius * 2 + abs(offset.z),
            at: (x: point.x + offset.x / 2, z: point.z + offset.z / 2),
            cornerRadius: radius,
            opacity: 0.26
        )
    }

    @MainActor
    private static func shadowPatch(
        width: Double,
        depth: Double,
        at point: (x: Double, z: Double),
        cornerRadius: Double,
        opacity: Float
    ) -> ModelEntity {
        var material = UnlitMaterial(color: PlatformColor(white: 0.08, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))

        let entity = ModelEntity(
            mesh: .generateBox(
                size: SIMD3<Float>(Float(width), 0.01, Float(depth)),
                cornerRadius: Float(cornerRadius)
            ),
            materials: [material]
        )
        entity.name = "shadow"
        entity.position = SIMD3<Float>(Float(point.x), 0.011, Float(point.z))
        return entity
    }

    /// A plain matte material. Most of the scenery wants nothing else.
    static func flat(_ colour: PlatformColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: colour)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    /// Outline of a world-space rectangle, drawn flat on the floor.
    ///
    /// Used to show the real system-derived safe gameplay area during greybox
    /// development, so placement can be checked on device rather than guessed.
    @MainActor
    public static func boundsOutline(
        minX: Float,
        maxX: Float,
        minZ: Float,
        maxZ: Float,
        thickness: Float = 0.06
    ) -> Entity {
        let container = Entity()
        container.name = "debug.safeBounds"

        var material = PhysicallyBasedMaterial()
        let color = PlatformColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1)
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 2.5
        material.roughness = .init(floatLiteral: 0.6)

        let width = maxX - minX
        let depth = maxZ - minZ
        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2

        let edges: [(w: Float, d: Float, x: Float, z: Float)] = [
            (width, thickness, centerX, minZ),
            (width, thickness, centerX, maxZ),
            (thickness, depth, minX, centerZ),
            (thickness, depth, maxX, centerZ)
        ]

        for (index, edge) in edges.enumerated() {
            let bar = ModelEntity(
                mesh: .generateBox(width: edge.w, height: 0.01, depth: edge.d),
                materials: [material]
            )
            bar.name = "debug.safeBounds.\(index)"
            bar.setPosition(SIMD3<Float>(edge.x, 0.015, edge.z), relativeTo: nil)
            container.addChild(bar)
        }

        return container
    }

    /// A flat marker disc, used for the debug destination indicator.
    @MainActor
    public static func destinationMarker() -> ModelEntity {
        let mesh = MeshResource.generateCylinder(height: 0.02, radius: 0.28)
        var material = PhysicallyBasedMaterial()
        let color = PlatformColor(red: 0.35, green: 0.95, blue: 0.55, alpha: 1)
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 3.0
        material.roughness = .init(floatLiteral: 0.5)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "debug.destination"
        return entity
    }
}
