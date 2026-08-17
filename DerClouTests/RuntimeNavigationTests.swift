import Testing
import RealityKit
import HeistCore
// Plain import, not @testable: the engine modules are linked into the host app,
// and a second copy inside the test bundle makes RealityKit trap when the same
// component type is registered twice.
import HeistKit

/// Runtime checks that need the real RealityKit stack, so they run on a
/// simulator or device rather than in the pure-Swift package tests.
@MainActor
@Suite("Runtime navigation")
struct RuntimeNavigationTests {
    @Test("The level scene builds with no blueprint errors")
    func sceneBuilds() {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        #expect(!built.issues.hasErrors, "\(built.issues)")
        #expect(built.actors.count == 2)
        #expect(built.root.children.count > 10)
    }

    @Test("The navigation mesh bakes from generated geometry")
    func navigationBakes() throws {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        let mesh = try #require(built.navigationMesh, "NavigationMeshResource failed to bake")
        #expect(!mesh.vertices.isEmpty)
        #expect(!mesh.polygonIndices.isEmpty)
    }

    /// Disabled: `NavigationController.computePath` never returns when the scene
    /// is not being rendered. A headless `ARView` is enough to *bake* a mesh but
    /// not to service a path request, so this hangs until the test times out.
    ///
    /// The same route is verified in the app by the debug smoke route in
    /// `GameScreen`; see docs/IMPLEMENTATION_STATUS.md.
    @Test(
        "A path between the two offices routes around the divider wall",
        .disabled("Needs a rendering scene; verified by the in-app smoke route")
    )
    func pathRoutesAroundWall() async throws {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        // Anchor the level in a real scene so navigation queries resolve.
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(built.root)
        let scene = try makeScene(containing: anchor)
        _ = scene

        let thief = try #require(built.actors["office01.thief.01"])
        // Office A and office B are separated by a solid wall; the only link is
        // the corridor, so any valid path must be much longer than the direct
        // line between them.
        thief.setPosition(SIMD3<Float>(2.4, 0, 2.4), relativeTo: nil)
        let target = SIMD3<Float>(10.0, 0, 2.4)

        let controller = try NavigationController(entity: thief)
        let path = try #require(
            await controller.computePath(to: target),
            "No path computed between the two offices"
        )

        #expect(path.count >= 2)

        var length: Float = 0
        var previous = thief.position(relativeTo: nil)
        for node in path {
            length += distance(previous, node.position)
            previous = node.position
        }

        let straightLine = distance(thief.position(relativeTo: nil), target)
        #expect(length > straightLine * 1.3, "Path length \(length) vs straight line \(straightLine)")
    }

    private func makeScene(containing anchor: AnchorEntity) throws -> RealityKit.Scene {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.scene.addAnchor(anchor)
        return view.scene
    }
}
