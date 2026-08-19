import Foundation

/// Surface family. The greybox kit renders these procedurally today; the art kit
/// will map the same keys onto authored PBR materials later. Levels never name a
/// texture file, only a surface family.
public enum SurfaceKey: String, Codable, Sendable, CaseIterable {
    case concrete
    case plaster
    case wood
    case metal
    case darkMetal
    case glass
    case fabric
    case emissive
}

/// What a prop can be asked to do. This is the vocabulary levels are built from:
/// a level places prototypes, and the prototype declares its verbs.
public enum InteractionKind: String, Codable, Sendable, CaseIterable {
    case open
    case lockpick
    case crackSafe
    case hack
    case toggleSwitch
    case takeLoot
    case extract
}

/// Broad category, used for selection rules, sorting and debug colouring.
public enum PropKind: String, Codable, Sendable, CaseIterable {
    /// Exterior dressing: trees, hedges, neighbouring walls. Lives outside the
    /// building, never on the playable floor, and is exempt from the floor and
    /// safe-area checks precisely because it is what fills the screen edges.
    case scenery
    case architecture
    case furniture
    case security
    case container
    case loot
    case actor
    case marker
}

/// A reusable object definition.
///
/// One prototype is authored once and instanced many times across levels, in any
/// rotation. Swapping `asset` from nil (greybox) to a USDZ name is the only edit
/// needed to move a prototype from placeholder to production art, because the
/// footprint is already final.
public struct PropPrototype: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: PropKind
    /// Footprint in meters: width (local x), depth (local z).
    public var footprint: CellSize
    /// Height in meters.
    public var height: Double
    public var surface: SurfaceKey
    /// Whether the prop is baked into the navigation mesh as an obstacle.
    public var blocksMovement: Bool
    /// Verbs this prototype supports.
    public var interactions: [InteractionKind]
    /// Default config, overridden per instance by `PropSpec.config`.
    public var defaults: [String: LevelValue]
    /// Production asset name, resolved in the RealityKit content bundle.
    /// Nil means "render the greybox stand-in for this footprint".
    public var asset: String?

    public init(
        id: String,
        kind: PropKind,
        footprint: CellSize,
        height: Double,
        surface: SurfaceKey,
        blocksMovement: Bool = true,
        interactions: [InteractionKind] = [],
        defaults: [String: LevelValue] = [:],
        asset: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.footprint = footprint
        self.height = height
        self.surface = surface
        self.blocksMovement = blocksMovement
        self.interactions = interactions
        self.defaults = defaults
        self.asset = asset
    }

    /// Resolved config for a placed instance: prototype defaults + overrides.
    public func resolvedConfig(overrides: [String: LevelValue]) -> [String: LevelValue] {
        defaults.merging(overrides) { _, override in override }
    }
}

/// The set of prototypes a level may reference.
public struct PropCatalog: Codable, Sendable, Equatable {
    public private(set) var prototypes: [String: PropPrototype]

    public init(prototypes: [PropPrototype]) {
        self.prototypes = Dictionary(uniqueKeysWithValues: prototypes.map { ($0.id, $0) })
    }

    public subscript(id: String) -> PropPrototype? {
        prototypes[id]
    }

    public var ids: [String] {
        prototypes.keys.sorted()
    }
}

extension PropCatalog {
    /// The starter kit: enough vocabulary for the first playable location, with
    /// real-world dimensions so the art pass is a straight swap.
    public static let standard = PropCatalog(prototypes: [
        // Architecture
        PropPrototype(
            id: "door.single",
            kind: .architecture,
            footprint: CellSize(width: 0.9, depth: 0.06),
            height: 2.1,
            surface: .wood,
            blocksMovement: false,
            interactions: [.open, .lockpick],
            defaults: [
                "locked": .bool(false), "lockDifficulty": .int(1),
                "openDuration": .double(1.0), "lockpickDuration": .double(4.0)
            ]
        ),

        // Exterior scenery — what the display edges are filled with
        PropPrototype(
            id: "tree.large",
            kind: .scenery,
            footprint: CellSize(width: 2.4, depth: 2.4),
            height: 5.5,
            surface: .fabric
        ),
        PropPrototype(
            id: "tree.small",
            kind: .scenery,
            footprint: CellSize(width: 1.6, depth: 1.6),
            height: 3.4,
            surface: .fabric
        ),
        PropPrototype(
            id: "hedge.block",
            kind: .scenery,
            footprint: CellSize(width: 3.0, depth: 1.0),
            height: 1.1,
            surface: .fabric
        ),
        /// A slab of a neighbouring building. Placed in right-angled runs, these
        /// read as the street the target sits on.
        PropPrototype(
            id: "building.neighbour",
            kind: .scenery,
            footprint: CellSize(width: 4.0, depth: 3.0),
            height: 4.5,
            surface: .concrete
        ),

        // Furniture
        PropPrototype(
            id: "desk.office",
            kind: .furniture,
            footprint: CellSize(width: 1.6, depth: 0.8),
            height: 0.75,
            surface: .wood
        ),
        PropPrototype(
            id: "chair.office",
            kind: .furniture,
            footprint: CellSize(width: 0.55, depth: 0.55),
            height: 1.0,
            surface: .fabric
        ),
        PropPrototype(
            id: "cabinet.filing",
            kind: .furniture,
            footprint: CellSize(width: 0.9, depth: 0.45),
            height: 1.35,
            surface: .metal,
            interactions: [.open, .takeLoot]
        ),
        PropPrototype(
            id: "crate.storage",
            kind: .container,
            footprint: CellSize(width: 1.0, depth: 0.8),
            height: 0.9,
            surface: .wood,
            interactions: [.open, .takeLoot]
        ),
        PropPrototype(
            id: "plant.potted",
            kind: .furniture,
            footprint: CellSize(width: 0.5, depth: 0.5),
            height: 1.2,
            surface: .fabric
        ),

        // Security
        PropPrototype(
            id: "camera.ceiling",
            kind: .security,
            footprint: CellSize(width: 0.25, depth: 0.35),
            height: 0.25,
            surface: .darkMetal,
            blocksMovement: false,
            defaults: [
                "powered": .bool(true),
                "range": .double(6.0),
                "fieldOfView": .double(60.0),
                "scanArc": .double(90.0),
                "scanPeriod": .double(8.0),
                "mountHeight": .double(2.4)
            ]
        ),
        PropPrototype(
            id: "panel.security",
            kind: .security,
            footprint: CellSize(width: 0.35, depth: 0.12),
            height: 0.45,
            surface: .darkMetal,
            blocksMovement: false,
            interactions: [.hack, .toggleSwitch],
            defaults: [
                "difficulty": .int(2), "mountHeight": .double(1.3),
                "hackDuration": .double(6.0), "toggleSwitchDuration": .double(0.5)
            ]
        ),

        // Containers and loot
        PropPrototype(
            id: "safe.wall",
            kind: .container,
            footprint: CellSize(width: 0.6, depth: 0.5),
            height: 0.6,
            surface: .darkMetal,
            interactions: [.crackSafe, .takeLoot],
            defaults: ["locked": .bool(true), "difficulty": .int(3), "crackSafeDuration": .double(20.0)]
        ),
        PropPrototype(
            id: "loot.cash",
            kind: .loot,
            footprint: CellSize(width: 0.25, depth: 0.15),
            height: 0.1,
            surface: .fabric,
            blocksMovement: false,
            interactions: [.takeLoot],
            defaults: ["value": .int(2500), "weight": .double(1.5)]
        ),

        // Actors
        PropPrototype(
            id: "actor.thief",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.75,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.4)],
            asset: "thief"
        ),
        PropPrototype(
            id: "actor.guard",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.8,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.2), "range": .double(9.0), "fieldOfView": .double(100.0)],
            asset: "guard01"
        ),
        // Roster review only for now: same shape as actor.guard, different
        // model, no patrol route wired to them yet — placed standing still
        // in Level01 so all five converted characters can be looked at
        // together. Not a decision that these are permanent gameplay
        // prototypes; merging them behind a single per-instance asset
        // override is the more scalable design once that's needed.
        PropPrototype(
            id: "actor.guard02",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.8,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.2), "range": .double(9.0), "fieldOfView": .double(100.0)],
            asset: "guard02"
        ),
        PropPrototype(
            id: "actor.guard03",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.8,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.2), "range": .double(9.0), "fieldOfView": .double(100.0)],
            asset: "guard03"
        ),
        PropPrototype(
            id: "actor.civilian01",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.7,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.1)],
            asset: "civilian01"
        ),

        // Markers
        PropPrototype(
            id: "marker.extraction",
            kind: .marker,
            footprint: CellSize(width: 1.0, depth: 1.0),
            height: 0.02,
            surface: .emissive,
            blocksMovement: false,
            interactions: [.extract]
        )
    ])
}
