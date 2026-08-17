import Foundation

/// System-reserved edges of the display, in points.
///
/// Always supplied by the OS for the current device and orientation. Never
/// hand-maintained per device: see `docs/DEVELOPMENT_FINDINGS.md`.
public struct ScreenInsets: Sendable, Equatable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = ScreenInsets()

    public var isEmpty: Bool {
        top == 0 && leading == 0 && bottom == 0 && trailing == 0
    }
}

/// The region of the world in which mission-critical objects may live.
///
/// The world renders edge to edge — floors, walls and scenery may pass behind a
/// Dynamic Island or a rounded corner. What may *not* end up there is anything
/// the player has to see, tap or reason about.
///
/// Axis-aligned because the tactical camera only ever tilts, never yaws: a
/// screen-aligned rectangle projects to a world-aligned one.
public struct SafeGameplayBounds: Sendable, Equatable {
    public var minX: Double
    public var maxX: Double
    public var minZ: Double
    public var maxZ: Double

    public init(minX: Double, maxX: Double, minZ: Double, maxZ: Double) {
        self.minX = min(minX, maxX)
        self.maxX = max(minX, maxX)
        self.minZ = min(minZ, maxZ)
        self.maxZ = max(minZ, maxZ)
    }

    public var width: Double { maxX - minX }
    public var depth: Double { maxZ - minZ }

    public func contains(_ point: WorldPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.z >= minZ && point.z <= maxZ
    }

    /// How far outside the bounds a point is, in meters. Zero when inside.
    public func overhang(of point: WorldPoint) -> Double {
        let dx = max(minX - point.x, point.x - maxX, 0)
        let dz = max(minZ - point.z, point.z - maxZ, 0)
        return max(dx, dz)
    }
}

/// Projects the system safe area onto the floor plane.
public enum SafeAreaSolver {
    /// - Parameters:
    ///   - viewportSize: full view size in points.
    ///   - insets: system safe-area insets for the current device and orientation.
    ///   - framing: the framing currently applied to the tactical camera.
    /// - Returns: the world-space region that stays clear of system-reserved
    ///   screen areas, or nil if the viewport is degenerate.
    public static func gameplayBounds(
        viewportSize: (width: Double, height: Double),
        insets: ScreenInsets,
        framing: CameraFraming
    ) -> SafeGameplayBounds? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let left = insets.leading
        let right = viewportSize.width - insets.trailing
        let top = insets.top
        let bottom = viewportSize.height - insets.bottom
        guard right > left, bottom > top else { return nil }

        // Two opposite corners are enough: the projection preserves axis
        // alignment for a camera that only tilts.
        let corners = [
            (x: left, y: top),
            (x: right, y: top),
            (x: left, y: bottom),
            (x: right, y: bottom)
        ]

        var points: [WorldPoint] = []
        for corner in corners {
            guard let ray = ScreenProjection.ray(
                screenPoint: (x: corner.x, y: corner.y),
                viewportSize: viewportSize,
                framing: framing
            ), let hit = ScreenProjection.hit(ray) else { return nil }
            points.append(hit)
        }

        return SafeGameplayBounds(
            minX: points.map(\.x).min() ?? 0,
            maxX: points.map(\.x).max() ?? 0,
            minZ: points.map(\.z).min() ?? 0,
            maxZ: points.map(\.z).max() ?? 0
        )
    }

    /// Reports mission-critical entities that fall outside the safe region.
    ///
    /// Runtime rather than blueprint validation on purpose: the answer depends
    /// on the device and orientation the level is being played on, which a level
    /// file cannot know.
    public static func placementIssues(
        for level: LevelBlueprint,
        catalog: PropCatalog,
        bounds: SafeGameplayBounds
    ) -> [LevelIssue] {
        var issues: [LevelIssue] = []

        func check(id: String, position: CellPoint, noun: String) {
            let world = level.metrics.worldPoint(position)
            guard !bounds.contains(world) else { return }
            issues.append(LevelIssue(
                severity: .warning,
                subject: id,
                message: String(
                    format: "%@ sits %.2f m outside the safe gameplay area — it may be hidden by a system-reserved screen region",
                    noun,
                    bounds.overhang(of: world)
                )
            ))
        }

        for prop in level.props {
            guard let prototype = catalog[prop.prototype] else { continue }
            // Scenery may run off the edge; anything the player must act on
            // may not.
            let isCritical = !prototype.interactions.isEmpty
                || prototype.kind == .security
                || prototype.kind == .loot
                || prototype.kind == .marker
            guard isCritical else { continue }
            check(id: prop.id, position: prop.position, noun: "Interactable '\(prop.prototype)'")
        }

        for actor in level.actors {
            check(id: actor.id, position: actor.position, noun: "Actor start position")
        }

        for marker in level.markers {
            check(id: marker.id, position: marker.position, noun: "Marker '\(marker.kind.rawValue)'")
        }

        return issues
    }
}
