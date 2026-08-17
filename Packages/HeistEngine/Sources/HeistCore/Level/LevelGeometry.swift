import Foundation

/// An axis-aligned box with a yaw, expressed in world meters.
///
/// This is the single hand-off format between the pure level model and anything
/// that renders or bakes it. Keeping it free of RealityKit means the whole
/// building can be built and asserted in unit tests with no simulator.
public struct WorldBox: Sendable, Equatable {
    /// Center of the box, in meters.
    public var center: WorldPoint
    public var width: Double
    public var height: Double
    public var depth: Double
    /// Yaw around +Y, in degrees.
    public var yaw: Double
    public var surface: SurfaceKey
    /// ID of the blueprint element this box came from.
    public var sourceID: String

    public init(
        center: WorldPoint,
        width: Double,
        height: Double,
        depth: Double,
        yaw: Double = 0,
        surface: SurfaceKey,
        sourceID: String
    ) {
        self.center = center
        self.width = width
        self.height = height
        self.depth = depth
        self.yaw = yaw
        self.surface = surface
        self.sourceID = sourceID
    }
}

/// A prototype instanced into world space, with its config already resolved.
public struct PlacedProp: Sendable, Equatable, Identifiable {
    public var id: String
    public var prototype: PropPrototype
    public var box: WorldBox
    public var config: [String: LevelValue]

    public init(id: String, prototype: PropPrototype, box: WorldBox, config: [String: LevelValue]) {
        self.id = id
        self.prototype = prototype
        self.box = box
        self.config = config
    }

    public var walkSpeed: Double {
        config["walkSpeed"]?.doubleValue ?? 1.4
    }
}

/// Everything needed to build the scene and bake navigation, in world meters.
public struct LevelGeometry: Sendable, Equatable {
    public var floors: [WorldBox]
    public var walls: [WorldBox]
    public var props: [PlacedProp]
    public var actors: [PlacedProp]
    public var markers: [MarkerSpec]

    /// Boxes the navigation baker must treat as walkable ground.
    public var walkableBoxes: [WorldBox] { floors }

    /// Boxes the navigation baker must treat as obstacles.
    public var obstacleBoxes: [WorldBox] {
        walls + props.filter { $0.prototype.blocksMovement }.map(\.box)
    }
}

/// Turns a blueprint into world-space boxes.
///
/// Pure and deterministic: same blueprint in, same geometry out, in a stable
/// order. Level generation depends on that, and so does the determinism
/// requirement for plan replay.
public enum LevelGeometryBuilder {
    public static func build(_ level: LevelBlueprint, catalog: PropCatalog = .standard) -> LevelGeometry {
        let metrics = level.metrics

        let floors = level.floors.map { floor -> WorldBox in
            let center = metrics.worldPoint(floor.rect.center)
            return WorldBox(
                center: WorldPoint(
                    x: center.x,
                    y: floor.elevation - metrics.floorThickness / 2,
                    z: center.z
                ),
                width: metrics.meters(fromCells: floor.rect.size.width),
                height: metrics.floorThickness,
                depth: metrics.meters(fromCells: floor.rect.size.depth),
                surface: surfaceKey(for: floor.material, fallback: .concrete),
                sourceID: floor.id
            )
        }

        let walls = level.walls.flatMap { wall -> [WorldBox] in
            let yaw = wallYaw(wall)
            let surface = surfaceKey(for: wall.material, fallback: .plaster)
            return wall.segments(metrics: metrics).enumerated().map { index, segment in
                let midpoint = wall.point(atDistance: (segment.span.lowerBound + segment.span.upperBound) / 2)
                let world = metrics.worldPoint(midpoint)
                return WorldBox(
                    center: WorldPoint(
                        x: world.x,
                        y: (segment.bottom + segment.top) / 2,
                        z: world.z
                    ),
                    width: metrics.meters(fromCells: segment.length),
                    height: segment.height,
                    depth: metrics.wallThickness,
                    yaw: yaw,
                    surface: surface,
                    sourceID: "\(wall.id).\(index)"
                )
            }
        }

        let props = level.props.compactMap { spec -> PlacedProp? in
            guard let prototype = catalog[spec.prototype] else { return nil }
            return place(spec: spec, prototype: prototype, metrics: metrics)
        }

        let actors = level.actors.compactMap { spec -> PlacedProp? in
            guard let prototype = catalog[spec.prototype] else { return nil }
            let world = metrics.worldPoint(spec.position)
            let box = WorldBox(
                center: WorldPoint(x: world.x, y: prototype.height / 2, z: world.z),
                width: prototype.footprint.width,
                height: prototype.height,
                depth: prototype.footprint.depth,
                yaw: spec.facing,
                surface: prototype.surface,
                sourceID: spec.id
            )
            return PlacedProp(
                id: spec.id,
                prototype: prototype,
                box: box,
                config: prototype.resolvedConfig(overrides: spec.config)
            )
        }

        return LevelGeometry(
            floors: floors,
            walls: walls,
            props: props,
            actors: actors,
            markers: level.markers
        )
    }

    private static func place(
        spec: PropSpec,
        prototype: PropPrototype,
        metrics: LevelMetrics
    ) -> PlacedProp {
        let config = prototype.resolvedConfig(overrides: spec.config)
        let world = metrics.worldPoint(spec.position)
        // Wall-mounted props declare their own height; everything else sits on
        // the floor. One rule, no per-prop special cases.
        let baseY = config["mountHeight"]?.doubleValue ?? 0
        let box = WorldBox(
            center: WorldPoint(x: world.x, y: baseY + prototype.height / 2, z: world.z),
            width: prototype.footprint.width,
            height: prototype.height,
            depth: prototype.footprint.depth,
            yaw: spec.rotation,
            surface: prototype.surface,
            sourceID: spec.id
        )
        return PlacedProp(id: spec.id, prototype: prototype, box: box, config: config)
    }

    /// Yaw that aligns a box's local +x with the wall direction.
    private static func wallYaw(_ wall: WallSpec) -> Double {
        let direction = wall.direction
        let radians = atan2(direction.y, direction.x)
        return -radians * 180 / .pi
    }

    private static func surfaceKey(for material: String, fallback: SurfaceKey) -> SurfaceKey {
        // Material strings are namespaced like "floor.concrete"; the last
        // component names the surface family.
        guard let last = material.split(separator: ".").last,
              let key = SurfaceKey(rawValue: String(last)) else {
            return fallback
        }
        return key
    }
}
