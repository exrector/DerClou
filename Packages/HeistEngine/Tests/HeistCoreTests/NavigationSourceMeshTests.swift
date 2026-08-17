import Testing
@testable import HeistCore

@Suite("Navigation source mesh")
struct NavigationSourceMeshTests {
    @Test("One box is twelve triangles")
    func boxTriangles() {
        let box = WorldBox(
            center: .zero,
            width: 2,
            height: 1,
            depth: 4,
            surface: .concrete,
            sourceID: "test"
        )
        let mesh = NavigationSourceMeshBuilder.triangles(for: box)

        #expect(mesh.vertices.count == 8)
        #expect(mesh.triangleCount == 12)
        #expect(mesh.indices.allSatisfy { $0 < 8 })
    }

    @Test("A yaw of 90 degrees swaps the box footprint")
    func yawedBox() {
        let box = WorldBox(
            center: .zero,
            width: 4,
            height: 1,
            depth: 1,
            yaw: 90,
            surface: .plaster,
            sourceID: "test"
        )
        let mesh = NavigationSourceMeshBuilder.triangles(for: box)
        let spanX = (mesh.vertices.map(\.x).max() ?? 0) - (mesh.vertices.map(\.x).min() ?? 0)
        let spanZ = (mesh.vertices.map(\.z).max() ?? 0) - (mesh.vertices.map(\.z).min() ?? 0)

        #expect(abs(spanX - 1) < 0.0001)
        #expect(abs(spanZ - 4) < 0.0001)
    }

    @Test("Appending remaps indices instead of colliding")
    func appendRemapsIndices() {
        var mesh = TriangleMesh(vertices: [.zero], indices: [0, 0, 0])
        mesh.append(TriangleMesh(vertices: [.zero, .zero], indices: [0, 1, 0]))

        #expect(mesh.vertices.count == 3)
        #expect(mesh.indices == [0, 0, 0, 1, 2, 1])
    }

    @Test("office01 produces a bake-ready mesh with floors and obstacles")
    func officeMesh() {
        let geometry = LevelGeometryBuilder.build(.office01)
        let mesh = NavigationSourceMeshBuilder.build(geometry)

        let expectedBoxes = geometry.walkableBoxes.count + geometry.obstacleBoxes.count
        #expect(mesh.triangleCount == expectedBoxes * 12)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })

        // The divider between the two offices has to be in the bake, otherwise
        // pathfinding would cut straight through it.
        #expect(geometry.obstacleBoxes.contains { $0.sourceID.hasPrefix("office01.wall.divider") })
    }

    @Test("Mesh building is deterministic")
    func deterministic() {
        let geometry = LevelGeometryBuilder.build(.office01)
        #expect(NavigationSourceMeshBuilder.build(geometry) == NavigationSourceMeshBuilder.build(geometry))
    }
}
