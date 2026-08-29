namespace DerClou.Gameplay.Level
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using UnityEngine;

    /// Two-purpose developer laboratory: a deliberately empty locomotion room
    /// with one four-node patrol, and an environment room for doors/furniture.
    /// The thief is the only dynamic obstacle the owner needs to place.
    public sealed class DeveloperSandboxLevelBuilder : MonoBehaviour
    {
        public LevelBlueprint blueprint;

        /// Keeps the developer sandbox interactive even while production
        /// character assets are absent. The spawned actor uses the neutral
        /// code-generated pawn visual supplied by LevelBuilder.
        public bool spawnThief = true;

        public void Generate()
        {
            blueprint = new LevelBlueprint
            {
                id = "developer_movement_sandbox",
                metrics = new LevelMetrics(0.25f, 2.5f)
            };
            blueprint.floors.Add(Box("floor", 0, 0, 24, 14, 0.2f));

            const float h = 2.5f;
            blueprint.walls.Add(Box("outer.n", 0, -7, 24, 0.3f, h));
            blueprint.walls.Add(Box("outer.s", 0, 7, 24, 0.3f, h));
            blueprint.walls.Add(Box("outer.w", -12, 0, 0.3f, 14, h));
            blueprint.walls.Add(Box("outer.e", 12, 0, 0.3f, 14, h));

            // Exactly two rooms. The single shared doorway belongs to the
            // environment room's test surface; the left room stays empty.
            blueprint.walls.Add(Box("divider.north", 0, -3.9f, 0.3f, 6.2f, h));
            blueprint.walls.Add(Box("divider.south", 0, 3.9f, 0.3f, 6.2f, h));
            AddDoor("door.rooms", 0, 0, 0.12f, 1.6f);
            blueprint.rooms.Add(new RoomSpec
            {
                id = "room.movement",
                bounds = Box("room.movement", -6f, 0f, 11.7f, 13.7f, 0f)
            });
            blueprint.rooms.Add(new RoomSpec
            {
                id = "room.environment",
                bounds = Box("room.environment", 6f, 0f, 11.7f, 13.7f, 0f)
            });
            blueprint.portals.Add(new PortalSpec
            {
                id = "portal.rooms",
                roomAId = "room.movement",
                roomBId = "room.environment",
                doorId = "door.rooms",
                position = new WorldPoint(0f, 0f, 0f),
                width = 1.6f,
                baseCost = 1f
            });

            // Furniture exists only in the right-hand room, leaving the
            // four-node patrol room geometrically clean and reproducible.
            AddProp("desk.environment.a", "desk.office", 4.0f, -4.5f, 2.4f, 1.1f, 0.75f);
            AddProp("chair.environment", "chair.office", 5.8f, -4.3f, 0.7f, 0.7f, 1f);
            AddProp("cabinet.environment", "cabinet.filing", 9.7f, -4.8f, 0.9f, 1.3f, 1.35f);
            AddProp("desk.environment.b", "desk.office", 5.0f, 3.2f, 2.6f, 1.2f, 0.75f);
            AddProp("safe.environment", "safe.wall", 9.4f, 3.8f, 0.8f, 0.7f, 0.8f);
            AddProp("plant.environment", "plant.potted", 9.7f, 5.6f, 0.8f, 0.8f, 1.2f);
            blueprint.props.Add(new PlacedProp
            {
                // Deliberately away from the doorway and the furniture
                // clusters at the back walls — the owner found it visually
                // blending into the door when it sat right next to it.
                id = "alarm.radio.environment", prototypeId = "alarm.radio",
                box = Box("alarm.radio.environment", 6.5f, 0f, 0.5f, 0.5f, 0.9f),
                config = new Dictionary<string, LevelValue>
                {
                    // Generous on purpose: worst case is the guard at the
                    // patrol rectangle's far corner (-10,-5)/(-10,5), ~17.2m
                    // straight-line from here, plus StimulusSystem's 3m
                    // one-portal attenuation — needs to clear ~20.2m total.
                    { "noiseRadius", LevelValue.Float(23f) }
                }
            });
            blueprint.props.Add(new PlacedProp
            {
                id = "camera.environment", prototypeId = "camera.wall",
                box = new WorldBox
                {
                    sourceID = "camera.environment", centerX = 10.7f, centerZ = 0f,
                    width = 0.4f, depth = 0.4f, height = 0.25f, yaw = -90f
                },
                config = new Dictionary<string, LevelValue>
                {
                    { "powered", LevelValue.Bool(true) },
                    { "range", LevelValue.Float(VisionProfiles.securityCamera.range) },
                    { "fieldOfView", LevelValue.Float(VisionProfiles.securityCamera.fieldOfViewDegrees) },
                    { "scanArc", LevelValue.Float(80f) },
                    { "scanPeriod", LevelValue.Float(7f) },
                    { "mountHeight", LevelValue.Float(2.35f) },
                    { "mountWallId", LevelValue.String("outer.e") }
                }
            });

            if (spawnThief)
            {
                blueprint.actors.Add(new ActorSpec
                {
                    id = "thief1", prototypeId = "actor.thief",
                    position = new CellPoint(-6, 0), yaw = 0f
                });
            }
            blueprint.actors.Add(new ActorSpec
            {
                id = "guard1", prototypeId = "actor.guard",
                position = new CellPoint(-10, -5), yaw = 90f,
                config = new Dictionary<string, LevelValue>
                {
                    { "showPatrolRoute", LevelValue.Bool(true) },
                    { "visionEnabled", LevelValue.Bool(true) },
                    { "visionRange", LevelValue.Float(VisionProfiles.guardActor.range) },
                    { "visionFov", LevelValue.Float(VisionProfiles.guardActor.fieldOfViewDegrees) }
                },
                route = new List<CellPoint>
                {
                    new CellPoint(-10, -5),
                    new CellPoint(-2, -5),
                    new CellPoint(-2, 5),
                    new CellPoint(-10, 5)
                }
            });

            Debug.Log($"Developer sandbox generated: 2 rooms, one 4-node guard, {blueprint.walls.Count} walls, " +
                      $"{blueprint.props.Count} props, {blueprint.actors.Count} actors");
        }

        private void AddDoor(string id, float x, float z, float width, float depth)
        {
            blueprint.props.Add(new PlacedProp
            {
                id = id, prototypeId = "door.single",
                box = Box(id, x, z, width, depth, 2.1f),
                config = new Dictionary<string, LevelValue>
                {
                    { "locked", LevelValue.Bool(false) },
                    { "open", LevelValue.Bool(true) },
                    { "hingeSide", LevelValue.String("Left") }
                }
            });
        }

        private void AddProp(string id, string prototype, float x, float z, float width, float depth, float height)
        {
            blueprint.props.Add(new PlacedProp
            {
                id = id, prototypeId = prototype,
                box = Box(id, x, z, width, depth, height)
            });
        }

        private static WorldBox Box(string id, float x, float z, float width, float depth, float height)
            => new WorldBox { sourceID = id, centerX = x, centerZ = z, width = width, depth = depth, height = height };
    }
}
