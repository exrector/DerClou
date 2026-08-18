import SwiftUI
import RealityKit
import HeistCore
import HeistKit

/// A debug scene for the tactical camera: one room, four cubes, no gameplay.
///
/// Kept deliberately. The camera is a fixed top-plane anchored off-axis
/// perspective camera — unusual enough, and fundamental enough to the game, to
/// deserve somewhere it can be checked by eye in isolation. `CameraProjectionTests`
/// owns the maths; this owns the question "does the renderer agree".
///
/// It drives the real `TacticalCamera`, not a copy of it. A second
/// implementation here would be a second thing to keep in step, and the whole
/// point of the camera's design is that there is only one.
///
/// Launch with `CAMLAB=1`. Drag to peek, double tap to reset.
struct CameraLab: View {
    /// The room, expressed the way a level is: cells, and one metrics.
    private let bounds = CellRect(x: 0, y: 0, width: 10, depth: 6)
    private let metrics = LevelMetrics.standard

    @State private var camera = TacticalCamera(restingLean: .flat)
    @State private var lean = (across: 0.0, up: 0.0)
    @State private var leanAtDragStart: (across: Double, up: Double)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                RealityView { content in
                    content.camera = .virtual
                    content.entities.append(room())
                    content.entities.append(camera.entity)
                    frame(proxy.size)
                } update: { _ in
                    frame(proxy.size)
                }

                Text(String(format: "peek  %.0f°  %.0f°", lean.across, lean.up))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if leanAtDragStart == nil { leanAtDragStart = lean }
                        guard let start = leanAtDragStart else { return }
                        let perPoint = 0.09
                        lean = (
                            across: start.across + Double(value.translation.width) * perPoint,
                            up: start.up + Double(value.translation.height) * perPoint
                        )
                        camera.control = camera.control.leaned(vertical: lean.up, horizontal: lean.across)
                        lean = (camera.control.leanHorizontal, camera.control.leanVertical)
                        frame(proxy.size)
                    }
                    .onEnded { _ in leanAtDragStart = nil }
            )
            .onTapGesture(count: 2) {
                lean = (0, 0)
                camera.control = .neutral
                frame(proxy.size)
            }
        }
        .ignoresSafeArea()
        .background(.black)
    }

    private func frame(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        camera.frame(
            bounds: bounds,
            metrics: metrics,
            aspectRatio: Double(size.width / size.height)
        )
    }

    // MARK: - The room

    private func room() -> Entity {
        let root = Entity()
        let width = metrics.meters(fromCells: bounds.size.width)
        let depth = metrics.meters(fromCells: bounds.size.depth)
        let height = metrics.wallHeight
        let thickness = metrics.wallThickness
        let centre = SIMD3<Float>(Float(width / 2), 0, Float(depth / 2))

        root.addChild(box(
            size: SIMD3<Float>(Float(width), 0.1, Float(depth)),
            at: centre + SIMD3<Float>(0, -0.05, 0),
            colour: UIColor(red: 0.35, green: 0.37, blue: 0.42, alpha: 1)
        ))

        let wall = UIColor(red: 0.62, green: 0.64, blue: 0.68, alpha: 1)
        let half = SIMD3<Float>(Float(width / 2), Float(height / 2), Float(depth / 2))
        for offset in [SIMD3<Float>(0, half.y, -half.z), SIMD3<Float>(0, half.y, half.z)] {
            root.addChild(box(
                size: SIMD3<Float>(Float(width), Float(height), Float(thickness)),
                at: centre + offset, colour: wall
            ))
        }
        for offset in [SIMD3<Float>(-half.x, half.y, 0), SIMD3<Float>(half.x, half.y, 0)] {
            root.addChild(box(
                size: SIMD3<Float>(Float(thickness), Float(height), Float(depth)),
                at: centre + offset, colour: wall
            ))
        }

        // Cubes, so the parallax is readable, and off centre so they cannot all
        // move the same way by accident.
        let cubes: [(SIMD3<Float>, UIColor)] = [
            (SIMD3<Float>(-3, 0.5, -1.5), UIColor(red: 0.85, green: 0.45, blue: 0.25, alpha: 1)),
            (SIMD3<Float>(3, 0.5, -1.5), UIColor(red: 0.30, green: 0.60, blue: 0.50, alpha: 1)),
            (SIMD3<Float>(-3, 0.5, 1.5), UIColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 1)),
            (SIMD3<Float>(3, 0.5, 1.5), UIColor(red: 0.80, green: 0.75, blue: 0.35, alpha: 1))
        ]
        for (offset, colour) in cubes {
            root.addChild(box(size: SIMD3<Float>(repeating: 1), at: centre + offset, colour: colour))
        }

        // Markers on the corners of the anchor plane. If the camera is doing its
        // job these four do not move on screen, at any peek. That is the whole
        // contract, made visible.
        for x in [-half.x, half.x] {
            for z in [-half.z, half.z] {
                root.addChild(box(
                    size: SIMD3<Float>(repeating: 0.35),
                    at: centre + SIMD3<Float>(x, Float(height), z),
                    colour: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 1)
                ))
            }
        }

        return root
    }

    /// Unlit on purpose: lighting is not part of the question, and a light that
    /// failed to reach the scene would look exactly like a camera that failed to
    /// render it.
    private func box(size: SIMD3<Float>, at position: SIMD3<Float>, colour: UIColor) -> Entity {
        let entity = ModelEntity(
            mesh: .generateBox(width: size.x, height: size.y, depth: size.z),
            materials: [UnlitMaterial(color: colour)]
        )
        entity.position = position
        return entity
    }
}
