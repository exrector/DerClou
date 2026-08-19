import SwiftUI
import OSLog
import RealityKit
import HeistCore

#if canImport(UIKit)
import UIKit
#endif

/// The 3D tactical view: orthographic camera, level scene, tap-to-move.
///
/// Owns nothing but presentation and input translation — game state lives in
/// `GameSession`.
public struct HeistSceneView: View {
    private static let log = Logger(subsystem: "com.exrector.DerClou", category: "view")

    @Bindable private var session: GameSession
    @State private var camera = TacticalCamera()
    @State private var viewportSize: CGSize = .zero
    /// The world point under the fingers when the current pinch began, and
    /// where on screen it started — so that point can be held fixed under the
    /// fingers as the pinch continues, instead of always zooming toward the
    /// level's centre.
    @State private var zoomAnchor: (screen: CGPoint, world: WorldPoint)?
    /// A light exponential average of recent orbit deltas — see `orbit(by:)`.
    @State private var smoothedOrbitDelta: CGSize = .zero
    #if !canImport(UIKit)
    /// How far the current orbit drag has moved since its last callback was
    /// read — see `orbitGestureFallback`.
    @State private var lastOrbitTranslation: CGSize = .zero
    #endif
    /// Keeps `SceneEvents.Update` alive for the life of the view.
    @State private var updateSubscription: EventSubscription?

    /// System safe-area insets, read by the caller *outside* `ignoresSafeArea`.
    private let safeAreaInsets: EdgeInsets

    public init(session: GameSession, safeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.session = session
        self.safeAreaInsets = safeAreaInsets
    }

    public var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.entities.append(camera.entity)
                if let root = session.rootEntity {
                    content.entities.append(root)
                }
                // Mission time advances here, and only here: this is the
                // single point where render time is allowed to touch
                // gameplay. Driven by RealityKit's own per-frame event
                // rather than a hand-rolled timer, so it is exactly in step
                // with what is actually being rendered.
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    session.tick(realTimeDelta: event.deltaTime)
                }
            } update: { content in
                // The level loads asynchronously, so the root usually appears
                // after the view is first made.
                if let root = session.rootEntity,
                   !content.entities.contains(where: { $0 === root }) {
                    content.entities.append(root)
                }
                frameCamera(size: viewportSize)
            }
            // A plain tap, resolved by our own projection.
            //
            // `SpatialTapGesture().targetedToAnyEntity()` was tried first and
            // never fired on device: it only reports taps that RealityKit's
            // input stack matches to an entity, and that never happened for the
            // orthographic non-AR scene. Projecting the tap ourselves works
            // regardless, and is unit tested.
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location)
            }
            // One finger orbits the view — sideways drag spins all the way
            // around the building, up/down drag climbs to reveal more of it.
            // Two fingers pan instead, which is what lets the player recentre
            // once already zoomed in, without touching the zoom level. Pinch
            // zooms, anchored to wherever the fingers landed.
            //
            // All three are raw UIKit gesture recognizers sharing one
            // `AlwaysSimultaneousDelegate` — see its doc comment for why that
            // turned out to matter more than anything about touch counting.
            #if canImport(UIKit)
            .gesture(TouchDragGesture(touches: 1, onChanged: { _, delta in orbit(by: delta) }))
            .gesture(TouchDragGesture(touches: 2, onChanged: pan))
            .gesture(TouchPinchGesture(onChanged: zoom, onEnded: { zoomAnchor = nil }))
            #else
            .gesture(orbitGestureFallback)
            #endif
            .onAppear { updateViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in updateViewport(size) }
            .onChange(of: session.level?.blueprint.id) { _, _ in updateViewport(proxy.size) }
            .onChange(of: safeAreaInsets) { _, _ in updateViewport(proxy.size) }
            .onChange(of: session.cameraResetToken) { _, _ in
                camera.control = .neutral
                frameCamera(size: viewportSize)
            }
        }
        // The world fills the display; only gameplay-critical placement and the
        // HUD respect the safe area. See docs/DEVELOPMENT_FINDINGS.md.
        .ignoresSafeArea()
    }

    private func updateViewport(_ size: CGSize) {
        viewportSize = size
        Self.log.debug("""
            Viewport \(size.width, privacy: .public)x\(size.height, privacy: .public), \
            insets L\(safeAreaInsets.leading, privacy: .public) T\(safeAreaInsets.top, privacy: .public) \
            R\(safeAreaInsets.trailing, privacy: .public) B\(safeAreaInsets.bottom, privacy: .public)
            """)
        frameCamera(size: size)

        // The safe region is derived from the framing, so it follows it.
        guard let projection = camera.projection, size.width > 0, size.height > 0 else { return }
        session.updateSafeArea(
            viewportSize: (width: Double(size.width), height: Double(size.height)),
            insets: ScreenInsets(
                top: Double(safeAreaInsets.top),
                leading: Double(safeAreaInsets.leading),
                bottom: Double(safeAreaInsets.bottom),
                trailing: Double(safeAreaInsets.trailing)
            ),
            projection: projection
        )
    }

    private func frameCamera(size: CGSize) {
        guard let blueprint = session.level?.blueprint, size.width > 0, size.height > 0 else { return }
        camera.frame(
            bounds: blueprint.bounds,
            metrics: blueprint.metrics,
            aspectRatio: Double(size.width / size.height)
        )
    }

    // MARK: - Camera gestures

    /// One finger orbits the view: dragging sideways turns `azimuth`, which
    /// wraps all the way around the building with nothing to hit; dragging up
    /// or down climbs `elevation`, which reveals more of whatever side is
    /// currently facing the camera. The two are independent, so either works
    /// on its own from rest.
    ///
    /// No spring back: tried and rejected earlier as something that fought
    /// the player's hand. The view stays exactly where it is left; the focus
    /// button is the separate, deliberate way back to flat.
    ///
    /// A light exponential average of the incoming deltas takes the edge off
    /// per-callback touch jitter — a real finger is never perfectly steady —
    /// without adding perceptible lag: at `smoothing = 0.4` each step is
    /// already 84% converged to a sustained motion within three callbacks.
    private func orbit(by delta: CGSize) {
        let smoothing = 0.4
        smoothedOrbitDelta = CGSize(
            width: smoothedOrbitDelta.width * smoothing + delta.width * (1 - smoothing),
            height: smoothedOrbitDelta.height * smoothing + delta.height * (1 - smoothing)
        )

        let degreesPerPoint = 0.12
        camera.control = camera.control.oriented(
            elevation: camera.control.elevation + Double(smoothedOrbitDelta.height) * degreesPerPoint,
            azimuth: camera.control.azimuth + Double(smoothedOrbitDelta.width) * degreesPerPoint
        )
        frameCamera(size: viewportSize)
    }

    /// Two fingers drag the ground itself: the world point under the fingers
    /// follows them exactly, the way scrolling any map or photo works. This
    /// is how the player recentres once already zoomed in — orbiting alone
    /// only ever looks around a fixed point, never moves it — without
    /// touching the zoom level the way pinching back out and back in would.
    ///
    /// Kept exact rather than smoothed, unlike `orbit(by:)`: the whole point
    /// is that the ground stays glued to the fingers, and averaging in past
    /// samples would introduce a small lag between the two.
    private func pan(location: CGPoint, delta: CGSize) {
        let previous = CGPoint(x: location.x - delta.width, y: location.y - delta.height)
        guard let worldAtPrevious = worldPoint(at: previous),
              let worldAtCurrent = worldPoint(at: location) else { return }

        let shift = WorldPoint(
            x: worldAtPrevious.x - worldAtCurrent.x,
            y: 0,
            z: worldAtPrevious.z - worldAtCurrent.z
        )
        camera.control = camera.control.focused(at: camera.control.focusOffset + shift)
        frameCamera(size: viewportSize)
    }

    #if !canImport(UIKit)
    /// Degraded stand-in for platforms without `UIGestureRecognizerRepresentable`
    /// (this package also declares macOS as a target so its pure-logic tests can
    /// run on the host Mac — the game itself only ships on iOS). Orbits only;
    /// there is no touch-count-based gesture here to add two-finger pan or
    /// pinch-zoom on top of it. Not the shipping experience.
    private var orbitGestureFallback: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                orbit(by: CGSize(
                    width: value.translation.width - lastOrbitTranslation.width,
                    height: value.translation.height - lastOrbitTranslation.height
                ))
                lastOrbitTranslation = value.translation
            }
            .onEnded { _ in lastOrbitTranslation = .zero }
    }
    #endif

    /// Pinch zooms toward wherever the fingers landed, not the level's
    /// centre — the point first touched stays under the fingers for the rest
    /// of the gesture, the same convention as Photos and Maps.
    ///
    /// `scale` arrives already incremental (see `TouchPinchGesture`), so
    /// unlike the `MagnifyGesture` this replaced, there is no need to divide
    /// out a running "last magnification" first.
    private func zoom(location: CGPoint, scale: CGFloat) {
        if zoomAnchor == nil {
            zoomAnchor = anchor(at: location)
        }

        camera.control = camera.control.zoomed(by: Double(scale))
        frameCamera(size: viewportSize)

        if let zoomAnchor, let drifted = worldPoint(at: zoomAnchor.screen) {
            let correction = WorldPoint(
                x: zoomAnchor.world.x - drifted.x,
                y: 0,
                z: zoomAnchor.world.z - drifted.z
            )
            camera.control = camera.control.focused(at: camera.control.focusOffset + correction)
            frameCamera(size: viewportSize)
        }
    }

    /// The world point a screen location resolves to right now, plus the
    /// location itself, for later re-resolving as the camera changes.
    private func anchor(at screen: CGPoint) -> (screen: CGPoint, world: WorldPoint)? {
        worldPoint(at: screen).map { (screen, $0) }
    }

    private func worldPoint(at screen: CGPoint) -> WorldPoint? {
        guard let projection = camera.projection, viewportSize.width > 0 else { return nil }
        return projection.ray(
            screenPoint: (x: Double(screen.x), y: Double(screen.y)),
            viewportSize: (width: Double(viewportSize.width), height: Double(viewportSize.height))
        )?.hit()
    }

    /// Turns a screen tap into a world point on the floor plane, plus whatever
    /// the ray hits along the way.
    private func handleTap(at location: CGPoint) {
        Self.log.debug("""
            Tap at \(location.x, privacy: .public), \(location.y, privacy: .public)
            """)

        guard let projection = camera.projection, viewportSize.width > 0 else {
            Self.log.error("Tap ignored: camera not framed yet")
            return
        }

        guard let ray = projection.ray(
            screenPoint: (x: Double(location.x), y: Double(location.y)),
            viewportSize: (width: Double(viewportSize.width), height: Double(viewportSize.height))
        ) else {
            Self.log.error("Tap did not resolve to a ray")
            return
        }

        // No conversion anywhere: the world the ray travels through is the same
        // world the navigation grid is built from. The tilt lives entirely in
        // the projection.
        guard let floorPoint = ray.hit() else {
            Self.log.error("Tap did not resolve to the floor plane")
            return
        }

        let destination = SIMD3<Float>(
            Float(floorPoint.x),
            0,
            Float(floorPoint.z)
        )
        let hit = session.entity(along: ray)

        Self.log.debug("""
            Tap -> world \(destination.x, privacy: .public), \(destination.z, privacy: .public) \
            on \(hit?.name ?? "floor", privacy: .public)
            """)

        session.handleTap(at: destination, entity: hit)
    }
}

#if canImport(UIKit)
/// A delegate that unconditionally allows whatever wears it to recognize
/// alongside every other gesture recognizer on the same view.
///
/// This is the actual fix, and the thing all three earlier attempts at this
/// gesture setup were missing. UIKit's default is exclusive: once one
/// gesture recognizer recognizes, every other one racing it on the same
/// touches is blocked unless a delegate on (at least) one of the pair says
/// otherwise. Orbit and pan are pinned to different touch counts, so they
/// were never really the problem once each read its own fixed count —
/// but zoom was still `MagnifyGesture`, a gesture living inside SwiftUI's
/// *own* internal recognizer system, entirely separate from the raw
/// `UIPanGestureRecognizer`s this file adds directly to the view. Those two
/// systems do not know about each other's `.simultaneousGesture` — that
/// modifier only coordinates gestures within SwiftUI's own `Gesture` tree —
/// so a real two-finger pan and the pinch recognizer backing `MagnifyGesture`
/// were quietly fighting over the same two touches by UIKit's default
/// exclusivity rule, with neither side configured to allow the other. Moving
/// zoom onto a raw `UIPinchGestureRecognizer` puts all three gestures in the
/// same system, where this one shared delegate can actually say "yes,
/// simultaneously" to every pair of them.
private final class AlwaysSimultaneousDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// A drag pinned to an exact number of touches.
///
/// `UIPanGestureRecognizer`'s own `minimumNumberOfTouches`/
/// `maximumNumberOfTouches` already refuse to recognize with the wrong touch
/// count — there is no need to hand-count touches here the way earlier
/// versions of this type did. What those versions were actually missing is
/// `AlwaysSimultaneousDelegate`: without it, whichever of the 1-touch and
/// 2-touch recognizers happens to recognize first (almost always the 1-touch
/// one, since real fingers rarely land in the same touch batch) blocks the
/// other for the rest of that touch sequence by UIKit's default exclusivity,
/// no matter how correct their own touch-count configuration is.
///
/// Deltas are reported via `setTranslation(.zero, in:)` after every callback
/// rather than `DragGesture`'s own start-accumulated `translation` — see
/// `orbit(by:)` for why that still matters once `elevation` clamps.
private struct TouchDragGesture: UIGestureRecognizerRepresentable {
    var touches: Int
    var onChanged: (_ location: CGPoint, _ delta: CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> AlwaysSimultaneousDelegate {
        AlwaysSimultaneousDelegate()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = touches
        recognizer.maximumNumberOfTouches = touches
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .changed else { return }
        let translation = recognizer.translation(in: recognizer.view)
        guard translation != .zero else { return }
        recognizer.setTranslation(.zero, in: recognizer.view)
        onChanged(recognizer.location(in: recognizer.view), CGSize(width: translation.x, height: translation.y))
    }
}

/// Pinch, reported as the scale factor since the last callback rather than
/// `UIPinchGestureRecognizer`'s own start-accumulated `scale` — resetting it
/// to 1 after every callback is the same technique `TouchDragGesture` uses
/// for translation, and for the same reason: `zoom` is clamped
/// (`CameraControl.zoomRange`), so comparing against a frozen gesture-start
/// baseline would let a pinch that keeps pushing past the clamp build an
/// invisible overshoot that has to be unwound before zoom responds again.
///
/// Wraps `UIPinchGestureRecognizer` instead of SwiftUI's own `MagnifyGesture`
/// so zoom shares `AlwaysSimultaneousDelegate` with orbit and pan — see that
/// type's doc comment for why that turned out to be the actual bug.
///
/// `onEnded` matters here in a way it didn't for `TouchDragGesture`: the view
/// keeps a `zoomAnchor` across callbacks *within* one pinch, captured on its
/// first callback and reused for the rest of that same gesture (see
/// `zoom(location:scale:)`). Forgetting to clear it when the gesture ends —
/// the actual regression the first version of this type shipped with, moving
/// off `MagnifyGesture`'s own `.onEnded` without carrying the reset along —
/// leaves the anchor pointing at wherever the *previous* pinch happened to
/// end. Every pinch after that corrects zoom toward a stale, unrelated point
/// instead of the one actually under the fingers, which reads as the zoom
/// centring on the wrong place and, since that stale correction fights the
/// live one every callback, as jittery on top of that.
private struct TouchPinchGesture: UIGestureRecognizerRepresentable {
    var onChanged: (_ location: CGPoint, _ scale: CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> AlwaysSimultaneousDelegate {
        AlwaysSimultaneousDelegate()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            let scale = recognizer.scale
            guard scale != 1 else { return }
            recognizer.scale = 1
            onChanged(recognizer.location(in: recognizer.view), scale)

        case .ended, .cancelled, .failed:
            onEnded()

        default:
            break
        }
    }
}
#endif
