import Foundation

/// What the walkability grid needs in order to produce usable corridors.
///
/// Walkable space is eroded by the character radius, so a gap only survives if it
/// is comfortably wider than twice that radius — and what survives has to be
/// several cells across, or the region is ragged and paths through it snake or
/// dead-end.
///
/// Getting this wrong is invisible in a level file and shows up in play as an
/// actor jamming in a doorway, which is why it is a validation rule rather than
/// a comment.
public struct NavigationBudget: Sendable, Equatable {
    /// Who the grid is built for. Everything else derives from this.
    public var character: CharacterProfile
    /// Grid resolution, in meters.
    public var cellSize: Double
    /// How many cells of clear width a gap must keep after erosion.
    public var minimumClearCells: Double

    public init(
        character: CharacterProfile = .standard,
        cellSize: Double = 0.05,
        minimumClearCells: Double = 12
    ) {
        self.character = character
        self.cellSize = cellSize
        self.minimumClearCells = minimumClearCells
    }

    public static let standard = NavigationBudget()

    /// The budget a specific level needs, derived from the actors it contains.
    public static func forLevel(_ level: LevelBlueprint, catalog: PropCatalog) -> NavigationBudget {
        let prototypes = level.actors.compactMap { catalog[$0.prototype] }
        return NavigationBudget(character: .navigationProfile(for: prototypes))
    }

    public var characterRadius: Double { character.radius }
    public var characterHeight: Double { character.height }

    /// Narrowest opening that still leaves a reliable path through it.
    public var minimumOpeningWidth: Double {
        characterRadius * 2 + cellSize * minimumClearCells
    }

    /// Clear width left after erosion, for an opening of `width`.
    public func clearWidth(forOpening width: Double) -> Double {
        width - characterRadius * 2
    }
}
