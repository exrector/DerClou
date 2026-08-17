import Foundation

/// Levels shipped with the game.
///
/// Levels are values, not code paths. Nothing here may contain behaviour — if a
/// level needs something new, it belongs in `PropCatalog` or in a system.
public enum LevelLibrary {
    public static var all: [LevelBlueprint] {
        [.office01]
    }

    public static func level(id: String) -> LevelBlueprint? {
        all.first { $0.id == id }
    }
}

extension LevelBlueprint {
    /// Engineering test location: two rooms separated by a solid wall, joined
    /// only through a corridor. Any route between the rooms has to go around,
    /// which is exactly what proves navigation-mesh pathfinding.
    ///
    /// Layout, in cells (x to the right, y into the screen):
    ///
    ///     (0,0)                                   (14,0)
    ///       +-------------------+-------------------+
    ///       |     office A      |     office B      |
    ///       |                   |                   |
    ///       +----[door]---------+---------[door]----+   y = 6
    ///       |            corridor                   |
    ///       +---------------------------------------+
    ///     (0,10)                                  (14,10)
    public static var office01: LevelBlueprint {
        LevelBlueprint(
            id: "office01",
            title: "Office Floor",
            metrics: .standard,
            floors: [
                FloorSpec(id: "office01.floor.main", rect: CellRect(x: 0, y: 0, width: 14, depth: 10))
            ],
            walls: [
                WallSpec(id: "office01.wall.north", start: CellPoint(0, 0), end: CellPoint(14, 0)),
                WallSpec(id: "office01.wall.south", start: CellPoint(0, 10), end: CellPoint(14, 10)),
                WallSpec(id: "office01.wall.west", start: CellPoint(0, 0), end: CellPoint(0, 10)),
                WallSpec(id: "office01.wall.east", start: CellPoint(14, 0), end: CellPoint(14, 10)),
                WallSpec(
                    id: "office01.wall.corridor",
                    start: CellPoint(0, 6),
                    end: CellPoint(14, 6),
                    openings: [
                        WallOpening(kind: .doorway, center: 3, width: 1.0),
                        WallOpening(kind: .doorway, center: 10, width: 1.0)
                    ]
                ),
                // No opening: the only way from office A to office B is the corridor.
                WallSpec(id: "office01.wall.divider", start: CellPoint(6, 0), end: CellPoint(6, 6))
            ],
            props: [
                PropSpec(id: "office01.door.a", prototype: "door.single", position: CellPoint(3, 6)),
                PropSpec(
                    id: "office01.door.b",
                    prototype: "door.single",
                    position: CellPoint(10, 6),
                    config: ["locked": .bool(true), "lockDifficulty": .int(2)]
                ),

                PropSpec(id: "office01.desk.a", prototype: "desk.office", position: CellPoint(2.4, 2.0)),
                PropSpec(id: "office01.chair.a", prototype: "chair.office", position: CellPoint(2.4, 3.1), rotation: 180),
                PropSpec(id: "office01.cabinet.a", prototype: "cabinet.filing", position: CellPoint(5.4, 1.2), rotation: 90),
                PropSpec(id: "office01.plant.a", prototype: "plant.potted", position: CellPoint(0.6, 5.2)),

                PropSpec(id: "office01.desk.b", prototype: "desk.office", position: CellPoint(9.2, 2.6), rotation: 90),
                PropSpec(id: "office01.cabinet.b", prototype: "cabinet.filing", position: CellPoint(7.0, 0.9)),
                PropSpec(
                    id: "office01.safe.manager",
                    prototype: "safe.wall",
                    position: CellPoint(13.5, 1.6),
                    rotation: 270,
                    config: ["difficulty": .int(3)]
                ),
                PropSpec(id: "office01.loot.desk", prototype: "loot.cash", position: CellPoint(9.2, 2.0), rotation: 90),

                PropSpec(id: "office01.camera.corridor", prototype: "camera.ceiling", position: CellPoint(7.0, 6.3)),
                PropSpec(id: "office01.panel.corridor", prototype: "panel.security", position: CellPoint(0.25, 7.6), rotation: 90),

                PropSpec(id: "office01.extraction", prototype: "marker.extraction", position: CellPoint(1.2, 9.0))
            ],
            actors: [
                ActorSpec(id: "office01.thief.01", prototype: "actor.thief", position: CellPoint(2.0, 8.6)),
                ActorSpec(
                    id: "office01.guard.01",
                    prototype: "actor.guard",
                    position: CellPoint(12.0, 8.0),
                    facing: 270,
                    route: [
                        CellPoint(12.0, 8.0),
                        CellPoint(4.0, 8.0),
                        CellPoint(4.0, 9.2),
                        CellPoint(12.0, 9.2)
                    ]
                )
            ],
            markers: [
                MarkerSpec(id: "office01.marker.spawn", kind: .spawn, position: CellPoint(2.0, 8.6)),
                MarkerSpec(id: "office01.marker.extraction", kind: .extraction, position: CellPoint(1.2, 9.0))
            ],
            security: [
                SecurityLinkSpec(
                    source: "office01.panel.corridor",
                    target: "office01.camera.corridor",
                    effect: .power
                )
            ]
        )
    }
}
