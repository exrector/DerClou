import Foundation

/// A problem found in a blueprint before anything is built.
public struct LevelIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public var severity: Severity
    public var subject: String
    public var message: String

    public init(severity: Severity, subject: String, message: String) {
        self.severity = severity
        self.subject = subject
        self.message = message
    }

    public var description: String {
        "[\(severity.rawValue)] \(subject): \(message)"
    }
}

/// Checks a blueprint against the catalog.
///
/// This exists because levels are meant to be generated. A generator that emits
/// a broken level should fail loudly here, not produce a scene where the thief
/// walks through a wall.
public enum LevelValidator {
    /// Checks a prepared level. Takes the already-built geometry and grid so
    /// nothing is computed twice and both sides judge the same thing.
    public static func validate(
        _ level: LevelBlueprint,
        catalog: PropCatalog,
        budget: NavigationBudget,
        geometry: LevelGeometry,
        grid: NavGrid
    ) -> [LevelIssue] {
        var issues: [LevelIssue] = []

        if level.floors.isEmpty {
            issues.append(LevelIssue(
                severity: .error,
                subject: level.id,
                message: "Level has no floors, so it has no navigable surface"
            ))
        }

        issues.append(contentsOf: duplicateIDIssues(in: level))

        for wall in level.walls {
            if wall.length <= 0 {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: wall.id,
                    message: "Wall has zero length"
                ))
                continue
            }
            for opening in wall.openings {
                if opening.span.lowerBound < -0.001 || opening.span.upperBound > wall.length + 0.001 {
                    issues.append(LevelIssue(
                        severity: .error,
                        subject: wall.id,
                        message: "Opening at \(opening.center) (width \(opening.width)) falls outside the wall run of \(wall.length)"
                    ))
                }
            }
            for opening in wall.openings where opening.kind != .window {
                let widthInMeters = level.metrics.meters(fromCells: opening.width)
                // Tolerance, or a doorway authored at exactly the minimum trips
                // on floating-point noise in the threshold itself.
                guard widthInMeters < budget.minimumOpeningWidth - 0.0001 else { continue }
                let clear = budget.clearWidth(forOpening: widthInMeters)
                issues.append(LevelIssue(
                    severity: clear > 0 ? .warning : .error,
                    subject: wall.id,
                    message: String(
                        format: "Opening at %.1f is %.2f m wide; after eroding for a %.2f m character radius only %.2f m remains, below the %.2f m needed for a reliable path",
                        opening.center,
                        widthInMeters,
                        budget.characterRadius,
                        clear,
                        budget.minimumOpeningWidth
                    )
                ))
            }

            for (lhs, rhs) in consecutivePairs(wall.openings.sorted { $0.span.lowerBound < $1.span.lowerBound }) {
                if lhs.span.upperBound > rhs.span.lowerBound + 0.001 {
                    issues.append(LevelIssue(
                        severity: .error,
                        subject: wall.id,
                        message: "Openings at \(lhs.center) and \(rhs.center) overlap"
                    ))
                }
            }
        }

        for prop in level.props {
            guard let prototype = catalog[prop.prototype] else {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: prop.id,
                    message: "Unknown prototype '\(prop.prototype)'"
                ))
                continue
            }
            let placement = prototype.placementContract
            if !placement.isAligned(prop.position) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: prop.id,
                    message: "Position is off the prototype's \(placement.positionSnapCells)-cell placement grid"
                ))
            }
            if !placement.isRotationAligned(prop.rotation) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: prop.id,
                    message: "Rotation is off the prototype's \(placement.rotationSnapDegrees)-degree increment"
                ))
            }
            // Scenery is meant to sit outside the building.
            if prototype.kind == .scenery { continue }
            if !isOnFloor(prop.position, level: level) {
                issues.append(LevelIssue(
                    severity: .warning,
                    subject: prop.id,
                    message: "Placed outside every floor rect"
                ))
            }
        }

        for actor in level.actors {
            guard let prototype = catalog[actor.prototype] else {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: actor.id,
                    message: "Unknown prototype '\(actor.prototype)'"
                ))
                continue
            }
            if prototype.kind != .actor {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: actor.id,
                    message: "Prototype '\(actor.prototype)' is \(prototype.kind.rawValue), not an actor"
                ))
            }
            let placement = prototype.placementContract
            if !placement.isAligned(actor.position) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: actor.id,
                    message: "Actor position is off the prototype's \(placement.positionSnapCells)-cell placement grid"
                ))
            }
            if !placement.isRotationAligned(actor.facing) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: actor.id,
                    message: "Actor facing is off the prototype's \(placement.rotationSnapDegrees)-degree increment"
                ))
            }
            if !isOnFloor(actor.position, level: level) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: actor.id,
                    message: "Spawns outside every floor rect"
                ))
            }
        }

        let knownIDs = Set(level.props.map(\.id))
            .union(level.actors.map(\.id))
            .union(level.markers.map(\.id))
        for link in level.security {
            if !knownIDs.contains(link.source) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: link.source,
                    message: "Security link source does not exist in this level"
                ))
            }
            if !knownIDs.contains(link.target) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: link.target,
                    message: "Security link target does not exist in this level"
                ))
            }
        }

        issues.append(contentsOf: reservedBandIssues(level, catalog: catalog))
        issues.append(contentsOf: reachabilityIssues(level, catalog: catalog, grid: grid))

        return issues
    }

    /// Reports mission-critical objects placed where the collapsed Plan Deck
    /// will cover them.
    ///
    /// Checked in level data rather than at runtime because it is a design
    /// reservation: the world still renders there, so the deck can sit on top
    /// without the camera having to give up any of the display.
    public static func reservedBandIssues(
        _ level: LevelBlueprint,
        catalog: PropCatalog
    ) -> [LevelIssue] {
        guard level.reservedNearBand > 0 else { return [] }

        let playable = level.playableBounds
        var issues: [LevelIssue] = []

        func check(id: String, position: CellPoint, noun: String) {
            guard position.y > playable.maxY else { return }
            issues.append(LevelIssue(
                severity: .warning,
                subject: id,
                message: String(
                    format: "%@ sits %.2f cells into the strip reserved for the Plan Deck",
                    noun,
                    position.y - playable.maxY
                )
            ))
        }

        for prop in level.props {
            guard let prototype = catalog[prop.prototype], prototype.kind != .scenery else { continue }
            let isCritical = !prototype.interactions.isEmpty
                || prototype.kind == .security
                || prototype.kind == .loot
                || prototype.kind == .marker
            guard isCritical else { continue }
            check(id: prop.id, position: prop.position, noun: "Interactable '\(prop.prototype)'")
        }

        for marker in level.markers {
            check(id: marker.id, position: marker.position, noun: "Marker '\(marker.kind.rawValue)'")
        }

        for actor in level.actors {
            check(id: actor.id, position: actor.position, noun: "Actor start position")
            for (offset, waypoint) in actor.route.enumerated() {
                check(id: "\(actor.id).route[\(offset)]", position: waypoint, noun: "Patrol waypoint")
            }
        }

        return issues
    }

    /// Walks the level the way an actor would and reports anything cut off.
    ///
    /// Placement mistakes do not look like mistakes in a level file: a safe put
    /// down next to a door reads fine as data, and only turns out to have sealed
    /// the room once someone tries to walk in. Since levels are meant to be
    /// generated, this has to be checked, not eyeballed.
    public static func reachabilityIssues(
        _ level: LevelBlueprint,
        catalog: PropCatalog,
        grid: NavGrid
    ) -> [LevelIssue] {
        guard grid.cellCount > 0 else { return [] }

        let origin = level.marker(.spawn)?.position
            ?? level.actors.first?.position
        guard let origin else { return [] }

        let start = level.metrics.worldPoint(origin)
        guard let startCell = grid.nearestWalkable(to: start, maximumRadius: 1.5) else {
            return [LevelIssue(
                severity: .error,
                subject: level.id,
                message: "Spawn point has no walkable ground within 1.5 m"
            )]
        }

        let reached = floodFill(from: startCell, in: grid)
        var issues: [LevelIssue] = []

        func check(id: String, position: CellPoint, noun: String) {
            let world = level.metrics.worldPoint(position)
            // Reachable means "an actor can stand next to it", so look for a
            // walkable cell within arm's reach rather than under the object.
            guard let cell = grid.nearestWalkable(to: world, maximumRadius: 1.5) else {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: id,
                    message: "\(noun) has no walkable ground within 1.5 m — nobody can stand next to it"
                ))
                return
            }
            if !reached.contains(cell.row * grid.columns + cell.column) {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: id,
                    message: "\(noun) is cut off from the spawn point — check for furniture blocking a doorway"
                ))
            }
        }

        for prop in level.props {
            guard let prototype = catalog[prop.prototype],
                  !prototype.interactions.isEmpty else { continue }
            check(id: prop.id, position: prop.position, noun: "Interactable '\(prop.prototype)'")
        }

        for marker in level.markers where marker.kind != .spawn {
            check(id: marker.id, position: marker.position, noun: "Marker '\(marker.kind.rawValue)'")
        }

        for actor in level.actors {
            check(id: actor.id, position: actor.position, noun: "Actor")
            for (offset, waypoint) in actor.route.enumerated() {
                check(id: "\(actor.id).route[\(offset)]", position: waypoint, noun: "Patrol waypoint")
            }
        }

        return issues
    }

    /// Indices of every cell connected to `start` by four-way movement.
    private static func floodFill(from start: NavGrid.Cell, in grid: NavGrid) -> Set<Int> {
        var seen: Set<Int> = []
        var stack = [start]
        seen.insert(start.row * grid.columns + start.column)

        while let cell = stack.popLast() {
            let neighbours = [
                NavGrid.Cell(column: cell.column + 1, row: cell.row),
                NavGrid.Cell(column: cell.column - 1, row: cell.row),
                NavGrid.Cell(column: cell.column, row: cell.row + 1),
                NavGrid.Cell(column: cell.column, row: cell.row - 1)
            ]
            for neighbour in neighbours where grid.isWalkable(neighbour) {
                let index = neighbour.row * grid.columns + neighbour.column
                if seen.insert(index).inserted {
                    stack.append(neighbour)
                }
            }
        }

        return seen
    }

    public static func isOnFloor(_ point: CellPoint, level: LevelBlueprint) -> Bool {
        level.floors.contains { $0.rect.contains(point) }
    }

    private static func duplicateIDIssues(in level: LevelBlueprint) -> [LevelIssue] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for id in level.floors.map(\.id) + level.walls.map(\.id) + level.props.map(\.id)
            + level.actors.map(\.id) + level.markers.map(\.id) {
            if !seen.insert(id).inserted {
                duplicates.append(id)
            }
        }
        return duplicates.map {
            LevelIssue(severity: .error, subject: $0, message: "Duplicate entity ID")
        }
    }

    private static func consecutivePairs<T>(_ items: [T]) -> [(T, T)] {
        guard items.count > 1 else { return [] }
        return (0..<(items.count - 1)).map { (items[$0], items[$0 + 1]) }
    }
}

extension Array where Element == LevelIssue {
    public var errors: [LevelIssue] { filter { $0.severity == .error } }
    public var hasErrors: Bool { contains { $0.severity == .error } }
}
