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

/// Procedural stand-in geometry and materials for the environment kit.
///
/// This is the *engineering* look, not the art direction: real dimensions, real
/// PBR response, real shadows, but primitive shapes. Because every prototype
/// already carries its final footprint, replacing a greybox with an authored
/// USDZ is a one-line change in `PropCatalog` and touches no level data.
public enum GreyboxKit {
    /// Colour and PBR response per surface family.
    public static func material(for surface: SurfaceKey) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()

        let (color, roughness, metallic): (PlatformColor, Float, Float) = switch surface {
        case .concrete:
            (PlatformColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1), 0.85, 0.0)
        case .plaster:
            (PlatformColor(red: 0.30, green: 0.31, blue: 0.34, alpha: 1), 0.90, 0.0)
        case .wood:
            (PlatformColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1), 0.55, 0.0)
        case .metal:
            (PlatformColor(red: 0.55, green: 0.57, blue: 0.60, alpha: 1), 0.35, 1.0)
        case .darkMetal:
            (PlatformColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1), 0.30, 1.0)
        case .glass:
            (PlatformColor(red: 0.60, green: 0.70, blue: 0.78, alpha: 1), 0.05, 0.0)
        case .fabric:
            (PlatformColor(red: 0.24, green: 0.36, blue: 0.34, alpha: 1), 0.95, 0.0)
        case .emissive:
            (PlatformColor(red: 0.20, green: 0.85, blue: 0.55, alpha: 1), 0.60, 0.0)
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
