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

    public init(session: GameSession) {
        self.session = session
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
                if let root = session.rootEntity, root.parent == nil,
                   !content.entities.contains(where: { $0 === root }) {
                    content.entities.append(root)
                }
                frameCamera(size: viewportSize)
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        handleTap(value)
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        Self.log.debug("""
                            Raw tap at \(value.location.x, privacy: .public), \
                            \(value.location.y, privacy: .public)
                            """)
                    }
            )
            .onAppear { updateViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in updateViewport(size) }
            .onChange(of: session.level?.blueprint.id) { _, _ in frameCamera(size: viewportSize) }
        }
        .ignoresSafeArea()
    }

    private func updateViewport(_ size: CGSize) {
        viewportSize = size
        Self.log.debug("Viewport \(size.width, privacy: .public)x\(size.height, privacy: .public)")
        frameCamera(size: size)
    }

    private func frameCamera(size: CGSize) {
        guard let blueprint = session.level?.blueprint, size.width > 0, size.height > 0 else { return }
        camera.frame(
            bounds: blueprint.bounds,
            metrics: blueprint.metrics,
            aspectRatio: Double(size.width / size.height)
        )
    }

    /// Turns a screen tap into a world-space point on the floor plane.
    ///
    /// The ray/plane intersection is done explicitly rather than trusting the
    /// hit point on whatever geometry happened to be under the finger: tapping
    /// the far side of a desk should still mean "the floor there".
    private func handleTap(_ value: EntityTargetValue<SpatialTapGesture.Value>) {
        let tappedEntity = value.entity

        if let ray = value.ray(through: value.location, in: .local, to: .scene),
           let point = intersectFloorPlane(origin: ray.origin, direction: ray.direction) {
            session.handleTap(at: point, entity: tappedEntity)
            return
        }

        // Fallback: project the tap straight into the scene. Less precise on
        // sloped or stacked geometry, fine for a single-storey floor plan.
        if let point = value.unproject(\.location, to: .scene) {
            session.handleTap(at: SIMD3<Float>(point.x, 0, point.z), entity: tappedEntity)
        }
    }

    private func intersectFloorPlane(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard abs(direction.y) > 0.0001 else { return nil }
        let distance = -origin.y / direction.y
        guard distance > 0 else { return nil }
        let point = origin + direction * distance
        return SIMD3<Float>(point.x, 0, point.z)
    }
}
