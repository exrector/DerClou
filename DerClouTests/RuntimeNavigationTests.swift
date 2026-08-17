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

    @Test("The walkability grid is built with the scene")
    func navigationGridIsBuilt() {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        #expect(built.navGrid.cellCount > 0)
        #expect(built.navGrid.walkable.contains(true))
    }

    @Test("A path between the two offices routes around the divider wall")
    func pathRoutesAroundWall() throws {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        let start = WorldPoint(x: 2.4, y: 0, z: 4.5)
        let goal = WorldPoint(x: 9.5, y: 0, z: 4.5)
        let path = try PathFinder.findPath(from: start, to: goal, in: built.navGrid).get()

        // Office A and office B are separated by a solid wall, so the route has
        // to detour through the corridor rather than cut across.
        #expect(path.length > 9.0, "length \(path.length)")
        #expect(path.waypoints.contains { $0.z > 6.4 })
    }

}
