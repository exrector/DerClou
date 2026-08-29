namespace DerClou.Core.Tests
{
    using System.Linq;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Planning;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using NUnit.Framework;

    public sealed class SmartTraversalTests
    {
        [Test]
        public void CrossRoomMove_CompilesDoorTraversal_WithoutRuntimeReplan()
        {
            var level = TwoRoomLevel();
            var baseGrid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.2f, 0.08f);
            var state = new MissionState
            {
                ImmutableBaseGrid = baseGrid,
                Grid = baseGrid.Clone(),
                Topology = WorldTopology.Build(level, PropCatalog.Standard)
            };
            var doorBox = level.props[0].box;
            state.Doors["door.ab"] = new DoorState
            {
                id = "door.ab", footprint = doorBox, isOpen = false,
                openDurationSeconds = 1f, closeDurationSeconds = 1f
            };
            DoorSystem.SynchronizeNavigation(state, state.Doors["door.ab"]);
            state.Actors[1] = new ActorState
            {
                ActorId = 1, Position = new WorldPoint(-2f, 0f, 0f),
                FacingYawDegrees = 90f, Profile = CharacterProfile.Standard
            };
            var plan = new MissionPlan();
            var cursor = new PlanCursor
            {
                Position = state.Actors[1].Position,
                FacingYawDegrees = 90f,
                HasFacing = true
            };

            Assert.IsTrue(PlanBuilder.QueueMove(
                plan, state, 1, ref cursor, new WorldPoint(2f, 0f, 0f)));

            var actions = plan.actorPlans[1].actions;
            CollectionAssert.Contains(actions.Select(action => action.type).ToArray(), PlanActionType.Align);
            CollectionAssert.Contains(actions.Select(action => action.type).ToArray(), PlanActionType.OpenDoor);
            CollectionAssert.Contains(actions.Select(action => action.type).ToArray(), PlanActionType.TraversePortal);
            CollectionAssert.Contains(actions.Select(action => action.type).ToArray(), PlanActionType.CloseDoor);
            var traverse = actions.Single(action => action.type == PlanActionType.TraversePortal);
            Assert.AreEqual("portal.ab", traverse.targetId);
            Assert.IsNotNull(traverse.frozenTrajectory);
            Assert.AreEqual(1, traverse.frozenTrajectory.Length);
            Assert.Greater(traverse.frozenTrajectory[0].x, 0f);
            Assert.AreEqual(2f, cursor.Position.x, 0.001f);
        }

        [Test]
        public void DoorStateChange_UpdatesOnlyAuthoritativeLocalNavigationAndRevision()
        {
            var level = TwoRoomLevel();
            var baseGrid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.2f, 0.08f);
            var state = new MissionState
            {
                ImmutableBaseGrid = baseGrid,
                Grid = baseGrid.Clone(),
                Topology = WorldTopology.Build(level, PropCatalog.Standard)
            };
            var door = new DoorState
            {
                id = "door.ab", footprint = level.props[0].box,
                isOpen = false
            };
            state.Doors[door.id] = door;
            DoorSystem.SynchronizeNavigation(state, door);
            var centre = state.Grid.WorldToCell(new WorldPoint(0f, 0f, 0f));
            Assert.IsFalse(state.Grid.Get((int)centre.x, (int)centre.y).walkable);

            DoorSystem.SetOpen(state, door.id, true);

            Assert.IsTrue(state.Grid.Get((int)centre.x, (int)centre.y).walkable);
            Assert.AreEqual(1u, state.Topology.rooms.GetPortalRevision("portal.ab"));
        }

        [Test]
        public void FurnitureInteraction_ChoosesReachablePerimeterSlot_NotBlockedCentre()
        {
            var level = TwoRoomLevel();
            var crate = new WorldBox
            {
                sourceID = "crate", centerX = -2f, centerZ = 0f,
                width = 1f, depth = 1f, height = 1f
            };
            level.props.Add(new PlacedProp
            {
                id = "crate", prototypeId = "crate.storage", box = crate
            });
            var grid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.2f, 0.08f);
            var state = new MissionState { Grid = grid, ImmutableBaseGrid = grid.Clone() };
            state.Actors[1] = new ActorState
            {
                ActorId = 1, Position = new WorldPoint(-3.5f, 0f, 0f),
                FacingYawDegrees = 90f, Profile = CharacterProfile.Standard
            };
            var cursor = new PlanCursor
            {
                Position = state.Actors[1].Position,
                FacingYawDegrees = 90f,
                HasFacing = true
            };
            var plan = new MissionPlan();

            PlanBuilder.QueueInteract(plan, state, 1, ref cursor, crate,
                PlanActionType.TakeLoot, "crate",
                new System.Collections.Generic.Dictionary<string, LevelValue>(),
                new DefaultDurationProvider());

            var actions = plan.actorPlans[1].actions;
            Assert.AreEqual(3, actions.Count);
            Assert.AreEqual(PlanActionType.MoveTo, actions[0].type);
            Assert.AreEqual(PlanActionType.Align, actions[1].type);
            Assert.AreEqual(PlanActionType.TakeLoot, actions[2].type);
            Assert.Greater(System.MathF.Abs(actions[0].targetPos.x - crate.centerX)
                + System.MathF.Abs(actions[0].targetPos.z - crate.centerZ), 0.5f);
        }

        private static LevelBlueprint TwoRoomLevel()
        {
            var level = new LevelBlueprint { metrics = new LevelMetrics(0.2f, 2.5f) };
            level.floors.Add(new WorldBox { sourceID = "floor", centerX = 0, centerZ = 0, width = 8, depth = 6 });
            level.walls.Add(new WorldBox { sourceID = "divider.n", centerX = 0, centerZ = -2, width = 0.3f, depth = 2 });
            level.walls.Add(new WorldBox { sourceID = "divider.s", centerX = 0, centerZ = 2, width = 0.3f, depth = 2 });
            level.props.Add(new PlacedProp
            {
                id = "door.ab", prototypeId = "door.single",
                box = new WorldBox { sourceID = "door.ab", centerX = 0, centerZ = 0, width = 0.12f, depth = 1.6f, height = 2.1f }
            });
            level.rooms.Add(new RoomSpec { id = "room.a", bounds = new WorldBox { centerX = -2, centerZ = 0, width = 4, depth = 6 } });
            level.rooms.Add(new RoomSpec { id = "room.b", bounds = new WorldBox { centerX = 2, centerZ = 0, width = 4, depth = 6 } });
            level.portals.Add(new PortalSpec
            {
                id = "portal.ab", roomAId = "room.a", roomBId = "room.b",
                doorId = "door.ab", position = new WorldPoint(0, 0, 0), width = 1.6f, baseCost = 1f
            });
            return level;
        }
    }
}
