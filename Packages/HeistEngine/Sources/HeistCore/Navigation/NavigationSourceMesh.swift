import Foundation

/// A raw triangle soup in world meters.
public struct TriangleMesh: Sendable, Equatable {
    public var vertices: [WorldPoint]
    public var indices: [UInt32]

    public init(vertices: [WorldPoint] = [], indices: [UInt32] = []) {
        self.vertices = vertices
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }

    public mutating func append(_ other: TriangleMesh) {
        let offset = UInt32(vertices.count)
        vertices.append(contentsOf: other.vertices)
        indices.append(contentsOf: other.indices.map { $0 + offset })
    }
}

/// Builds the triangle soup that navigation baking voxelises.
///
/// Recast-style bakers want the *whole* scene — walkable ground plus every
/// obstacle — and derive walkability from the character radius and height. So
/// this emits floors and obstacles together rather than trying to pre-carve
/// walkable polygons by hand.
public enum NavigationSourceMeshBuilder {
    public static func build(_ geometry: LevelGeometry) -> TriangleMesh {
        var mesh = TriangleMesh()
        for box in geometry.walkableBoxes {
            mesh.append(triangles(for: box))
        }
        for box in geometry.obstacleBoxes {
            mesh.append(triangles(for: box))
        }
        return mesh
    }

    /// Twelve triangles for one yawed box, wound counter-clockwise when seen
    /// from outside.
    public static func triangles(for box: WorldBox) -> TriangleMesh {
        let halfWidth = box.width / 2
        let halfHeight = box.height / 2
        let halfDepth = box.depth / 2

        let radians = box.yaw * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        func corner(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
            // Yaw around +Y.
            let rotatedX = x * cosine + z * sine
            let rotatedZ = -x * sine + z * cosine
            return WorldPoint(
                x: box.center.x + rotatedX,
                y: box.center.y + y,
                z: box.center.z + rotatedZ
            )
        }

        let vertices = [
            corner(-halfWidth, -halfHeight, -halfDepth), // 0
            corner(halfWidth, -halfHeight, -halfDepth),  // 1
            corner(halfWidth, -halfHeight, halfDepth),   // 2
            corner(-halfWidth, -halfHeight, halfDepth),  // 3
            corner(-halfWidth, halfHeight, -halfDepth),  // 4
            corner(halfWidth, halfHeight, -halfDepth),   // 5
            corner(halfWidth, halfHeight, halfDepth),    // 6
            corner(-halfWidth, halfHeight, halfDepth)    // 7
        ]

        let indices: [UInt32] = [
            // top (+y): the surface characters actually walk on
            4, 7, 6, 4, 6, 5,
            // bottom (-y)
            0, 1, 2, 0, 2, 3,
            // -z
            0, 4, 5, 0, 5, 1,
            // +z
            3, 2, 6, 3, 6, 7,
            // -x
            0, 3, 7, 0, 7, 4,
            // +x
            1, 5, 6, 1, 6, 2
        ]

        return TriangleMesh(vertices: vertices, indices: indices)
    }
}
