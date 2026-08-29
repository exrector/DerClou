namespace DerClou.Gameplay.Level
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
    using DerClou.Core.Time;
    using System.Collections.Generic;
    using UnityEngine;

    /// <summary>
    /// Creates the first tutorial level programmatically.
    /// In production, load from JSON/ScriptableObject.
    /// </summary>
    public class Level01Builder : MonoBehaviour
    {
        [Header("Output")]
        public LevelBlueprint blueprint;

        [ContextMenu("Generate Level 01")]
        public void Generate()
        {
            blueprint = new LevelBlueprint
            {
                id = "level01",
                metrics = new LevelMetrics { cellSize = 0.5f, wallHeight = 2.5f }
            };

            // ─── Floors ───
            blueprint.floors.Add(new WorldBox
            {
                sourceID = "floor_main",
                centerX = 0, centerZ = 0,
                width = 30, depth = 20,
                height = 0.2f,
                yaw = 0
            });

            // ─── Walls (rectangular building) ───
            float hw = 15f, hd = 10f, wh = 2.5f;
            // North wall
            blueprint.walls.Add(new WorldBox { sourceID = "wall_n", centerX = 0, centerZ = -hd, width = 30, depth = 0.3f, height = wh, yaw = 0 });
            // South wall
            blueprint.walls.Add(new WorldBox { sourceID = "wall_s", centerX = 0, centerZ = hd, width = 30, depth = 0.3f, height = wh, yaw = 0 });
            // West wall
            blueprint.walls.Add(new WorldBox { sourceID = "wall_w", centerX = -hw, centerZ = 0, width = 0.3f, depth = 20, height = wh, yaw = 0 });
            // East wall
            blueprint.walls.Add(new WorldBox { sourceID = "wall_e", centerX = hw, centerZ = 0, width = 0.3f, depth = 20, height = wh, yaw = 0 });
            // Internal divider, split around the actual portal. A door is a
            // gap in planar topology, never a mesh laid across a solid wall.
            blueprint.walls.Add(new WorldBox { sourceID = "wall_div.north", centerX = 0, centerZ = -5.4f, width = 0.3f, depth = 8.8f, height = wh, yaw = 0 });
            blueprint.walls.Add(new WorldBox { sourceID = "wall_div.south", centerX = 0, centerZ = 5.4f, width = 0.3f, depth = 8.8f, height = wh, yaw = 0 });

            // ─── Door in divider ───
            blueprint.props.Add(new PlacedProp
            {
                id = "door_div",
                prototypeId = "door.single",
                box = new WorldBox { centerX = 0, centerZ = 0, width = 0.12f, depth = 1.6f, height = 2.1f, yaw = 0 },
                yaw = 0,
                config = new Dictionary<string, LevelValue>
                {
                    { "locked", LevelValue.Bool(false) },
                    { "lockDifficulty", LevelValue.Int(1) },
                    { "hingeSide", LevelValue.String("Left") }
                }
            });

            blueprint.rooms.Add(new RoomSpec
            {
                id = "room.west",
                bounds = new WorldBox { sourceID = "room.west", centerX = -7.5f, centerZ = 0f, width = 14.7f, depth = 19.7f }
            });
            blueprint.rooms.Add(new RoomSpec
            {
                id = "room.east",
                bounds = new WorldBox { sourceID = "room.east", centerX = 7.5f, centerZ = 0f, width = 14.7f, depth = 19.7f }
            });
            blueprint.portals.Add(new PortalSpec
            {
                id = "portal.divider",
                roomAId = "room.west",
                roomBId = "room.east",
                doorId = "door_div",
                position = new WorldPoint(0f, 0f, 0f),
                width = 1.6f,
                baseCost = 1f
            });

            // ─── Security Camera ───
            blueprint.props.Add(new PlacedProp
            {
                id = "cam_hall",
                prototypeId = "camera.wall",
                box = new WorldBox { centerX = -5, centerZ = -5, width = 0.5f, depth = 0.5f, height = 0.25f, yaw = 0 },
                yaw = 0,
                config = new Dictionary<string, LevelValue>
                {
                    { "powered", LevelValue.Bool(true) },
                    { "scanArc", LevelValue.Float(120f) },
                    { "scanPeriod", LevelValue.Float(10f) },
                    { "mountWallId", LevelValue.String("wall_n") }
                }
            });

            // ─── Security Panel ───
            blueprint.props.Add(new PlacedProp
            {
                id = "panel_main",
                prototypeId = "panel.security",
                box = new WorldBox { centerX = 8, centerZ = -8, width = 0.35f, depth = 0.12f, height = 0.45f, yaw = 0 },
                yaw = 0,
                config = new Dictionary<string, LevelValue>
                {
                    { "difficulty", LevelValue.Int(2) },
                    { "hackDuration", LevelValue.Float(6f) },
                    // Which security device this panel gates — the minimum
                    // data-driven version of the `docs/CLAUDE.md` "security
                    // dependency" grammar (Switch A -> Camera 1 power),
                    // without building the full dependency-graph engine that
                    // grammar eventually calls for.
                    { "controlsCameraId", LevelValue.String("cam_hall") }
                }
            });

            // ─── Safe ───
            blueprint.props.Add(new PlacedProp
            {
                id = "safe_office",
                prototypeId = "safe.wall",
                box = new WorldBox { centerX = 10, centerZ = 5, width = 0.6f, depth = 0.5f, height = 0.6f, yaw = 0 },
                yaw = 0,
                config = new Dictionary<string, LevelValue>
                {
                    { "locked", LevelValue.Bool(true) },
                    { "difficulty", LevelValue.Int(3) },
                    { "crackSafeDuration", LevelValue.Float(20f) }
                }
            });

            // ─── Loot ───
            blueprint.props.Add(new PlacedProp
            {
                id = "loot_cash1",
                prototypeId = "loot.cash",
                box = new WorldBox { centerX = 10, centerZ = 6, width = 0.25f, depth = 0.15f, height = 0.1f, yaw = 0 },
                yaw = 0,
                config = new Dictionary<string, LevelValue>
                {
                    { "requiresSafeId", LevelValue.String("safe_office") }
                }
            });

            // ─── Extraction ───
            blueprint.props.Add(new PlacedProp
            {
                id = "exit_main",
                prototypeId = "marker.extraction",
                box = new WorldBox { centerX = -14, centerZ = 0, width = 1f, depth = 1f, height = 0.02f, yaw = 0 },
                yaw = 0
            });

            // ─── Actors ───
            // Thief (player)
            blueprint.actors.Add(new ActorSpec
            {
                id = "thief1",
                prototypeId = "actor.thief",
                position = new CellPoint(-12, -8),
                yaw = 45f
            });

            // Guard 1 (patrol) — small loop in the NE part of the east room.
            // No route data existed anywhere in this scaffold before this —
            // `GuardPatrolSystem` had nothing to register, so "the guard
            // patrols" was not actually true yet.
            blueprint.actors.Add(new ActorSpec
            {
                id = "guard1",
                prototypeId = "actor.guard",
                position = new CellPoint(5, -5),
                yaw = 180f,
                route = new List<CellPoint>
                {
                    new CellPoint(5, -5), new CellPoint(13, -5),
                    new CellPoint(13, -1), new CellPoint(5, -1)
                },
                config = new Dictionary<string, LevelValue>
                {
                    // U4 proves one complete watcher end-to-end before
                    // multiplying the system across every guard.
                    { "visionEnabled", LevelValue.Bool(true) },
                    { "visionRange", LevelValue.Float(VisionProfiles.guardActor.range) },
                    { "visionFov", LevelValue.Float(VisionProfiles.guardActor.fieldOfViewDegrees) }
                }
            });

            // Guard 2 (patrol) — small loop in the SE part of the east room.
            blueprint.actors.Add(new ActorSpec
            {
                id = "guard2",
                prototypeId = "actor.guard",
                position = new CellPoint(10, 5),
                yaw = -90f,
                route = new List<CellPoint>
                {
                    new CellPoint(2, 1), new CellPoint(13, 1),
                    new CellPoint(13, 8), new CellPoint(2, 8)
                },
                config = new Dictionary<string, LevelValue>()
            });

            // Guard 3 (with flashlight!) — the long diagonal, most likely to
            // cross paths with the other two.
            blueprint.actors.Add(new ActorSpec
            {
                id = "guard3",
                prototypeId = "actor.guard",
                position = new CellPoint(11, 5),
                yaw = 0f,
                route = new List<CellPoint>
                {
                    new CellPoint(2, -8), new CellPoint(13, -8),
                    new CellPoint(13, 8), new CellPoint(2, 8)
                },
                config = new Dictionary<string, LevelValue>()
            });

            Debug.Log($"Level01 generated: {blueprint.floors.Count} floors, {blueprint.walls.Count} walls, {blueprint.props.Count} props, {blueprint.actors.Count} actors");
        }

        private void OnValidate()
        {
            if (blueprint == null) Generate();
        }
    }
}
