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
    case inspect
    case search
    case open
    case close
    case unlock
    case lockpick
    case crackSafe
    case hack
    case toggleSwitch
    case takeLoot
    case extract
}

public enum PropMechanic: String, Codable, Sendable, CaseIterable {
    case hingedDoor
    case securityCamera
}

/// Which gameplay rules an actor follows — separate from `PropPrototype.id`
/// (a catalog key) and from `asset`/`ActorSpec.config["appearance"]` (which
/// model renders). Before this existed, `LevelSceneBuilder` decided
/// component wiring by string-comparing `prototype.id` against literals
/// like `"actor.guard"`, so every new look (Guard02, Guard03, ...) needed
/// its own prototype id just to stay recognisable as a guard — appearance
/// and gameplay role were the same string. See `ActorSpec.appearance`(config
/// key `"appearance"`) for how a role now carries more than one look.
public enum ActorRole: String, Codable, Sendable, CaseIterable {
    case thief
    case `guard`
    case civilian
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
    /// Canonical gameplay footprint in meters: width (local x), depth (local z).
    /// `gridFootprint(metrics:)` exposes the same bounds in authoring cells.
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
    /// Default production asset name, resolved in the RealityKit content
    /// bundle. Nil means "render the greybox stand-in for this footprint".
    /// A placed instance can override this per-instance — see
    /// `ActorSpec.appearance`.
    public var asset: String?
    /// Which gameplay rules this actor follows. Nil for every non-actor
    /// `PropKind`. Component wiring in `LevelSceneBuilder` reads this
    /// instead of comparing `id` against string literals, so a new look for
    /// an existing role (another guard model, say) never needs a new
    /// prototype — see `ActorRole`'s own docs for why that used to be true.
    public var actorRole: ActorRole?
    /// Runtime behavior family, independent of prototype ID and appearance.
    public var mechanic: PropMechanic?
    /// Optional authored override for the universal modular placement contract.
    /// Old catalog data decodes as nil and receives the stable default.
    public var placement: PlacementContract?

    public init(
        id: String,
        kind: PropKind,
        footprint: CellSize,
        height: Double,
        surface: SurfaceKey,
        blocksMovement: Bool = true,
        interactions: [InteractionKind] = [],
        defaults: [String: LevelValue] = [:],
        asset: String? = nil,
        actorRole: ActorRole? = nil,
        mechanic: PropMechanic? = nil,
        placement: PlacementContract? = nil
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
        self.actorRole = actorRole
        self.mechanic = mechanic
        self.placement = placement
    }

    /// Resolved config for a placed instance: prototype defaults + overrides.
    public func resolvedConfig(overrides: [String: LevelValue]) -> [String: LevelValue] {
        defaults.merging(overrides) { _, override in override }
    }

    public var placementContract: PlacementContract {
        placement ?? PlacementContract(
            rotationSnapDegrees: kind == .architecture ? 90 : 15,
            pivot: mechanic == .hingedDoor ? .hingeLeft : .bottomCenter,
            scalePolicy: kind == .actor ? .preserveMeters : .uniformFit
        )
    }

    public func gridFootprint(metrics: LevelMetrics) -> CellSize {
        CellSize(
            width: metrics.cells(fromMeters: footprint.width),
            depth: metrics.cells(fromMeters: footprint.depth)
        )
    }

    public var canonicalBounds: MetricSize3D {
        MetricSize3D(width: footprint.width, height: height, depth: footprint.depth)
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
            interactions: [.open, .close, .unlock, .lockpick],
            defaults: [
                "locked": .bool(false), "lockDifficulty": .int(1),
                "open": .bool(false),
                "hingeSide": .string(DoorHingeSide.left.rawValue),
                "openAngle": .double(90),
                "openDuration": .double(1.0), "closeDuration": .double(1.0),
                "unlockDuration": .double(0.8),
                "lockpickDuration": .double(4.0)
            ],
            mechanic: .hingedDoor
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
            surface: .wood,
            interactions: [.search],
            defaults: ["searchDuration": .double(3.0), "searched": .bool(false)]
        ),
        PropPrototype(
            id: "chair.office",
            kind: .furniture,
            footprint: CellSize(width: 0.55, depth: 0.55),
            height: 1.0,
            surface: .fabric,
            interactions: [.inspect],
            defaults: ["inspectDuration": .double(1.0), "inspected": .bool(false)]
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
                "visionSource": .string(VisionSourceKind.securityCamera.rawValue),
                "range": .double(VisionProfiles.securityCamera.range),
                "fieldOfView": .double(VisionProfiles.securityCamera.fieldOfViewDegrees),
                "scanArc": .double(90.0),
                "scanPeriod": .double(8.0),
                "mountHeight": .double(2.4)
            ],
            mechanic: .securityCamera
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
        //
        // One prototype per gameplay role, not per look: which model renders
        // is `asset` here (the role's default) or `ActorSpec.config
        // ["appearance"]` per placement (an override — see LevelSceneBuilder
        // and CharacterLab for the pattern). Guard01/02/03 and future
        // civilians are all the same `actor.guard`/`actor.civilian` role
        // wearing a different model; they used to each need their own
        // prototype id just to be recognised as a guard at all, which is
        // exactly the coupling `ActorRole` exists to remove.
        PropPrototype(
            id: "actor.thief",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.75,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.4)],
            asset: "thief",
            actorRole: .thief
        ),
        PropPrototype(
            id: "actor.guard",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.8,
            surface: .fabric,
            blocksMovement: false,
            defaults: [
                "walkSpeed": .double(1.2),
                "turnSpeed": .double(180.0),
                "visionSource": .string(VisionSourceKind.guardActor.rawValue),
                "range": .double(VisionProfiles.guardActor.range),
                "fieldOfView": .double(VisionProfiles.guardActor.fieldOfViewDegrees)
            ],
            asset: "guard01",
            actorRole: .guard
        ),
        PropPrototype(
            id: "actor.civilian",
            kind: .actor,
            footprint: CellSize(width: 0.6, depth: 0.6),
            height: 1.7,
            surface: .fabric,
            blocksMovement: false,
            defaults: ["walkSpeed": .double(1.1)],
            asset: "civilian01",
            actorRole: .civilian
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
