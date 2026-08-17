import Foundation
import OSLog
import RealityKit
import HeistCore

/// Bakes a navigation mesh from level geometry at runtime.
///
/// Baking in code rather than authoring a mesh per scene in Reality Composer Pro
/// is what makes generated levels viable: emit a blueprint, get navigation for
/// free. Authored meshes stay possible later for hand-tuned hero levels.
public enum NavigationBaker {
    private static let log = Logger(subsystem: "com.exrector.DerClou", category: "navigation")

    /// Recast-style bake settings derived from the character we actually use.
    public static func configuration(
        characterRadius: Double = 0.3,
        characterHeight: Double = 1.75
    ) -> NavigationMeshResource.Configuration {
        NavigationMeshResource.Configuration(
            cellSize: 0.1,
            cellHeight: 0.1,
            walkableSlopeAngle: 45,
            characterHeight: characterHeight,
            walkableClimb: 0.3,
            characterRadius: characterRadius
        )
    }

    public static func bake(
        geometry: LevelGeometry,
        configuration: NavigationMeshResource.Configuration = configuration()
    ) -> NavigationMeshResource? {
        let source = NavigationSourceMeshBuilder.build(geometry)
        guard !source.vertices.isEmpty else {
            log.error("Navigation bake skipped: no source geometry")
            return nil
        }

        let vertices = source.vertices.map {
            SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
        }

        do {
            let mesh = try NavigationMeshResource(
                triangleIndices: source.indices,
                vertices: vertices,
                configuration: configuration
            )
            log.info("""
                Navigation baked: \(source.triangleCount) source triangles \
                -> \(mesh.polygonIndices.count) polygons
                """)
            return mesh
        } catch {
            log.error("Navigation bake failed: \(error.localizedDescription)")
            return nil
        }
    }
}
