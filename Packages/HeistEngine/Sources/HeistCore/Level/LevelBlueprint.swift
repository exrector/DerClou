import Foundation

/// A floor slab. Also defines where the navigation mesh may exist at all.
public struct FloorSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var rect: CellRect
    public var material: String
    /// Elevation of the walking surface, in meters.
    public var elevation: Double

    public init(
        id: String,
        rect: CellRect,
        material: String = "floor.concrete",
        elevation: Double = 0
    ) {
        self.id = id
        self.rect = rect
        self.material = material
        self.elevation = elevation
    }
}

/// An instance of a catalog prototype placed in the level.
///
/// The blueprint says *what* and *where*. It never says *how the thing behaves*
/// — behaviour comes from the prototype in `PropCatalog`, so a new level is data
/// and a new mechanic is one catalog entry plus one system.
public struct PropSpec: Codable, Sendable, Equatable, Identifiable {
    /// Stable logical ID, e.g. `level01.safe.manager`. Used by plans and logs.
    public var id: String
    /// Prototype key resolved against `PropCatalog`.
    public var prototype: String
    public var position: CellPoint
    /// Yaw in degrees, clockwise when seen from above. 0 faces +z.
    public var rotation: Double
    /// Per-instance overrides, e.g. `["locked": .bool(true), "difficulty": .int(3)]`.
    public var config: [String: LevelValue]

    public init(
        id: String,
        prototype: String,
        position: CellPoint,
        rotation: Double = 0,
        config: [String: LevelValue] = [:]
    ) {
        self.id = id
        self.prototype = prototype
        self.position = position
        self.rotation = rotation
        self.config = config
    }
}

/// A character placed in the level.
public struct ActorSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var prototype: String
    public var position: CellPoint
    public var facing: Double
    /// Ordered patrol waypoints. Empty for player-controlled actors.
    public var route: [CellPoint]
    public var config: [String: LevelValue]

    public init(
        id: String,
        prototype: String,
        position: CellPoint,
        facing: Double = 0,
        route: [CellPoint] = [],
        config: [String: LevelValue] = [:]
    ) {
        self.id = id
        self.prototype = prototype
        self.position = position
        self.facing = facing
        self.route = route
        self.config = config
    }
}

/// A non-visual point of interest: spawn, extraction, camera framing anchor.
public struct MarkerSpec: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case spawn
        case extraction
        case cameraFocus
    }

    public var id: String
    public var kind: Kind
    public var position: CellPoint
    public var facing: Double

    public init(id: String, kind: Kind, position: CellPoint, facing: Double = 0) {
        self.id = id
        self.kind = kind
        self.position = position
        self.facing = facing
    }
}

/// A directed link in the security dependency graph, e.g. switch -> camera.
///
/// Present in the schema from day one so levels authored now stay valid once
/// the security system lands; the runtime simply ignores unknown effects.
public struct SecurityLinkSpec: Codable, Sendable, Equatable {
    public enum Effect: String, Codable, Sendable {
        case power
        case unlock
        case disarm
        case alarmTrigger
    }

    public var source: String
    public var target: String
    public var effect: Effect
    /// For timed effects, in seconds. Nil means latching.
    public var duration: Double?

    public init(source: String, target: String, effect: Effect, duration: Double? = nil) {
        self.source = source
        self.target = target
        self.effect = effect
        self.duration = duration
    }
}

/// The complete, serialisable definition of one level.
///
/// A level is data. Adding a level must not require new Swift code — if it does,
/// the missing piece belongs in `PropCatalog` or in a system, not here.
public struct LevelBlueprint: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var metrics: LevelMetrics
    public var floors: [FloorSpec]
    public var walls: [WallSpec]
    public var props: [PropSpec]
    public var actors: [ActorSpec]
    public var markers: [MarkerSpec]
    public var security: [SecurityLinkSpec]
    /// Depth of the strip along the near edge that the collapsed Plan Deck sits
    /// over, in cells.
    ///
    /// The world keeps rendering underneath it — the game stays fullscreen — but
    /// nothing the player must see or tap belongs there. This is a level-design
    /// reservation, not a smaller camera: shrinking the viewport whenever a panel
    /// appears would undo the fullscreen framing.
    public var reservedNearBand: Double

    public init(
        id: String,
        title: String,
        metrics: LevelMetrics = .standard,
        floors: [FloorSpec] = [],
        walls: [WallSpec] = [],
        props: [PropSpec] = [],
        actors: [ActorSpec] = [],
        markers: [MarkerSpec] = [],
        security: [SecurityLinkSpec] = [],
        reservedNearBand: Double = 1.5
    ) {
        self.id = id
        self.title = title
        self.metrics = metrics
        self.floors = floors
        self.walls = walls
        self.props = props
        self.actors = actors
        self.markers = markers
        self.security = security
        self.reservedNearBand = reservedNearBand
    }

    /// Bounding rectangle of all floors, in cells.
    public var bounds: CellRect {
        guard let first = floors.first else { return CellRect(x: 0, y: 0, width: 0, depth: 0) }
        var minX = first.rect.minX
        var maxX = first.rect.maxX
        var minY = first.rect.minY
        var maxY = first.rect.maxY
        for floor in floors.dropFirst() {
            minX = min(minX, floor.rect.minX)
            maxX = max(maxX, floor.rect.maxX)
            minY = min(minY, floor.rect.minY)
            maxY = max(maxY, floor.rect.maxY)
        }
        return CellRect(x: minX, y: minY, width: maxX - minX, depth: maxY - minY)
    }

    public func marker(_ kind: MarkerSpec.Kind) -> MarkerSpec? {
        markers.first { $0.kind == kind }
    }

    /// The area mission-critical objects may occupy: everything but the strip
    /// the collapsed Plan Deck covers.
    public var playableBounds: CellRect {
        let full = bounds
        return CellRect(
            x: full.minX,
            y: full.minY,
            width: full.size.width,
            depth: max(0, full.size.depth - reservedNearBand)
        )
    }
}
