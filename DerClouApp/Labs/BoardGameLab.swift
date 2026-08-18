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
                content.entities.append(LabBoard.dioramaScene())
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

}
