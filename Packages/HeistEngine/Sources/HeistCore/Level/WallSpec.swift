import Foundation

/// What kind of hole is cut through a wall.
public enum OpeningKind: String, Codable, Sendable, CaseIterable {
    /// Floor-to-lintel gap, usually filled by a door prop.
    case doorway
    /// Gap with a sill below and a lintel above.
    case window
    /// Full-height gap with no lintel, used for open archways.
    case passage
}

/// A hole in a wall, positioned along the wall's own axis.
public struct WallOpening: Codable, Sendable, Equatable {
    public var kind: OpeningKind
    /// Distance from the wall start to the *center* of the opening, in cells.
    public var center: Double
    /// Width of the opening, in cells.
    public var width: Double
    /// Overrides `LevelMetrics.doorwayHeight` for this opening, in meters.
    public var headHeight: Double?
    /// Height of the sill for `.window` openings, in meters.
    public var sillHeight: Double?

    public init(
        kind: OpeningKind,
        center: Double,
        width: Double,
        headHeight: Double? = nil,
        sillHeight: Double? = nil
    ) {
        self.kind = kind
        self.center = center
        self.width = width
        self.headHeight = headHeight
        self.sillHeight = sillHeight
    }

    public var span: ClosedRange<Double> {
        (center - width / 2)...(center + width / 2)
    }
}

/// One straight run of wall between two grid points, with holes cut in it.
///
/// A wall is deliberately just a line plus openings. That is the whole
/// vocabulary: it is enough to describe any rectilinear building and it is
/// trivial to emit from a generator.
public struct WallSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var start: CellPoint
    public var end: CellPoint
    public var openings: [WallOpening]
    /// Material key resolved against the environment kit.
    public var material: String
    /// Overrides `LevelMetrics.wallThickness`, in meters.
    ///
    /// Exterior walls are deliberately thick. They extend past the floor, so
    /// they are what falls under a hardware cutout at the edge of the display —
    /// architecture rather than empty space. See docs/DEVELOPMENT_FINDINGS.md.
    public var thickness: Double?

    public init(
        id: String,
        start: CellPoint,
        end: CellPoint,
        openings: [WallOpening] = [],
        material: String = "wall.plaster",
        thickness: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.openings = openings
        self.material = material
        self.thickness = thickness
    }

    /// Length of the wall run, in cells.
    public var length: Double {
        start.distance(to: end)
    }

    /// Unit direction of the wall in cell space.
    public var direction: CellPoint {
        let length = self.length
        guard length > 0 else { return CellPoint(x: 1, y: 0) }
        return CellPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
    }

    /// Point at `distance` cells along the wall.
    public func point(atDistance distance: Double) -> CellPoint {
        let direction = self.direction
        return CellPoint(x: start.x + direction.x * distance, y: start.y + direction.y * distance)
    }
}

/// One solid piece of wall geometry produced from a `WallSpec`.
///
/// `span` is measured along the wall in cells; `bottom`/`top` are in meters.
public struct WallSegment: Sendable, Equatable {
    public var span: ClosedRange<Double>
    public var bottom: Double
    public var top: Double

    public init(span: ClosedRange<Double>, bottom: Double, top: Double) {
        self.span = span
        self.bottom = bottom
        self.top = top
    }

    public var length: Double { span.upperBound - span.lowerBound }
    public var height: Double { top - bottom }
}

extension WallSpec {
    /// Splits the wall into solid boxes, cutting out openings and adding
    /// lintels/sills back above and below them.
    ///
    /// Deterministic and pure: the same spec always yields the same segments in
    /// the same order. This is the function level generation leans on, so it is
    /// unit tested rather than eyeballed in the viewport.
    public func segments(metrics: LevelMetrics) -> [WallSegment] {
        let wallTop = metrics.wallHeight
        let sorted = openings
            .filter { $0.width > 0 }
            .sorted { $0.span.lowerBound < $1.span.lowerBound }

        var segments: [WallSegment] = []
        var cursor = 0.0

        for opening in sorted {
            let lower = max(0, opening.span.lowerBound)
            let upper = min(length, opening.span.upperBound)
            guard upper > lower else { continue }

            if lower > cursor {
                segments.append(WallSegment(span: cursor...lower, bottom: 0, top: wallTop))
            }

            let head = opening.headHeight ?? metrics.doorwayHeight
            switch opening.kind {
            case .doorway:
                if head < wallTop {
                    segments.append(WallSegment(span: lower...upper, bottom: head, top: wallTop))
                }
            case .window:
                let sill = opening.sillHeight ?? 0.9
                if sill > 0 {
                    segments.append(WallSegment(span: lower...upper, bottom: 0, top: sill))
                }
                if head < wallTop {
                    segments.append(WallSegment(span: lower...upper, bottom: head, top: wallTop))
                }
            case .passage:
                break
            }

            cursor = max(cursor, upper)
        }

        if cursor < length {
            segments.append(WallSegment(span: cursor...length, bottom: 0, top: wallTop))
        }

        return segments
    }
}
