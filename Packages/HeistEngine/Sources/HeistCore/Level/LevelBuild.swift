import Foundation

/// A blueprint turned into everything the game needs to run it, computed once.
///
/// The single entry point for preparing a level. Before this existed, the
/// validator built the geometry and the grid to check reachability, and then the
/// scene builder built both again to render — duplicated work, and two copies
/// that could disagree if either side changed its parameters.
///
/// Pure data: no RealityKit, so a level can be prepared and asserted in a unit
/// test exactly as the game will see it.
public struct LevelBuild: Sendable {
    public let blueprint: LevelBlueprint
    public let catalog: PropCatalog
    /// Navigation parameters, derived from the actors this level contains.
    public let budget: NavigationBudget
    /// World-space boxes for rendering and collision.
    public let geometry: LevelGeometry
    /// Walkability grid for path finding.
    public let grid: NavGrid
    /// Everything the validator objected to. Errors mean the level is not
    /// trustworthy and the scene should not be treated as playable.
    public let issues: [LevelIssue]

    public var hasErrors: Bool { issues.hasErrors }

    /// Prepares a level: geometry, navigation and validation, in one pass.
    public static func make(
        _ blueprint: LevelBlueprint,
        catalog: PropCatalog = .standard
    ) -> LevelBuild {
        let budget = NavigationBudget.forLevel(blueprint, catalog: catalog)
        let geometry = LevelGeometryBuilder.build(blueprint, catalog: catalog)
        let grid = NavGridBuilder.build(geometry: geometry, budget: budget)
        let issues = LevelValidator.validate(
            blueprint,
            catalog: catalog,
            budget: budget,
            geometry: geometry,
            grid: grid
        )

        return LevelBuild(
            blueprint: blueprint,
            catalog: catalog,
            budget: budget,
            geometry: geometry,
            grid: grid,
            issues: issues
        )
    }

    /// Finds a route for an actor across this level.
    public func route(from start: WorldPoint, to destination: WorldPoint) -> Result<PathResult, PathFailure> {
        PathFinder.findPath(from: start, to: destination, in: grid)
    }
}
