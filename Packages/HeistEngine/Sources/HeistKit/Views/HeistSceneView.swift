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
    @State private var lastDragTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    /// Peek angle and the world point under the fingers when the gesture began.
    @State private var peekStart: (degrees: Double, anchor: WorldPoint, screen: CGPoint)?

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
            // Pan and pinch, but never rotation: the map is a puzzle, and it
            // only stays learnable if screen directions never move.
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            // Two fingers dragged vertically tilt the camera. Not a SwiftUI
            // gesture because DragGesture cannot tell one finger from two.
            .overlay {
                #if canImport(UIKit)
                TwoFingerDragView(
                    onChange: { translation, midpoint in
                        peek(verticalTranslation: translation, around: midpoint)
                    },
                    onEnd: { peekStart = nil }
                )
                #endif
            }
            .onAppear { updateViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in updateViewport(size) }
            .onChange(of: session.level?.blueprint.id) { _, _ in updateViewport(proxy.size) }
            .onChange(of: safeAreaInsets) { _, _ in updateViewport(proxy.size) }
            .onChange(of: session.cameraResetToken) { _, _ in
                camera.control = .neutral
                frameCamera(size: viewportSize)
            }
            // Mission time advances here, and only here: this is the single
            // point where render time is allowed to touch gameplay.
            .task {
                var last = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(16))
                    let now = Date()
                    session.tick(realTimeDelta: now.timeIntervalSince(last))
                    last = now
                }
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
        guard let framing = camera.framing, size.width > 0, size.height > 0 else { return }
        session.updateSafeArea(
            viewportSize: (width: Double(size.width), height: Double(size.height)),
            insets: ScreenInsets(
                top: Double(safeAreaInsets.top),
                leading: Double(safeAreaInsets.leading),
                bottom: Double(safeAreaInsets.bottom),
                trailing: Double(safeAreaInsets.trailing)
            ),
            framing: framing
        )
    }

    private func frameCamera(size: CGSize) {
        guard let blueprint = session.level?.blueprint, size.width > 0, size.height > 0 else { return }
        camera.frame(
            bounds: blueprint.bounds,
            metrics: blueprint.metrics,
            aspectRatio: Double(size.width / size.height),
            screenInsets: ScreenInsets(
                top: Double(safeAreaInsets.top),
                leading: Double(safeAreaInsets.leading),
                bottom: Double(safeAreaInsets.bottom),
                trailing: Double(safeAreaInsets.trailing)
            ),
            viewportSize: (width: Double(size.width), height: Double(size.height))
        )
    }

    // MARK: - Camera gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard let blueprint = session.level?.blueprint,
                      let framing = camera.framing,
                      viewportSize.height > 0 else { return }

                // Convert the drag into world meters at the current zoom, so a
                // finger stays on the same spot on the floor.
                let metersPerPoint = framing.verticalExtent / Double(viewportSize.height)
                let delta = WorldPoint(
                    x: -Double(value.translation.width - lastDragTranslation.width) * metersPerPoint,
                    y: 0,
                    z: -Double(value.translation.height - lastDragTranslation.height) * metersPerPoint
                )
                lastDragTranslation = value.translation

                camera.control = camera.control.panned(
                    by: delta,
                    within: blueprint.bounds,
                    metrics: blueprint.metrics
                )
                frameCamera(size: viewportSize)
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }

    /// Tilts the camera while holding the point under the fingers in place.
    ///
    /// Without the anchor the whole map slides out from under the hand and the
    /// gesture reads as the camera lurching rather than as leaning in to look.
    private func peek(verticalTranslation: CGFloat, around midpoint: CGPoint) {
        guard let blueprint = session.level?.blueprint,
              let framing = camera.framing,
              viewportSize.height > 0 else { return }

        let viewport = (width: Double(viewportSize.width), height: Double(viewportSize.height))

        if peekStart == nil {
            guard let ray = ScreenProjection.ray(
                screenPoint: (x: Double(midpoint.x), y: Double(midpoint.y)),
                viewportSize: viewport,
                framing: framing
            ), let anchor = ScreenProjection.hit(ray) else { return }
            peekStart = (camera.control.peekDegrees, anchor, midpoint)
        }
        guard let start = peekStart else { return }

        // Dragging up leans in; the range is small by design.
        let degreesPerPoint = 0.06
        camera.control = camera.control.peeked(
            to: start.degrees - Double(verticalTranslation) * degreesPerPoint
        )
        frameCamera(size: viewportSize)

        // Re-pan so the anchor lands back where the fingers are.
        guard let tilted = camera.framing,
              let now = ScreenProjection.screenPoint(
                of: start.anchor,
                viewportSize: viewport,
                framing: tilted
              ) else { return }

        let metersPerPoint = tilted.verticalExtent / viewport.height
        let correction = WorldPoint(
            x: (now.x - Double(start.screen.x)) * metersPerPoint,
            y: 0,
            z: (now.y - Double(start.screen.y)) * metersPerPoint
        )
        camera.control = camera.control.panned(
            by: correction,
            within: blueprint.bounds,
            metrics: blueprint.metrics
        )
        frameCamera(size: viewportSize)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let factor = value.magnification / max(lastMagnification, 0.01)
                lastMagnification = value.magnification
                camera.control = camera.control.zoomed(by: factor)
                frameCamera(size: viewportSize)
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }

    /// Turns a screen tap into a world point on the floor plane, plus whatever
    /// the ray hits along the way.
    private func handleTap(at location: CGPoint) {
        Self.log.debug("""
            Tap at \(location.x, privacy: .public), \(location.y, privacy: .public)
            """)

        guard let framing = camera.framing, viewportSize.width > 0 else {
            Self.log.error("Tap ignored: camera not framed yet")
            return
        }

        guard let ray = ScreenProjection.ray(
            screenPoint: (x: Double(location.x), y: Double(location.y)),
            viewportSize: (width: Double(viewportSize.width), height: Double(viewportSize.height)),
            framing: framing
        ), let floorPoint = ScreenProjection.hit(ray) else {
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
