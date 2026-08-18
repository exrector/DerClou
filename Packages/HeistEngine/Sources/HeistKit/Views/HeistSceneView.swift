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
    /// How far the view was leaning when the current drag began.
    @State private var leanAtDragStart: (vertical: Double, horizontal: Double)?

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
            // Peek and pinch, but never yaw: the map is a puzzle, and it only
            // stays learnable if screen directions never move.
            .gesture(leanGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear { updateViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in updateViewport(size) }
            .onChange(of: session.level?.blueprint.id) { _, _ in updateViewport(proxy.size) }
            .onChange(of: safeAreaInsets) { _, _ in updateViewport(proxy.size) }
            .onChange(of: session.cameraTuning) { _, _ in
                applyTuning()
                frameCamera(size: viewportSize)
            }
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

    /// Hands the live tuning to the camera. Temporary; see `CameraTuning`.
    private func applyTuning() {
        camera.anchorHeight = session.anchorHeight
        camera.restingLean = session.cameraTuning.restingLean
    }

    private func frameCamera(size: CGSize) {
        guard let blueprint = session.level?.blueprint, size.width > 0, size.height > 0 else { return }
        applyTuning()
        camera.frame(
            bounds: blueprint.bounds,
            metrics: blueprint.metrics,
            aspectRatio: Double(size.width / size.height)
        )
    }

    // MARK: - Camera gestures

    /// One finger leans the view into the building.
    ///
    /// Not a pan and not a turn. The view hinges along the tops of the walls, so
    /// they stay where they are on screen while the floor and everything
    /// standing on it swing — which is how the depth of a room becomes visible
    /// in any of the four directions without the map ever rotating.
    private var leanGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if leanAtDragStart == nil {
                    leanAtDragStart = (camera.control.leanVertical, camera.control.leanHorizontal)
                }
                guard let start = leanAtDragStart else { return }

                // Degrees of lean per point of finger travel: a drag across half
                // the screen reaches the limit.
                let degreesPerPoint = 0.09

                camera.control = camera.control.leaned(
                    vertical: start.vertical + Double(value.translation.height) * degreesPerPoint,
                    horizontal: start.horizontal + Double(value.translation.width) * degreesPerPoint
                )
                frameCamera(size: viewportSize)
            }
            .onEnded { _ in
                leanAtDragStart = nil
            }
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
        // world the navigation grid is built from. The peek lives entirely in the
        // projection.
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
