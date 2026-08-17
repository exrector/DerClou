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
    public static func validate(_ level: LevelBlueprint, catalog: PropCatalog) -> [LevelIssue] {
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
            guard catalog[prop.prototype] != nil else {
                issues.append(LevelIssue(
                    severity: .error,
                    subject: prop.id,
                    message: "Unknown prototype '\(prop.prototype)'"
                ))
                continue
            }
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

        return issues
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
