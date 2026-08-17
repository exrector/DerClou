import SwiftUI
import HeistCore
import HeistKit

/// The whole game screen: the 3D tactical scene edge to edge, plus a debug
/// panel that stays out of the way until asked for.
struct GameScreen: View {
    @State private var session = GameSession()
    @State private var isDebugPanelShown = false

    var body: some View {
        // The insets have to be read *outside* `ignoresSafeArea`, or they are
        // already consumed by the time the scene view sees them.
        GeometryReader { proxy in
            content(safeAreaInsets: proxy.safeAreaInsets)
        }
    }

    private func content(safeAreaInsets: EdgeInsets) -> some View {
        ZStack {
            Color.black

            HeistSceneView(session: session, safeAreaInsets: safeAreaInsets)
        }
        // The scene owns the whole display, including under the notch and the
        // home indicator...
        .ignoresSafeArea()
        // ...but the HUD sits inside the safe area, which is why this overlay is
        // attached after `ignoresSafeArea` rather than before it. Sized to its
        // own content, so it never covers the scene.
        .overlay(alignment: .topTrailing) {
            debugControls
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            session.load(.office01)
            // Guards start walking immediately for now; once planning exists,
            // the clock only runs while a plan is being executed.
            session.startClock()
        }
    }

    private var debugControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            focusButton
            toggleButton
            if isDebugPanelShown {
                debugPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
    }

    /// Returns the camera to framing the whole level.
    private var focusButton: some View {
        Button {
            session.requestCameraReset()
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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

            Text(session.clock.formatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

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

            if !session.placementIssues.isEmpty {
                Label("\(session.placementIssues.count) outside safe area", systemImage: "rectangle.dashed")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Toggle("Safe area", isOn: Binding(
                get: { session.isSafeBoundsShown },
                set: { session.setSafeBoundsVisible($0) }
            ))
            .toggleStyle(.switch)
            .font(.caption2)
            .tint(.orange)
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
