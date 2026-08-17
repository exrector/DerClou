import Foundation

/// Single conversion layer between authoring grid units and RealityKit meters.
///
/// Level data is authored in *cells* so levels stay easy to generate and diff.
/// Everything the runtime touches is in *meters*. Nothing else in the codebase
/// is allowed to mix the two: go through `LevelMetrics`.
public struct LevelMetrics: Codable, Sendable, Equatable {
    /// Edge length of one authoring cell, in meters.
    public var cellSize: Double
    /// Height of a full-height interior wall, in meters.
    public var wallHeight: Double
    /// Thickness of an interior wall, in meters.
    public var wallThickness: Double
    /// Clear height of a doorway opening, in meters.
    public var doorwayHeight: Double
    /// Thickness of the floor slab, in meters.
    public var floorThickness: Double

    public init(
        cellSize: Double = 1.0,
        wallHeight: Double = 2.6,
        wallThickness: Double = 0.2,
        doorwayHeight: Double = 2.1,
        floorThickness: Double = 0.1
    ) {
        self.cellSize = cellSize
        self.wallHeight = wallHeight
        self.wallThickness = wallThickness
        self.doorwayHeight = doorwayHeight
        self.floorThickness = floorThickness
    }

    public static let standard = LevelMetrics()

    // MARK: - Conversion

    /// Converts a distance expressed in cells into meters.
    public func meters(fromCells cells: Double) -> Double {
        cells * cellSize
    }

    /// Converts a distance expressed in meters into cells.
    public func cells(fromMeters meters: Double) -> Double {
        meters / cellSize
    }

    /// Converts an authoring point into a world-space point on the floor plane.
    ///
    /// The building plane is X/Z with +Y up, matching RealityKit's convention.
    /// Cell +x maps to world +x, cell +y maps to world +z.
    public func worldPoint(_ point: CellPoint) -> WorldPoint {
        WorldPoint(x: point.x * cellSize, y: 0, z: point.y * cellSize)
    }

    /// Converts a world-space point back into authoring cell coordinates.
    public func cellPoint(_ point: WorldPoint) -> CellPoint {
        CellPoint(x: point.x / cellSize, y: point.z / cellSize)
    }
}
