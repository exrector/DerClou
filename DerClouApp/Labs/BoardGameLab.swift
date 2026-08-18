import SwiftUI
import RealityKit
import HeistCore

/// Variant C: the same layout as a tabletop diorama, in the manner of Hitman GO.
///
/// Deliberately the conventional approach, because that is what makes it a fair
/// comparison. There is no custom projection here at all: an ordinary symmetric
/// perspective camera sits at a fixed presentation angle and looks at a board on
/// a plinth. Dragging tips the view a little and it springs back — the camera
/// treats the player as someone sitting at a table, not as someone inside the
/// building.
///
/// What that buys: the pieces read as objects, the board reads as a physical
/// thing, and depth is free because the angle gives it. What it costs: the board
/// keystones, so its outline is a trapezium rather than a rectangle, it cannot
/// fill a phone screen without waste at the corners, and the far row is smaller
/// than the near one, so equal distances do not look equal.
///
/// References for the look: nodes and lines on a square grid, pawn-like plastic
/// figurines, a wooden frame with a name plate, matte materials, one warm key
/// light and a dark table around it.
struct BoardGameLab: View {
    /// Degrees above the horizon. Around here the board reads as a board rather
    /// than as a map or as a room.
    private let restingElevation = 54.0
    private let restingYaw = 0.0

    @State private var elevation = 54.0
    @State private var yaw = 0.0
    @State private var startOfDrag: (elevation: Double, yaw: Double)?

    @State private var camera = PerspectiveCamera()

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.entities.append(diorama())
                content.entities.append(camera)
                place()
            } update: { _ in
                place()
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if startOfDrag == nil { startOfDrag = (elevation, yaw) }
                        guard let start = startOfDrag else { return }
                        // A look around, not a free camera: a narrow range, and
                        // it does not stay where it is left.
                        elevation = min(max(start.elevation - Double(value.translation.height) * 0.06, 34), 78)
                        yaw = min(max(start.yaw + Double(value.translation.width) * 0.06, -22), 22)
                    }
                    .onEnded { _ in
                        startOfDrag = nil
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            elevation = restingElevation
                            yaw = restingYaw
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .background(.black)
        .overlay(alignment: .top) {
            Text(String(format: "диорама   %.0f°  %.0f°", yaw, elevation))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 6)
                .allowsHitTesting(false)
        }
    }

    /// Fixed presentation angle, orbiting the middle of the board.
    private func place() {
        let centre = LabBoard.centre + SIMD3<Float>(0, 0.35, 0)
        // Far enough back that the board fits the frame with a little table
        // showing around it, which is part of the look.
        let distance = Float(max(LabBoard.width, LabBoard.depth)) * 1.35

        let elevationRadians = Float(elevation * .pi / 180)
        let yawRadians = Float(yaw * .pi / 180)
        let horizontal = distance * cos(elevationRadians)

        camera.look(
            at: centre,
            from: centre + SIMD3<Float>(
                horizontal * sin(yawRadians),
                distance * sin(elevationRadians),
                horizontal * cos(yawRadians)
            ),
            relativeTo: nil
        )
        camera.camera.fieldOfViewInDegrees = 32
    }

    // MARK: - Scene

    private func diorama() -> Entity {
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
        let wood = LabBoard.matte(UIColor(red: 0.42, green: 0.29, blue: 0.19, alpha: 1), roughness: 0.6)
        root.addChild(LabBoard.block(
            size: SIMD3<Float>(width + frameWidth * 2, plinthHeight, depth + frameWidth * 2),
            at: centre + SIMD3<Float>(0, -plinthHeight / 2 - 0.06, 0),
            material: wood,
            cornerRadius: 0.03
        ))
        for z in [-(depth / 2 + frameWidth / 2), depth / 2 + frameWidth / 2] {
            root.addChild(LabBoard.block(
                size: SIMD3<Float>(width + frameWidth * 2, 0.16, frameWidth),
                at: centre + SIMD3<Float>(0, 0.02, z),
                material: wood, cornerRadius: 0.02
            ))
        }
        for x in [-(width / 2 + frameWidth / 2), width / 2 + frameWidth / 2] {
            root.addChild(LabBoard.block(
                size: SIMD3<Float>(frameWidth, 0.16, depth + frameWidth * 2),
                at: centre + SIMD3<Float>(x, 0.02, 0),
                material: wood, cornerRadius: 0.02
            ))
        }
        // Name plate on the near edge.
        root.addChild(LabBoard.block(
            size: SIMD3<Float>(1.6, 0.03, 0.34),
            at: centre + SIMD3<Float>(0, 0.11, depth / 2 + frameWidth / 2),
            material: LabBoard.matte(UIColor(red: 0.78, green: 0.72, blue: 0.55, alpha: 1), roughness: 0.35)
        ))

        // The board itself: felt, with nodes and the lines between them.
        root.addChild(LabBoard.block(
            size: SIMD3<Float>(width, 0.12, depth),
            at: centre + SIMD3<Float>(0, -0.06, 0),
            material: LabBoard.matte(UIColor(red: 0.20, green: 0.28, blue: 0.26, alpha: 1), roughness: 0.95)
        ))

        let nodeMaterial = LabBoard.matte(UIColor(red: 0.80, green: 0.78, blue: 0.70, alpha: 1), roughness: 0.5)
        let linkMaterial = LabBoard.matte(UIColor(red: 0.55, green: 0.55, blue: 0.50, alpha: 1), roughness: 0.8)

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
                    root.addChild(LabBoard.block(
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
        let wall = LabBoard.matte(UIColor(red: 0.52, green: 0.54, blue: 0.56, alpha: 1), roughness: 0.7)
        for run in LabBoard.interior {
            let from = metrics.worldPoint(run.from)
            let to = metrics.worldPoint(run.to)
            let length = Float(max(abs(to.x - from.x), abs(to.z - from.z)))
            let alongZ = abs(to.z - from.z) > abs(to.x - from.x)
            root.addChild(LabBoard.block(
                size: alongZ
                    ? SIMD3<Float>(thickness, height, length)
                    : SIMD3<Float>(length, height, thickness),
                at: SIMD3<Float>(Float((from.x + to.x) / 2), height / 2, Float((from.z + to.z) / 2)),
                material: wall, cornerRadius: 0.02
            ))
        }

        root.addChild(LabBoard.block(
            size: SIMD3<Float>(0.5, 0.5, 0.5),
            at: SIMD3<Float>(
                Float(metrics.worldPoint(LabBoard.objective).x),
                0.25,
                Float(metrics.worldPoint(LabBoard.objective).z)
            ),
            material: LabBoard.matte(UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1), roughness: 0.35),
            cornerRadius: 0.03
        ))

        root.addChild(LabBoard.piece(
            colour: UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1),
            at: LabBoard.thief
        ))
        for cell in LabBoard.guards {
            root.addChild(LabBoard.piece(
                colour: UIColor(red: 0.62, green: 0.16, blue: 0.16, alpha: 1),
                at: cell
            ))
        }

        addLighting(to: root)
        return root
    }

    /// Whether an interior wall runs along the line between two neighbouring
    /// cells.
    private func isBlocked(between cell: CellPoint, and other: CellPoint) -> Bool {
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

    private func addLighting(to root: Entity) {
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
