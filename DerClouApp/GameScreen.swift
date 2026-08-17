import SwiftUI
import HeistCore
import HeistKit

/// The whole game screen: 3D tactical scene plus a minimal debug overlay.
///
/// The production HUD comes later. What matters now is that the scene fills the
/// screen and that the overlay reports what navigation actually did.
struct GameScreen: View {
    @State private var session = GameSession()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            HeistSceneView(session: session)

            debugOverlay
                .padding(.horizontal, 20)
                .padding(.top, 12)
                // The HUD is read-only. Without this it swallows taps meant for
                // the scene underneath it.
                .allowsHitTesting(false)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            session.load(.office01)
        }
    }

    private var debugOverlay: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.level?.blueprint.title ?? "Loading")
                    .font(.headline)
                Text(session.status)
                    .font(.caption)
                    .monospaced()
                if let selected = session.selectedActorID {
                    Text("selected: \(selected)")
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 0)

            if let issues = session.level?.issues, issues.hasErrors {
                Label("\(issues.errors.count) blueprint errors", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .padding(10)
                    .background(.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    GameScreen()
}
