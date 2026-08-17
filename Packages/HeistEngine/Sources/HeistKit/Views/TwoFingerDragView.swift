#if canImport(UIKit)
import SwiftUI
import UIKit

/// Reports two-finger vertical drags, which SwiftUI's `DragGesture` cannot
/// distinguish from one-finger drags.
///
/// Used for the peek gesture: one finger pans the map, two fingers tilt it.
struct TwoFingerDragView: UIViewRepresentable {
    /// Called with the vertical translation in points and the midpoint between
    /// the fingers, both in this view's coordinate space.
    var onChange: (_ verticalTranslation: CGFloat, _ midpoint: CGPoint) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        let recogniser = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recogniser.minimumNumberOfTouches = 2
        recogniser.maximumNumberOfTouches = 2
        // Runs alongside SwiftUI's own gestures rather than stealing from them.
        recogniser.delegate = context.coordinator
        view.addGestureRecognizer(recogniser)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onEnd: onEnd)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChange: (CGFloat, CGPoint) -> Void
        var onEnd: () -> Void

        init(onChange: @escaping (CGFloat, CGPoint) -> Void, onEnd: @escaping () -> Void) {
            self.onChange = onChange
            self.onEnd = onEnd
        }

        @objc func handle(_ recogniser: UIPanGestureRecognizer) {
            guard let view = recogniser.view else { return }

            switch recogniser.state {
            case .changed:
                let translation = recogniser.translation(in: view)
                onChange(translation.y, recogniser.location(in: view))
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    /// Lets taps and one-finger drags fall through to the RealityView beneath.
    private final class PassthroughView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            // The recogniser still sees the touches; hit testing does not.
            false
        }
    }
}
#endif
