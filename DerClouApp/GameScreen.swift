import SwiftUI
import HeistCore
import HeistKit

/// The whole game screen: the 3D tactical scene edge to edge, plus a debug
/// panel that stays out of the way until asked for.
struct GameScreen: View {
    @State private var session = GameSession()
    @State private var isDebugPanelShown = false
    @State private var isNorthLegCubeShown = false
    @State private var isSouthLegCubeShown = false

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

            Divider().overlay(Color.white.opacity(0.2))
            obstacleTestControls
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: 300, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
    }

    /// Manual triggers for "something suddenly blocks the guard's path,"
    /// so that scenario can be tested on demand from a button instead of by
    /// walking the thief into position by hand and hoping the timing lands.
    ///
    /// The cube toggles exercise the static-obstacle path (a new
    /// `NavigationWorld` revision — the same mechanism a moved prop or a
    /// closed door would trigger). "Ambush with thief" exercises the
    /// separate agent-vs-agent path instead — it is the one actually
    /// reported as still passing through, so this is the button that
    /// matters for that report; the cubes are here because they were asked
    /// for directly, and they double as a live check that obstacle
    /// rerouting still works outside the test suite.
    private var obstacleTestControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Guard obstacle test")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            Button("Ambush with thief") { ambushGuard() }
                .buttonStyle(.bordered)
                .tint(.red)
                .font(.caption2)
                .disabled(guardID == nil || thiefID == nil)

            Toggle("Cube — north leg", isOn: Binding(
                get: { isNorthLegCubeShown },
                set: { setNorthLegCube(shown: $0) }
            ))
            .toggleStyle(.switch)
            .font(.caption2)
            .tint(.orange)

            Toggle("Cube — south leg", isOn: Binding(
                get: { isSouthLegCubeShown },
                set: { setSouthLegCube(shown: $0) }
            ))
            .toggleStyle(.switch)
            .font(.caption2)
            .tint(.orange)
        }
    }

    private var guardID: String? {
        session.level?.actors.first { $0.value.components[GuardComponent.self] != nil }?.key
    }

    private var thiefID: String? {
        session.level?.actors.first { $0.value.components[PlayableActorComponent.self] != nil }?.key
    }

    private func ambushGuard() {
        guard let guardID, let thiefID else { return }
        session.placeBlockerAheadOfAgent(blockerID: thiefID, targetID: guardID, secondsAhead: 1.5)
    }

    // office01's guard walks a rectangle at z=8 and z=9.2 (see Level01.swift);
    // these are the midpoints of its two long legs, clear of doorways.
    private var northLegCubeCenter: WorldPoint? {
        session.level?.blueprint.metrics.worldPoint(CellPoint(12.5, 8))
    }

    private var southLegCubeCenter: WorldPoint? {
        session.level?.blueprint.metrics.worldPoint(CellPoint(12.5, 9.2))
    }

    private func setNorthLegCube(shown: Bool) {
        isNorthLegCubeShown = shown
        guard let center = northLegCubeCenter else { return }
        if shown {
            session.placeDebugCube(id: "debug.cube.north-leg", center: center)
        } else {
            session.removeDynamicObstacle(id: "debug.cube.north-leg")
        }
    }

    private func setSouthLegCube(shown: Bool) {
        isSouthLegCubeShown = shown
        guard let center = southLegCubeCenter else { return }
        if shown {
            session.placeDebugCube(id: "debug.cube.south-leg", center: center)
        } else {
            session.removeDynamicObstacle(id: "debug.cube.south-leg")
        }
    }
}

#Preview {
    GameScreen()
}
