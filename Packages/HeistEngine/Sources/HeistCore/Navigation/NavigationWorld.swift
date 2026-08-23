import Foundation

/// Versioned navigation state for a level.
///
/// Static level geometry is immutable. Runtime blockers (a moved chair, a
/// fallen crate, a closed gate) are an overlay. Every material change advances
/// `revision`, giving autonomous tasks one deterministic reason to replan.
public struct NavigationWorld: Sendable {
    public let geometry: LevelGeometry
    public let budget: NavigationBudget
    public private(set) var dynamicObstacles: [String: WorldBox]
    public private(set) var revision: Int
    public private(set) var grid: NavGrid
    public private(set) var bakedMesh: BakedNavigationMesh
    private let baseGrid: NavGrid

    public init(
        geometry: LevelGeometry,
        budget: NavigationBudget,
        dynamicObstacles: [String: WorldBox] = [:],
        revision: Int = 0
    ) {
        self.geometry = geometry
        self.budget = budget
        self.dynamicObstacles = dynamicObstacles
        self.revision = revision
        let baseGrid = NavGridBuilder.build(
            geometry: geometry,
            budget: budget
        )
        self.baseGrid = baseGrid
        let grid = baseGrid.blockingTransientObstacles(
            dynamicObstacles.keys.sorted().compactMap { dynamicObstacles[$0] },
            characterRadius: budget.characterRadius,
            characterHeight: budget.characterHeight
        )
        self.grid = grid
        self.bakedMesh = NavigationMeshBaker.bake(from: grid, sourceRevision: revision)
    }

    @discardableResult
    public mutating func upsertObstacle(id: String, box: WorldBox) -> Bool {
        guard dynamicObstacles[id] != box else { return false }
        dynamicObstacles[id] = box
        rebuildOverlay()
        return true
    }

    @discardableResult
    public mutating func removeObstacle(id: String) -> Bool {
        guard dynamicObstacles.removeValue(forKey: id) != nil else { return false }
        rebuildOverlay()
        return true
    }

    private mutating func rebuildOverlay() {
        revision += 1
        grid = baseGrid.blockingTransientObstacles(
            dynamicObstacles.keys.sorted().compactMap { dynamicObstacles[$0] },
            characterRadius: budget.characterRadius,
            characterHeight: budget.characterHeight
        )
        bakedMesh = NavigationMeshBaker.bake(from: grid, sourceRevision: revision)
    }
}
