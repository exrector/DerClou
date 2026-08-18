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
    @State private var lastMagnification: CGFloat = 1
    /// The world point under the fingers when the current pinch began, and
    /// where on screen it started — so that point can be held fixed under the
    /// fingers as the pinch continues, instead of always zooming toward the
    /// level's centre.
    @State private var zoomAnchor: (screen: CGPoint, world: WorldPoint)?
    /// Keeps `SceneEvents.Update` alive for the life of the view.
    @State private var updateSubscription: EventSubscription?
    #if !canImport(UIKit)
    @State private var lastFallbackTranslation: CGSize = .zero
    #endif

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
            // Pan, tilt and pinch, split by touch count the way Maps splits
            // them: one finger drags the ground itself — the point under the
            // finger is what moves, so centring on a room is exactly
            // "drag it to where you want it," the same gesture as scrolling
            // any other view. Two fingers tilt the view instead of the
            // ground, which is what keeps the two from fighting over a single
            // touch. Pinch zooms, anchored the same way. The map itself never
            // turns — every exterior wall stays parallel to the screen — but
            // the view can lean freely.
            #if canImport(UIKit)
            .gesture(TouchDragGesture(touches: 1, onChanged: pan))
            .gesture(TouchDragGesture(touches: 2, onChanged: { _, delta in tilt(by: delta) }))
            #else
            .gesture(tiltGestureFallback)
            #endif
            .simultaneousGesture(zoomGesture)
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

    /// One finger drags the ground itself: the world point under the finger
    /// follows it exactly, the way scrolling any map or photo works. That
    /// makes "centre on this room" a single direct gesture instead of
    /// something the player has to reach by zooming out, re-centring and
    /// zooming back in.
    ///
    /// Reported as the delta since the last callback, not accumulated from
    /// where the finger first touched down — see `TouchDragGesture`.
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

    /// Two fingers tilt the view, and it stays where it is left.
    ///
    /// Two independent axes: dragging up or down tilts around world X, dragging
    /// left or right tilts around world Z, and neither depends on the other —
    /// both work from a dead-flat rest, and both are symmetric, so the far side
    /// of a room is exactly as reachable as the near one. The frame itself does
    /// not move or resize while this happens; only the camera orbits it, which
    /// is what keeps the motion smooth rather than pulsing.
    ///
    /// No spring back: tried and rejected earlier as something that fought the
    /// player's hand. The view stays exactly where it is left; the focus button
    /// is the separate, deliberate way back to flat.
    private func tilt(by delta: CGSize) {
        let degreesPerPoint = 0.12
        camera.control = camera.control.tilted(
            vertical: camera.control.leanVertical + Double(delta.height) * degreesPerPoint,
            horizontal: camera.control.leanHorizontal + Double(delta.width) * degreesPerPoint
        )
        frameCamera(size: viewportSize)
    }

    #if !canImport(UIKit)
    /// Degraded stand-in for platforms without `UIGestureRecognizerRepresentable`
    /// (this package also declares macOS as a target so its pure-logic tests can
    /// run on the host Mac — the game itself only ships on iOS). One finger
    /// tilts rather than pans, since there is no touch-count-based gesture to
    /// tell one from two fingers here. Not the shipping experience.
    private var tiltGestureFallback: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                tilt(by: CGSize(
                    width: value.translation.width - lastFallbackTranslation.width,
                    height: value.translation.height - lastFallbackTranslation.height
                ))
                lastFallbackTranslation = value.translation
            }
            .onEnded { _ in lastFallbackTranslation = .zero }
    }
    #endif

    /// Pinch zooms toward wherever the fingers landed, not the level's
    /// centre — the point first touched stays under the fingers for the rest
    /// of the gesture, the same convention as Photos and Maps.
    ///
    /// `MagnifyGesture` only ever reports where the pinch *started*
    /// (`startLocation`), not a live midpoint, so that is what is held fixed.
    /// Each step re-solves how far the anchor's world point has drifted under
    /// the new zoom and pulls the focus back by exactly that much.
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomAnchor == nil {
                    zoomAnchor = anchor(at: value.startLocation)
                }

                let factor = value.magnification / max(lastMagnification, 0.01)
                lastMagnification = value.magnification
                camera.control = camera.control.zoomed(by: factor)
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
            .onEnded { _ in
                lastMagnification = 1
                zoomAnchor = nil
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
/// A drag requiring an exact number of touches, reported as the delta since
/// the last callback rather than accumulated from wherever the gesture began.
///
/// Two things SwiftUI's own `DragGesture` cannot do, and both matter here.
///
/// First, touch count: there is no SwiftUI-native way to require two fingers
/// specifically, which is what separates panning the ground (one finger) from
/// tilting the view (two) — the same split Maps uses between panning and
/// tilting/rotating. `UIPanGestureRecognizer`'s `minimumNumberOfTouches` and
/// `maximumNumberOfTouches` do it directly.
///
/// Second, and less obvious: `DragGesture.translation` accumulates from
/// wherever the finger first touched down, for as long as the gesture lasts.
/// That reads fine on its own, but combined with a clamped value — the tilt
/// limit, or the edge of the building — it means a drag that keeps pushing
/// past the clamp keeps growing a translation that has no visible effect,
/// and reversing direction has to "unwind" that invisible backlog before the
/// view responds again. That unwind is what read as the camera snapping or
/// jerking at the extremes. `setTranslation(.zero, in:)` after every callback
/// removes the backlog entirely — each callback only ever reports what
/// changed since the last one, so there is nothing left to unwind.
private struct TouchDragGesture: UIGestureRecognizerRepresentable {
    var touches: Int
    var onChanged: (_ location: CGPoint, _ delta: CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = touches
        recognizer.maximumNumberOfTouches = touches
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
#endif
