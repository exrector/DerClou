import SwiftUI
import RealityKit
import HeistCore

/// One small test board, built two ways.
///
/// The point of the labs is to compare *how the same layout reads* under two
/// different ways of looking at it, so the layout has to be the same in both:
/// same size, same rooms, same doorways, same pieces in the same squares. Only
/// the presentation differs.
enum LabBoard {
    /// Nine by six cells of one meter. Small enough to read at a glance, big
    /// enough to have an inside and an outside.
    static let bounds = CellRect(x: 0, y: 0, width: 9, depth: 6)

    /// Low walls on purpose. The game's own walls stand 2.6 m, which reads as a
    /// building seen from above; at 1.1 m the same plan reads as a board with
    /// raised edges. Both variants use this so the comparison is about the
    /// viewpoint and not about the height of the walls.
    static let metrics = LevelMetrics(cellSize: 1, wallHeight: 1.1, wallThickness: 0.2)

    static var width: Double { metrics.meters(fromCells: bounds.size.width) }
    static var depth: Double { metrics.meters(fromCells: bounds.size.depth) }
    static var centre: SIMD3<Float> { SIMD3<Float>(Float(width / 2), 0, Float(depth / 2)) }

    /// Where the pieces stand, in cells.
    static let thief = CellPoint(1.5, 4.5)
    static let guards = [CellPoint(6.5, 1.5), CellPoint(3.5, 4.5)]
    /// The one thing worth reaching, in the far room.
    static let objective = CellPoint(7.5, 4.5)

    /// Interior walls, as (from, to) in cells along the grid lines, with the gap
    /// that makes them a doorway rather than a partition.
    /// A cross wall with a gap, and a short spur: enough to have rooms, corners
    /// to hide behind and one sight line worth blocking.
    static let interior: [(from: CellPoint, to: CellPoint)] = [
        (CellPoint(3, 0), CellPoint(3, 2.2)),
        (CellPoint(3, 3.8), CellPoint(3, 6)),
        (CellPoint(6, 2.5), CellPoint(6, 6))
    ]

    // MARK: - Materials

    static func matte(_ colour: UIColor, roughness: Float = 0.85) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: colour)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    static func block(
        size: SIMD3<Float>,
        at position: SIMD3<Float>,
        material: PhysicallyBasedMaterial,
        cornerRadius: Float = 0
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [material]
        )
        entity.position = position
        return entity
    }

    /// A pawn: a base, a body and a head. Deliberately the same shape in both
    /// labs, so the eye compares the view and not the figure.
    static func piece(colour: UIColor, at cell: CellPoint, height: Float = 0.62) -> Entity {
        let container = Entity()
        let point = metrics.worldPoint(cell)
        container.position = SIMD3<Float>(Float(point.x), 0, Float(point.z))

        let material = matte(colour, roughness: 0.55)
        let radius: Float = 0.17

        let base = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: radius * 1.35),
            materials: [material]
        )
        base.position = SIMD3<Float>(0, 0.025, 0)
        container.addChild(base)

        let body = ModelEntity(
            mesh: .generateCone(height: height * 0.72, radius: radius),
            materials: [material]
        )
        body.position = SIMD3<Float>(0, 0.05 + height * 0.36, 0)
        container.addChild(body)

        let head = ModelEntity(
            mesh: .generateSphere(radius: radius * 0.62),
            materials: [material]
        )
        head.position = SIMD3<Float>(0, 0.05 + height * 0.72 + radius * 0.5, 0)
        container.addChild(head)

        return container
    }
}
