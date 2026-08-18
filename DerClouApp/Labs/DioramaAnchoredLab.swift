import SwiftUI
import RealityKit
import HeistCore
import HeistKit

/// Variant D: the diorama's look under the game's camera.
///
/// The proposition being tested is that the two halves of "Hitman GO" separate
/// cleanly. Its *art* — felt, wood, a plinth, nodes and links, plastic pawns,
/// one warm lamp — is a look, and looks are portable. Its *camera* is a tilted
/// presentation angle, which costs this game more than it gives: a trapezium
/// instead of a rectangle, unequal distances at unequal depths, occlusion by
/// anything tall, and wasted corners on a phone.
///
/// So: the same diorama, seen through the anchored off-axis camera, with two
/// dials the comparison actually turns on.
///
/// **Resting peek.** The peek is one number, and nothing says it has to rest at
/// zero. Held at 12–15° the scene reads obliquely — every piece shows a side,
/// every wall shows a face, depth is legible — while the board stays an exact
/// rectangle filling the screen. That is a board game photographed with a shift
/// lens rather than one photographed from a chair.
///
/// **Anchor plane.** Pin the board itself, and the play surface is the thing
/// that never moves. Pin the frame's rim, and the object's outline is. They feel
/// different enough that it is worth a switch rather than an argument.
struct DioramaAnchoredLab: View {
    /// Top of the wooden frame, in meters. The other plane worth pinning.
    private let frameTop = 0.1

    @State private var restingPeek = 14.0
    @State private var restingPeekAcross = 9.0
    @State private var anchorToFrame = false

    @State private var camera = TacticalCamera(margin: 0.55, mode: .fit, anchorHeight: 0)
    @State private var peek = (across: 0.0, up: 0.0)
    @State private var peekAtDragStart: (across: Double, up: Double)?

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.entities.append(LabBoard.dioramaScene())
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
                        peek = (
                            across: start.across + Double(value.translation.width) * 0.09,
                            up: start.up + Double(value.translation.height) * 0.09
                        )
                        frame(proxy.size)
                    }
                    .onEnded { _ in peekAtDragStart = nil }
            )
            .onTapGesture(count: 2) {
                peek = (0, 0)
                frame(proxy.size)
            }
        }
        .ignoresSafeArea()
        .background(.black)
        .overlay(alignment: .top) { readout }
        .overlay(alignment: .bottom) { dials }
    }

    private var readout: some View {
        Text(String(
            format: "%@   покой %.0f°/%.0f°   палец %.0f°/%.0f°",
            anchorToFrame ? "рама" : "доска",
            restingPeekAcross, restingPeek,
            peek.across, peek.up
        ))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.65))
        .padding(.top, 6)
        .allowsHitTesting(false)
    }

    private var dials: some View {
        HStack(spacing: 14) {
            dial("вниз", value: $restingPeek)
            dial("вбок", value: $restingPeekAcross, range: -20...20)
            Toggle("рама", isOn: $anchorToFrame)
                .toggleStyle(.button)
                .font(.caption2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 52)
    }

    private func dial(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...20
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Slider(value: value, in: range)
                .frame(width: 130)
        }
    }

    private func frame(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        camera.anchorHeight = anchorToFrame ? frameTop : 0
        // The resting peek is simply where the peek starts from. It tips the
        // scene up the screen, which is the direction that shows the far side of
        // a room, and the finger works from there.
        camera.control = camera.control.leaned(
            vertical: restingPeek + peek.up,
            horizontal: restingPeekAcross + peek.across
        )
        camera.frame(
            bounds: LabBoard.bounds,
            metrics: LabBoard.metrics,
            aspectRatio: Double(size.width / size.height)
        )
    }
}
