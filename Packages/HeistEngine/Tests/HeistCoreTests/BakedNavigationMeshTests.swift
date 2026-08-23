import Foundation
import Testing
@testable import HeistCore

@Suite("Baked polygon navigation")
struct BakedNavigationMeshTests {
    private let geometry = LevelGeometryBuilder.build(.office01)

    @Test("The office grid bakes into a compact connected polygon topology")
    func compactTopology() {
        let world = NavigationWorld(geometry: geometry, budget: .standard)

        #expect(world.bakedMesh.polygons.count > 1)
        #expect(world.bakedMesh.polygons.count < 2_000)
        #expect(!world.bakedMesh.portals.isEmpty)
        #expect(world.bakedMesh.sourceRevision == world.revision)
    }

    @Test("Corridor and funnel route between offices stays inside baked walkability")
    func officeCorridor() throws {
        let world = NavigationWorld(geometry: geometry, budget: .standard)
        let metrics = LevelMetrics.standard
        let start = metrics.worldPoint(CellPoint(2, 8.6))
        let goal = metrics.worldPoint(CellPoint(20, 2))

        let path = try PolygonPathFinder.findPath(
            from: start,
            to: goal,
            in: world.bakedMesh
        ).get()

        #expect(path.waypoints.count >= 2)
        for (from, to) in zip([start] + path.waypoints, path.waypoints) {
            #expect(
                PathFinder.hasLineOfSight(from: from, to: to, in: world.grid),
                "funnel segment escaped walkability: \(from) -> \(to)"
            )
        }
    }

    @Test("The baked asset is canonical and Codable")
    func canonicalRoundTrip() throws {
        let first = NavigationWorld(geometry: geometry, budget: .standard).bakedMesh
        let second = NavigationWorld(geometry: geometry, budget: .standard).bakedMesh
        #expect(first == second)

        let data = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(BakedNavigationMesh.self, from: data)
        #expect(decoded == first)
    }

    @Test("A persistent cube publishes a new polygon revision and route")
    func dynamicCube() throws {
        var world = NavigationWorld(geometry: geometry, budget: .standard)
        let point = LevelMetrics.standard.worldPoint(CellPoint(12, 8))
        let cube = WorldBox(
            center: WorldPoint(x: point.x, y: 0.45, z: point.z),
            width: 0.9, height: 0.9, depth: 0.9,
            surface: .metal, sourceID: "test.cube"
        )

        let inserted = world.upsertObstacle(id: "test.cube", box: cube)
        #expect(inserted)
        #expect(world.bakedMesh.sourceRevision == 1)
        #expect(world.bakedMesh.polygon(containing: point, maximumSnap: 0) == nil)
    }
}
