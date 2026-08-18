import Foundation
import HeistCore

/// Camera settings being chosen by eye, live, on the real level.
///
/// Temporary by design. Two questions are open — which plane the view should be
/// anchored to, and what angle it should rest at — and neither can be answered
/// from a still frame or from a small test board: the anchor only shows itself
/// while a finger is moving, and the size of the effect is the height of a thing
/// times the tangent of the angle, so it needs the real level's real walls.
///
/// When the answers are settled, this and the controls that drive it come out,
/// and the numbers become the defaults in `RestingLean` and `TacticalCamera`.
public struct CameraTuning: Sendable, Equatable {
    /// Which plane stays welded to the display while the view leans.
    public enum Anchor: String, Sendable, CaseIterable, Identifiable {
        /// The outline of the building never moves; the floor slides inside it.
        case wallTops
        /// The gameplay plane never moves; the walls and everything standing on
        /// the floor lean instead.
        case floor

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .wallTops: "Верх стен"
            case .floor: "Пол"
            }
        }
    }

    public var anchor: Anchor
    /// Degrees the view rests at, down the screen.
    public var restingVertical: Double
    /// Degrees across it.
    public var restingHorizontal: Double
    /// Build the walls a third lower while the view is anchored to their tops.
    ///
    /// The anchor plane stays where it was, so it floats clear of the walls
    /// instead of sitting on them. Asked for by the owner: with the plane no
    /// longer welded to a visible edge, what it is doing becomes legible, and
    /// lower walls hide less of the room while the comparison is being made.
    public var lowerWalls: Bool

    public init(
        anchor: Anchor = .wallTops,
        restingVertical: Double = RestingLean.tactical.vertical,
        restingHorizontal: Double = RestingLean.tactical.horizontal,
        lowerWalls: Bool = true
    ) {
        self.anchor = anchor
        self.restingVertical = restingVertical
        self.restingHorizontal = restingHorizontal
        self.lowerWalls = lowerWalls
    }

    public var restingLean: RestingLean {
        RestingLean(vertical: restingVertical, horizontal: restingHorizontal)
    }

    /// How tall to build the walls, against the level's own figure.
    public var wallHeightScale: Double {
        anchor == .wallTops && lowerWalls ? 2.0 / 3.0 : 1
    }
}
