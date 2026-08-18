import SwiftUI
import OSLog
import RealityKit
import HeistCore

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
    /// How far the current orbit drag has moved since its last callback was
    /// read — see `orbitGesture`.
    @State private var lastOrbitTranslation: CGSize = .zero
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
            // around the building, up/down drag climbs to reveal more of it —
            // and pinch zooms, anchored to wherever the fingers landed.
            .gesture(orbitGesture)
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
    /// Reported as the delta since the last callback, not the total
    /// accumulated since the finger first touched down (`DragGesture`'s own
    /// `translation`). That distinction matters once a value is clamped —
    /// `elevation` stops at its ceiling — because comparing against a frozen
    /// drag-start baseline lets the raw translation keep growing past the
    /// clamp with no visible effect, and reversing direction then has to
    /// "unwind" that invisible backlog before the view responds again, which
    /// is what read as the camera snapping once it finally caught up.
    /// Subtracting the last-seen translation every step removes the backlog
    /// entirely: there is nothing left to unwind.
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastOrbitTranslation.width,
                    height: value.translation.height - lastOrbitTranslation.height
                )
                lastOrbitTranslation = value.translation
                orbit(by: delta)
            }
            .onEnded { _ in lastOrbitTranslation = .zero }
    }

    private func orbit(by delta: CGSize) {
        let degreesPerPoint = 0.12
        camera.control = camera.control.oriented(
            elevation: camera.control.elevation + Double(delta.height) * degreesPerPoint,
            azimuth: camera.control.azimuth + Double(delta.width) * degreesPerPoint
        )
        frameCamera(size: viewportSize)
    }

    /// Pinch zooms toward wherever the fingers landed, not the level's
    /// centre — the point first touched stays under the fingers for the rest
    /// of the gesture, the same convention as Photos and Maps. With no
    /// separate pan gesture, this doubles as how the player reaches a
    /// specific room: zoom in on it, and the anchor keeps it centred.
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
