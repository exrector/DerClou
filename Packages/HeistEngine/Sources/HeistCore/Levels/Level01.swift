import Foundation

/// Levels shipped with the game.
///
/// Levels are values, not code paths. Nothing here may contain behaviour — if a
/// level needs something new, it belongs in `PropCatalog` or in a system.
public enum LevelLibrary {
    public static var all: [LevelBlueprint] {
        [.office01, .characterLab]
    }

    public static func level(id: String) -> LevelBlueprint? {
        all.first { $0.id == id }
    }
}

extension LevelBlueprint {
    /// Engineering test location: three rooms off a single corridor.
    ///
    /// Proportioned so the floor fills a landscape phone exactly: its width spans
    /// the display, and its depth plus the wall height leaning into frame fills
    /// the height. The left, right and far walls therefore fall outside the
    /// frame; only the near wall stays in shot, where the camera tilt shows its
    /// thickness. Nothing of the building is cropped and no ground shows at the
    /// edges.
    ///
    /// The shape of the building is a framing decision as much as a design one:
    /// 24 × 11 m is what a 2.17:1 display asks for at a 24° tilt.
    ///
    /// Offices A and B are separated by a solid wall, as are B and the store
    /// room, so every route between rooms has to go around through the corridor.
    /// That is what makes navigation-mesh pathfinding observable.
    ///
    /// Layout, in cells (x to the right, y into the screen):
    ///
    ///     (0,0)                                                   (24,0)
    ///       +-------------+---------------+-------------------------+
    ///       |  office A   |   office B    |       store room        |
    ///       |             |               |                         |
    ///       +---[door]----+-----[door]----+--------[door]-----------+  y = 6
    ///       |                    corridor                           |
    ///       +-------------------------------------------------------+
    ///     (0,11)                                                  (24,11)
    public static var office01: LevelBlueprint {
        LevelBlueprint(
            id: "office01",
            title: "Office Floor",
            metrics: .standard,
            floors: [
                FloorSpec(id: "office01.floor.main", rect: CellRect(x: 0, y: 0, width: 24, depth: 11))
            ],
            walls: [
                WallSpec(id: "office01.wall.north", start: CellPoint(0, 0), end: CellPoint(24, 0)),
                WallSpec(id: "office01.wall.south", start: CellPoint(0, 11), end: CellPoint(24, 11)),
                WallSpec(id: "office01.wall.west", start: CellPoint(0, 0), end: CellPoint(0, 11)),
                WallSpec(id: "office01.wall.east", start: CellPoint(24, 0), end: CellPoint(24, 11)),
                WallSpec(
                    id: "office01.wall.corridor",
                    start: CellPoint(0, 6),
                    end: CellPoint(24, 6),
                    openings: [
                        WallOpening(kind: .doorway, center: 3, width: 1.2),
                        WallOpening(kind: .doorway, center: 10, width: 1.2),
                        WallOpening(kind: .doorway, center: 18, width: 1.2)
                    ]
                ),
                // No openings: the corridor is the only link between rooms.
                WallSpec(id: "office01.wall.dividerA", start: CellPoint(6, 0), end: CellPoint(6, 6)),
                WallSpec(id: "office01.wall.dividerB", start: CellPoint(14, 0), end: CellPoint(14, 6))
            ],
            props: [
                PropSpec(id: "office01.door.a", prototype: "door.single", position: CellPoint(3, 6)),
                PropSpec(
                    id: "office01.door.b",
                    prototype: "door.single",
                    position: CellPoint(10, 6),
                    config: ["locked": .bool(true), "lockDifficulty": .int(2)]
                ),
                PropSpec(
                    id: "office01.door.store",
                    prototype: "door.single",
                    position: CellPoint(18, 6),
                    config: ["locked": .bool(true), "lockDifficulty": .int(3)]
                ),

                // Office A
                PropSpec(id: "office01.desk.a", prototype: "desk.office", position: CellPoint(2.4, 2.0)),
                PropSpec(id: "office01.chair.a", prototype: "chair.office", position: CellPoint(2.4, 3.1), rotation: 180),
                PropSpec(id: "office01.cabinet.a", prototype: "cabinet.filing", position: CellPoint(5.4, 1.2), rotation: 90),
                PropSpec(id: "office01.plant.a", prototype: "plant.potted", position: CellPoint(0.6, 5.2)),

                // Office B
                PropSpec(id: "office01.desk.b", prototype: "desk.office", position: CellPoint(9.2, 2.6), rotation: 90),
                PropSpec(id: "office01.chair.b", prototype: "chair.office", position: CellPoint(10.4, 2.6), rotation: 270),
                PropSpec(id: "office01.cabinet.b", prototype: "cabinet.filing", position: CellPoint(7.0, 0.9)),
                PropSpec(
                    id: "office01.safe.manager",
                    prototype: "safe.wall",
                    position: CellPoint(13.5, 1.6),
                    rotation: 270,
                    config: ["difficulty": .int(3)]
                ),
                PropSpec(id: "office01.loot.desk", prototype: "loot.cash", position: CellPoint(9.2, 1.8), rotation: 90),

                // Store room
                PropSpec(id: "office01.crate.01", prototype: "crate.storage", position: CellPoint(16.0, 1.2)),
                PropSpec(id: "office01.crate.02", prototype: "crate.storage", position: CellPoint(16.0, 2.6)),
                PropSpec(id: "office01.crate.03", prototype: "crate.storage", position: CellPoint(21.5, 1.2), rotation: 90),
                PropSpec(id: "office01.shelf.01", prototype: "cabinet.filing", position: CellPoint(19.0, 0.5)),
                PropSpec(id: "office01.shelf.02", prototype: "cabinet.filing", position: CellPoint(22.1, 3.5), rotation: 90),
                // Against the far wall, not beside the door: a safe parked in
                // front of a doorway seals the room once the character radius is
                // taken into account.
                PropSpec(
                    id: "office01.safe.store",
                    prototype: "safe.wall",
                    position: CellPoint(22.0, 0.5),
                    config: ["difficulty": .int(4)]
                ),

                // Corridor security
                PropSpec(id: "office01.camera.corridor", prototype: "camera.ceiling", position: CellPoint(7.0, 6.3)),
                PropSpec(id: "office01.camera.store", prototype: "camera.ceiling", position: CellPoint(19.0, 6.3)),
                // On the corridor wall, clear of both the sensor housing at the
                // screen edges and the strip the Plan Deck will cover.
                PropSpec(id: "office01.panel.corridor", prototype: "panel.security", position: CellPoint(4.0, 6.3)),

                PropSpec(id: "office01.extraction", prototype: "marker.extraction", position: CellPoint(2.2, 9.3))
            ],
            actors: [
                ActorSpec(id: "office01.thief.01", prototype: "actor.thief", position: CellPoint(2.0, 8.6)),
                ActorSpec(
                    id: "office01.guard.01",
                    prototype: "actor.guard",
                    position: CellPoint(20.0, 8.0),
                    facing: 270,
                    route: [
                        CellPoint(20.0, 8.0),
                        CellPoint(5.0, 8.0),
                        CellPoint(5.0, 9.2),
                        CellPoint(20.0, 9.2)
                    ]
                )
            ],
            markers: [
                MarkerSpec(id: "office01.marker.spawn", kind: .spawn, position: CellPoint(2.0, 8.6)),
                MarkerSpec(id: "office01.marker.extraction", kind: .extraction, position: CellPoint(2.2, 9.3))
            ],
            security: [
                SecurityLinkSpec(
                    source: "office01.panel.corridor",
                    target: "office01.camera.corridor",
                    effect: .power
                ),
                SecurityLinkSpec(
                    source: "office01.panel.corridor",
                    target: "office01.camera.store",
                    effect: .power
                )
            ]
        )
    }

    /// Not a mission — a bare room for looking at the character roster.
    ///
    /// office01 briefly grew three extra standing-still actors for exactly
    /// this purpose; it broke office01's own validation (they sat inside the
    /// reserved Plan Deck strip) and its actor-count test, and a real mission
    /// has no business carrying roster review as part of its own definition.
    /// This gives the same "look at everyone at once" capability its own
    /// home instead of leaking into a level meant to ship.
    public static var characterLab: LevelBlueprint {
        LevelBlueprint(
            id: "characterlab",
            title: "Character Lab",
            metrics: .standard,
            floors: [
                FloorSpec(id: "characterlab.floor.main", rect: CellRect(x: 0, y: 0, width: 16, depth: 10))
            ],
            walls: [
                WallSpec(id: "characterlab.wall.north", start: CellPoint(0, 0), end: CellPoint(16, 0)),
                WallSpec(id: "characterlab.wall.south", start: CellPoint(0, 10), end: CellPoint(16, 10)),
                WallSpec(id: "characterlab.wall.west", start: CellPoint(0, 0), end: CellPoint(0, 10)),
                WallSpec(id: "characterlab.wall.east", start: CellPoint(16, 0), end: CellPoint(16, 10))
            ],
            props: [
                PropSpec(id: "characterlab.extraction", prototype: "marker.extraction", position: CellPoint(14.0, 5.0))
            ],
            actors: [
                ActorSpec(id: "characterlab.thief", prototype: "actor.thief", position: CellPoint(2.0, 5.0)),
                // Same "actor.guard" role, three different looks — the point
                // of ActorRole/appearance: no per-look prototype needed.
                ActorSpec(id: "characterlab.guard01", prototype: "actor.guard", position: CellPoint(5.0, 5.0)),
                ActorSpec(
                    id: "characterlab.guard02", prototype: "actor.guard", position: CellPoint(8.0, 5.0),
                    config: ["appearance": .string("guard02")]
                ),
                ActorSpec(
                    id: "characterlab.guard03", prototype: "actor.guard", position: CellPoint(11.0, 5.0),
                    config: ["appearance": .string("guard03")]
                ),
                ActorSpec(id: "characterlab.civilian01", prototype: "actor.civilian", position: CellPoint(13.5, 7.0))
            ],
            markers: [
                MarkerSpec(id: "characterlab.marker.spawn", kind: .spawn, position: CellPoint(2.0, 5.0)),
                MarkerSpec(id: "characterlab.marker.extraction", kind: .extraction, position: CellPoint(14.0, 5.0))
            ]
        )
    }
}
