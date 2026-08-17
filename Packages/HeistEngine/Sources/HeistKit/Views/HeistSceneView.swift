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
    /// How far the floor is currently slid, and where it was when the drag began.
    @State private var floorOffset: (x: Double, z: Double) = (0, 0)
    @State private var floorStart: (x: Double, z: Double)?

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
            .gesture(leanGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear { updateViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in updateViewport(size) }
            .onChange(of: session.level?.blueprint.id) { _, _ in updateViewport(proxy.size) }
            .onChange(of: safeAreaInsets) { _, _ in updateViewport(proxy.size) }
            .onChange(of: session.cameraResetToken) { _, _ in
                camera.control = .neutral
                floorOffset = (0, 0)
                session.setFloorOffset(x: 0, z: 0)
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

    /// Tips the level itself, pivoting on its centre.
    ///
    /// The camera stays put; the world leans. That is what keeps the building
    /// pinned to the display edges and stops the map appearing to rotate.
    private func applyWorldLean(blueprint: LevelBlueprint) {
        guard let root = session.rootEntity else { return }

        let tilt = camera.control.worldTilt
        let centre = blueprint.metrics.worldPoint(blueprint.bounds.center)
        let pivot = SIMD3<Float>(Float(centre.x), 0, Float(centre.z))

        let rotation = simd_quatf(angle: Float(tilt.aroundX), axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: Float(tilt.aroundZ), axis: SIMD3<Float>(0, 0, 1))

        root.orientation = rotation
        // Rotating about the origin would swing the building away from centre,
        // so the pivot is put back by hand.
        root.position = pivot - rotation.act(pivot)
    }

    // MARK: - Camera gestures

    /// One finger leans the view; the floor slides the way the finger goes.
    ///
    /// Not a pan. The building stays pinned to the display edges — what changes
    /// is the angle it is seen from, which is how the depth of a room becomes
    /// visible without the map ever turning.
    private var leanGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if floorStart == nil { floorStart = floorOffset }
                guard let start = floorStart else { return }

                // Metres of floor travel per point of finger travel, and how far
                // it may go before the floor would leave the walls behind.
                let metresPerPoint = 0.012
                let limit = 2.2

                let x = min(max(start.x + Double(value.translation.width) * metresPerPoint, -limit), limit)
                let z = min(max(start.z + Double(value.translation.height) * metresPerPoint, -limit), limit)

                floorOffset = (x: x, z: z)
                session.setFloorOffset(x: x, z: z)
            }
            .onEnded { _ in
                floorStart = nil
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

        guard let framing = camera.framing, viewportSize.width > 0 else {
            Self.log.error("Tap ignored: camera not framed yet")
            return
        }

        guard let ray = ScreenProjection.ray(
            screenPoint: (x: Double(location.x), y: Double(location.y)),
            viewportSize: (width: Double(viewportSize.width), height: Double(viewportSize.height)),
            framing: framing
        ) else {
            Self.log.error("Tap did not resolve to a ray")
            return
        }

        // The world may be leaning, so the ray is taken into the level's own
        // frame before meeting the floor. Without this a tap lands where the
        // floor *would* be if it were flat, which drifts as the view leans.
        guard let floorPoint = ScreenProjection.hit(levelSpaceRay(ray)) else {
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

    /// Converts a world-space ray into the level's own space, undoing the lean.
    ///
    /// Without this a tap lands where the floor *would* be if it were flat, and
    /// the error grows with the lean.
    private func levelSpaceRay(_ ray: WorldRay) -> WorldRay {
        guard let blueprint = session.level?.blueprint else { return ray }

        let tilt = camera.control.worldTilt
        guard abs(tilt.aroundX) > 1e-6 || abs(tilt.aroundZ) > 1e-6 else { return ray }

        let centre = blueprint.metrics.worldPoint(blueprint.bounds.center)
        let pivot = SIMD3<Float>(Float(centre.x), 0, Float(centre.z))
        let rotation = simd_quatf(angle: Float(tilt.aroundX), axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: Float(tilt.aroundZ), axis: SIMD3<Float>(0, 0, 1))
        let inverse = rotation.inverse

        func toLevel(_ point: WorldPoint) -> WorldPoint {
            let simd = SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
            let local = inverse.act(simd - pivot) + pivot
            return WorldPoint(x: Double(local.x), y: Double(local.y), z: Double(local.z))
        }

        let origin = toLevel(ray.origin)
        let ahead = toLevel(ray.origin + ray.direction)
        return WorldRay(origin: origin, direction: (ahead - origin).normalized)
    }
}
