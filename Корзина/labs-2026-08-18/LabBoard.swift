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

    // MARK: - Scene

    /// The diorama, as a scene: plinth, wooden frame, felt board, nodes and
    /// links, low walls, the objective and the pieces.
    ///
    /// Shared, because the whole question is what this looks like under one
    /// camera versus another. Building it twice would compare two dioramas.
    static func dioramaScene() -> Entity {
        let root = Entity()
        let metrics = LabBoard.metrics
        let width = Float(LabBoard.width)
        let depth = Float(LabBoard.depth)
        let height = Float(metrics.wallHeight)
        let thickness = Float(metrics.wallThickness)
        let centre = LabBoard.centre

        let frameWidth: Float = 0.45
        let plinthHeight: Float = 0.5

        // The plinth and its wooden frame: the thing that says "this is an
        // object on a table" rather than "this is a place".
        let wood = matte(UIColor(red: 0.42, green: 0.29, blue: 0.19, alpha: 1), roughness: 0.6)
        root.addChild(block(
            size: SIMD3<Float>(width + frameWidth * 2, plinthHeight, depth + frameWidth * 2),
            at: LabBoard.centre + SIMD3<Float>(0, -plinthHeight / 2 - 0.06, 0),
            material: wood,
            cornerRadius: 0.03
        ))
        for z in [-(depth / 2 + frameWidth / 2), depth / 2 + frameWidth / 2] {
            root.addChild(block(
                size: SIMD3<Float>(width + frameWidth * 2, 0.16, frameWidth),
                at: LabBoard.centre + SIMD3<Float>(0, 0.02, z),
                material: wood, cornerRadius: 0.02
            ))
        }
        for x in [-(width / 2 + frameWidth / 2), width / 2 + frameWidth / 2] {
            root.addChild(block(
                size: SIMD3<Float>(frameWidth, 0.16, depth + frameWidth * 2),
                at: LabBoard.centre + SIMD3<Float>(x, 0.02, 0),
                material: wood, cornerRadius: 0.02
            ))
        }
        // Name plate on the near edge.
        root.addChild(block(
            size: SIMD3<Float>(1.6, 0.03, 0.34),
            at: LabBoard.centre + SIMD3<Float>(0, 0.11, depth / 2 + frameWidth / 2),
            material: matte(UIColor(red: 0.78, green: 0.72, blue: 0.55, alpha: 1), roughness: 0.35)
        ))

        // The board itself: felt, with nodes and the lines between them.
        root.addChild(block(
            size: SIMD3<Float>(width, 0.12, depth),
            at: LabBoard.centre + SIMD3<Float>(0, -0.06, 0),
            material: matte(UIColor(red: 0.20, green: 0.28, blue: 0.26, alpha: 1), roughness: 0.95)
        ))

        let nodeMaterial = matte(UIColor(red: 0.80, green: 0.78, blue: 0.70, alpha: 1), roughness: 0.5)
        let linkMaterial = matte(UIColor(red: 0.55, green: 0.55, blue: 0.50, alpha: 1), roughness: 0.8)

        // A node in the middle of every cell, and a link to the neighbour to the
        // right and below it. Blocked by a wall? Then no link — the board states
        // the rules the way a board game does.
        for column in 0..<Int(LabBoard.bounds.size.width) {
            for row in 0..<Int(LabBoard.bounds.size.depth) {
                let cell = CellPoint(Double(column) + 0.5, Double(row) + 0.5)
                let point = metrics.worldPoint(cell)
                let node = ModelEntity(
                    mesh: .generateCylinder(height: 0.02, radius: 0.14),
                    materials: [nodeMaterial]
                )
                node.position = SIMD3<Float>(Float(point.x), 0.015, Float(point.z))
                root.addChild(node)

                for step in [CellPoint(1, 0), CellPoint(0, 1)] {
                    let other = CellPoint(cell.x + step.x, cell.y + step.y)
                    guard other.x < LabBoard.bounds.size.width, other.y < LabBoard.bounds.size.depth else { continue }
                    guard !isBlocked(between: cell, and: other) else { continue }

                    let middle = metrics.worldPoint(CellPoint((cell.x + other.x) / 2, (cell.y + other.y) / 2))
                    let alongZ = step.y > 0
                    root.addChild(block(
                        size: alongZ
                            ? SIMD3<Float>(0.05, 0.012, 0.72)
                            : SIMD3<Float>(0.72, 0.012, 0.05),
                        at: SIMD3<Float>(Float(middle.x), 0.012, Float(middle.z)),
                        material: linkMaterial
                    ))
                }
            }
        }

        // Low walls, as raised edges of the board rather than as architecture.
        let wall = matte(UIColor(red: 0.52, green: 0.54, blue: 0.56, alpha: 1), roughness: 0.7)
        for run in LabBoard.interior {
            let from = metrics.worldPoint(run.from)
            let to = metrics.worldPoint(run.to)
            let length = Float(max(abs(to.x - from.x), abs(to.z - from.z)))
            let alongZ = abs(to.z - from.z) > abs(to.x - from.x)
            root.addChild(block(
                size: alongZ
                    ? SIMD3<Float>(thickness, height, length)
                    : SIMD3<Float>(length, height, thickness),
                at: SIMD3<Float>(Float((from.x + to.x) / 2), height / 2, Float((from.z + to.z) / 2)),
                material: wall, cornerRadius: 0.02
            ))
        }

        root.addChild(block(
            size: SIMD3<Float>(0.5, 0.5, 0.5),
            at: SIMD3<Float>(
                Float(metrics.worldPoint(LabBoard.objective).x),
                0.25,
                Float(metrics.worldPoint(LabBoard.objective).z)
            ),
            material: matte(UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1), roughness: 0.35),
            cornerRadius: 0.03
        ))

        root.addChild(piece(
            colour: UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1),
            at: LabBoard.thief
        ))
        for cell in LabBoard.guards {
            root.addChild(piece(
                colour: UIColor(red: 0.62, green: 0.16, blue: 0.16, alpha: 1),
                at: cell
            ))
        }

        addDioramaLighting(to: root)
        return root
    }

    /// Whether an interior wall runs along the line between two neighbouring
    /// cells.
    static func isBlocked(between cell: CellPoint, and other: CellPoint) -> Bool {
        let line = CellPoint((cell.x + other.x) / 2, (cell.y + other.y) / 2)
        for run in LabBoard.interior {
            let alongZ = abs(run.to.y - run.from.y) > abs(run.to.x - run.from.x)
            if alongZ {
                guard abs(line.x - run.from.x) < 0.01 else { continue }
                if line.y > min(run.from.y, run.to.y) && line.y < max(run.from.y, run.to.y) { return true }
            } else {
                guard abs(line.y - run.from.y) < 0.01 else { continue }
                if line.x > min(run.from.x, run.to.x) && line.x < max(run.from.x, run.to.x) { return true }
            }
        }
        return false
    }

    static func addDioramaLighting(to root: Entity) {
        // One warm key from above and to the side, the way a lamp lights a table,
        // plus a cool fill so the shadowed sides do not go black.
        let key = Entity()
        key.components.set(DirectionalLightComponent(
            color: UIColor(red: 1, green: 0.94, blue: 0.84, alpha: 1),
            intensity: 4200
        ))
        key.components.set(DirectionalLightComponent.Shadow())
        key.look(
            at: LabBoard.centre,
            from: LabBoard.centre + SIMD3<Float>(-4, 8, -3),
            relativeTo: nil
        )
        root.addChild(key)

        let fill = Entity()
        fill.components.set(DirectionalLightComponent(
            color: UIColor(red: 0.58, green: 0.68, blue: 0.92, alpha: 1),
            intensity: 700
        ))
        fill.look(
            at: LabBoard.centre,
            from: LabBoard.centre + SIMD3<Float>(6, 5, 6),
            relativeTo: nil
        )
        root.addChild(fill)
    }
}
