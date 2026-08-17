import SwiftUI
import HeistCore
import HeistKit

/// The whole game screen: the 3D tactical scene edge to edge, plus a debug
/// panel that stays out of the way until asked for.
struct GameScreen: View {
    @State private var session = GameSession()
    @State private var isDebugPanelShown = false

    var body: some View {
        ZStack {
            Color.black

            HeistSceneView(session: session)
        }
        // An overlay sized to its own content, not a full-screen layer: anything
        // stretched edge to edge here would sit between the player and the scene.
        .overlay(alignment: .topTrailing) {
            debugControls
        }
        // The scene owns the whole display, including under the notch and the
        // home indicator. Only the HUD respects the safe area.
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            session.load(.office01)
        }
    }

    private var debugControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            toggleButton
            if isDebugPanelShown {
                debugPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isDebugPanelShown.toggle()
            }
        } label: {
            Image(systemName: isDebugPanelShown ? "xmark" : "ladybug")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.level?.blueprint.title ?? "Loading")
                .font(.subheadline.weight(.semibold))

            Text(session.status)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.white.opacity(0.85))

            if let selected = session.selectedActorID {
                Text(selected)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let issues = session.level?.issues, issues.hasErrors {
                Label("\(issues.errors.count) blueprint errors", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: 260, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
    }
}

#Preview {
    GameScreen()
}
