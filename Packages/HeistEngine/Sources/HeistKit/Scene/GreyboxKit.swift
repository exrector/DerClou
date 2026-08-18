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

    /// The land the building stands on: grass, a path, and some planting.
    ///
    /// Scenery, and none of it is walkable or reaches the navigation grid. It
    /// earns its place by what it does to the eye — a building with ground
    /// around it reads as a place, and one without reads as a box.
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

        // Generous, because the view can be turned and zoomed: the grass has to
        // reach past the corners of the frame at any peek.
        let padding = max(maxX - minX, maxZ - minZ)
        let width = (maxX - minX) + padding * 2
        let depth = (maxZ - minZ) + padding * 2
        let centre = SIMD3<Float>(Float((minX + maxX) / 2), 0, Float((minZ + maxZ) / 2))

        let grass = ModelEntity(
            mesh: .generateBox(width: Float(width), height: 0.3, depth: Float(depth)),
            materials: [flat(PlatformColor(red: 0.52, green: 0.63, blue: 0.40, alpha: 1), roughness: 0.95)]
        )
        grass.name = "environment.grass"
        grass.position = centre + SIMD3<Float>(0, -0.19, 0)
        container.addChild(grass)

        // A paved apron just outside the walls, so the building meets the ground
        // through something rather than being planted in a lawn.
        let apron = ModelEntity(
            mesh: .generateBox(
                width: Float(maxX - minX) + 2.4,
                height: 0.08,
                depth: Float(maxZ - minZ) + 2.4
            ),
            materials: [flat(PlatformColor(red: 0.74, green: 0.72, blue: 0.67, alpha: 1), roughness: 0.9)]
        )
        apron.name = "environment.apron"
        apron.position = centre + SIMD3<Float>(0, -0.05, 0)
        container.addChild(apron)

        // A path leading away from the near edge, with low hedging along it.
        let path = ModelEntity(
            mesh: .generateBox(width: 2.6, height: 0.06, depth: 7),
            materials: [flat(PlatformColor(red: 0.83, green: 0.79, blue: 0.71, alpha: 1), roughness: 0.9)]
        )
        path.name = "environment.path"
        path.position = SIMD3<Float>(centre.x, -0.03, Float(maxZ) + 4.6)
        container.addChild(path)

        let hedge = flat(PlatformColor(red: 0.36, green: 0.50, blue: 0.31, alpha: 1), roughness: 0.95)
        for side in [-1.0, 1.0] {
            let run = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.55, 0.55, 6.4), cornerRadius: 0.22),
                materials: [hedge]
            )
            run.name = "environment.hedge"
            run.position = SIMD3<Float>(
                centre.x + Float(side) * 1.9,
                0.24,
                Float(maxZ) + 4.6
            )
            container.addChild(run)
        }

        // Two trees, off to the sides, for something taller than the building to
        // catch the light.
        for side in [-1.0, 1.0] {
            let tree = Entity()
            tree.name = "environment.tree"
            tree.position = SIMD3<Float>(
                Float(side < 0 ? minX - 4.6 : maxX + 4.6),
                0,
                Float(minZ) + Float(maxZ - minZ) * 0.15
            )
            let trunk = ModelEntity(
                mesh: .generateCylinder(height: 2.2, radius: 0.18),
                materials: [flat(PlatformColor(red: 0.48, green: 0.38, blue: 0.28, alpha: 1), roughness: 0.9)]
            )
            trunk.position = SIMD3<Float>(0, 1.1, 0)
            tree.addChild(trunk)
            let crown = ModelEntity(
                mesh: .generateSphere(radius: 1.5),
                materials: [flat(PlatformColor(red: 0.38, green: 0.54, blue: 0.33, alpha: 1), roughness: 0.95)]
            )
            crown.position = SIMD3<Float>(0, 2.9, 0)
            crown.scale = SIMD3<Float>(1, 0.85, 1)
            tree.addChild(crown)
            container.addChild(tree)
        }

        return container
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
