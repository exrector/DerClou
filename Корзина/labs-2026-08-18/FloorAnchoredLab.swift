import SwiftUI
import RealityKit
import HeistCore
import HeistKit

/// Variant B: the same camera, anchored to the floor instead of the wall tops.
///
/// Everything about the projection is unchanged — straight down, no rotation,
/// off-axis shift cancelling the camera's slide. Only the plane it cancels at
/// moves, from the tops of the walls down to the floor.
///
/// That inverts what holds still. The gameplay plane becomes the fixed thing:
/// the floor, the grid, the squares people stand on and the routes between them
/// never move by a pixel, and what leans instead is everything standing on the
/// floor — walls, furniture, pieces. It reads as a board held still while the
/// player moves their head, where variant A reads as looking down into a box.
///
/// Which is better is the question the labs exist to answer.
struct FloorAnchoredLab: View {
    // Fit rather than fill: the labs exist to be compared, and a comparison
    // wants the whole board in shot. The game itself fills the screen.
    @State private var camera = TacticalCamera(margin: 0.7, mode: .fit, anchorHeight: 0, restingLean: .flat)
    @State private var peek = (across: 0.0, up: 0.0)
    @State private var peekAtDragStart: (across: Double, up: Double)?

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.entities.append(board())
                content.entities.append(camera.entity)
                frame(proxy.size)
            } update: { _ in
                frame(proxy.size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if peekAtDragStart == nil { peekAtDragStart = peek }
                        guard let start = peekAtDragStart else { return }
                        camera.control = camera.control.leaned(
                            vertical: start.up + Double(value.translation.height) * 0.09,
                            horizontal: start.across + Double(value.translation.width) * 0.09
                        )
                        peek = (camera.control.leanHorizontal, camera.control.leanVertical)
                        frame(proxy.size)
                    }
                    .onEnded { _ in peekAtDragStart = nil }
            )
            .onTapGesture(count: 2) {
                peek = (0, 0)
                camera.control = .neutral
                frame(proxy.size)
            }
        }
        .ignoresSafeArea()
        .background(.black)
        .overlay(alignment: .top) {
            Text(String(format: "пол закреплён   %.0f°  %.0f°", peek.across, peek.up))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 6)
                .allowsHitTesting(false)
        }
    }

    private func frame(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        camera.frame(
            bounds: LabBoard.bounds,
            metrics: LabBoard.metrics,
            aspectRatio: Double(size.width / size.height)
        )
    }

    // MARK: - Scene

    private func board() -> Entity {
        let root = Entity()
        let metrics = LabBoard.metrics
        let width = Float(LabBoard.width)
        let depth = Float(LabBoard.depth)
        let height = Float(metrics.wallHeight)
        let thickness = Float(metrics.wallThickness)
        let centre = LabBoard.centre

        // Floor. This is the plane that will not move.
        root.addChild(LabBoard.block(
            size: SIMD3<Float>(width, 0.12, depth),
            at: centre + SIMD3<Float>(0, -0.06, 0),
            material: LabBoard.matte(UIColor(red: 0.33, green: 0.35, blue: 0.40, alpha: 1))
        ))

        // A grid scored into the floor, so it is obvious when the gameplay plane
        // holds still and when it does not.
        let line = LabBoard.matte(UIColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1))
        for x in stride(from: 1.0, to: LabBoard.width, by: 1.0) {
            root.addChild(LabBoard.block(
                size: SIMD3<Float>(0.02, 0.01, depth),
                at: SIMD3<Float>(Float(x), 0.005, centre.z),
                material: line
            ))
        }
        for z in stride(from: 1.0, to: LabBoard.depth, by: 1.0) {
            root.addChild(LabBoard.block(
                size: SIMD3<Float>(width, 0.01, 0.02),
                at: SIMD3<Float>(centre.x, 0.005, Float(z)),
                material: line
            ))
        }

        // Exterior walls, low.
        let wall = LabBoard.matte(UIColor(red: 0.60, green: 0.62, blue: 0.66, alpha: 1))
        for z in [Float(0), depth] {
            root.addChild(LabBoard.block(
                size: SIMD3<Float>(width, height, thickness),
                at: SIMD3<Float>(centre.x, height / 2, z),
                material: wall
            ))
        }
        for x in [Float(0), width] {
            root.addChild(LabBoard.block(
                size: SIMD3<Float>(thickness, height, depth),
                at: SIMD3<Float>(x, height / 2, centre.z),
                material: wall
            ))
        }

        // Interior walls and their doorways.
        for run in LabBoard.interior {
            let from = metrics.worldPoint(run.from)
            let to = metrics.worldPoint(run.to)
            let length = Float(max(abs(to.x - from.x), abs(to.z - from.z)))
            let isAlongZ = abs(to.z - from.z) > abs(to.x - from.x)
            root.addChild(LabBoard.block(
                size: isAlongZ
                    ? SIMD3<Float>(thickness, height, length)
                    : SIMD3<Float>(length, height, thickness),
                at: SIMD3<Float>(
                    Float((from.x + to.x) / 2),
                    height / 2,
                    Float((from.z + to.z) / 2)
                ),
                material: wall
            ))
        }

        // The objective, and the pieces.
        root.addChild(LabBoard.block(
            size: SIMD3<Float>(0.5, 0.5, 0.5),
            at: SIMD3<Float>(
                Float(metrics.worldPoint(LabBoard.objective).x),
                0.25,
                Float(metrics.worldPoint(LabBoard.objective).z)
            ),
            material: LabBoard.matte(UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1), roughness: 0.4)
        ))

        root.addChild(LabBoard.piece(
            colour: UIColor(red: 0.22, green: 0.40, blue: 0.66, alpha: 1),
            at: LabBoard.thief
        ))
        for cell in LabBoard.guards {
            root.addChild(LabBoard.piece(
                colour: UIColor(red: 0.70, green: 0.26, blue: 0.24, alpha: 1),
                at: cell
            ))
        }

        addLighting(to: root)
        return root
    }

    private func addLighting(to root: Entity) {
        let key = Entity()
        key.components.set(DirectionalLightComponent(
            color: UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1),
            intensity: 3200
        ))
        key.components.set(DirectionalLightComponent.Shadow())
        key.look(
            at: LabBoard.centre,
            from: LabBoard.centre + SIMD3<Float>(-5, 9, -6),
            relativeTo: nil
        )
        root.addChild(key)

        let fill = Entity()
        fill.components.set(DirectionalLightComponent(
            color: UIColor(red: 0.65, green: 0.74, blue: 0.95, alpha: 1),
            intensity: 900
        ))
        fill.look(
            at: LabBoard.centre,
            from: LabBoard.centre + SIMD3<Float>(6, 7, 5),
            relativeTo: nil
        )
        root.addChild(fill)
    }
}
