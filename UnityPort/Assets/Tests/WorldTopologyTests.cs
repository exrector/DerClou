namespace DerClou.Core.Tests
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using NUnit.Framework;

    public sealed class WorldTopologyTests
    {
        [Test]
        public void RoomRoute_UsesPortalAndReportsRequiredDoor()
        {
            var level = TwoRoomLevel();
            var doors = new Dictionary<string, DoorState>
            {
                ["door.ab"] = new DoorState { id = "door.ab", isOpen = true }
            };
            var graph = RoomPortalGraph.Build(level);

            Assert.IsTrue(graph.TryFindRoute(
                new WorldPoint(-2, 0, 0), new WorldPoint(2, 0, 0), doors, false, out var route));
            CollectionAssert.AreEqual(new[] { "room.a", "room.b" }, route.roomIds);
            CollectionAssert.AreEqual(new[] { "portal.ab" }, route.portalIds);
            CollectionAssert.AreEqual(new[] { "door.ab" }, route.requiredDoorIds);
        }

        [Test]
        public void ClosedPortal_IsNotRawMovement_ButIsSmartTraversalCandidate()
        {
            var graph = RoomPortalGraph.Build(TwoRoomLevel());
            var doors = new Dictionary<string, DoorState>
            {
                ["door.ab"] = new DoorState { id = "door.ab", isOpen = false, isLocked = false }
            };
            var start = new WorldPoint(-2, 0, 0);
            var goal = new WorldPoint(2, 0, 0);

            Assert.IsFalse(graph.TryFindRoute(start, goal, doors, false, out _));
            Assert.IsTrue(graph.TryFindRoute(start, goal, doors, true, out var smartRoute));
            CollectionAssert.AreEqual(new[] { "door.ab" }, smartRoute.requiredDoorIds);

            doors["door.ab"].isLocked = true;
            Assert.IsFalse(graph.TryFindRoute(start, goal, doors, true, out _));
        }

        [Test]
        public void DoorChange_RevisesOnlyItsPortal()
        {
            var topology = WorldTopology.Build(TwoRoomLevel(), PropCatalog.Standard);
            uint worldBefore = topology.revision;
            uint portalBefore = topology.rooms.GetPortalRevision("portal.ab");

            topology.PublishDoorChange("unrelated");
            Assert.AreEqual(worldBefore, topology.revision);
            topology.PublishDoorChange("door.ab");
            Assert.AreEqual(worldBefore + 1, topology.revision);
            Assert.AreEqual(portalBefore + 1, topology.rooms.GetPortalRevision("portal.ab"));
        }

        [Test]
        public void LocalDoorOccupancy_DoesNotTouchRemoteCells()
        {
            var level = TwoRoomLevel();
            var immutableGrid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.3f, 0.08f);
            var liveGrid = immutableGrid.Clone();
            var remote = liveGrid.WorldToCell(new WorldPoint(-3, 0, -2));
            bool remoteBefore = liveGrid.Get((int)remote.x, (int)remote.y).walkable;
            var door = level.props[0].box;

            liveGrid.ApplyLocalBoxOccupancy(immutableGrid, door, true, 0.38f);
            var centre = liveGrid.WorldToCell(new WorldPoint(0, 0, 0));
            Assert.IsFalse(liveGrid.Get((int)centre.x, (int)centre.y).walkable);
            Assert.AreEqual(remoteBefore, liveGrid.Get((int)remote.x, (int)remote.y).walkable);

            liveGrid.ApplyLocalBoxOccupancy(immutableGrid, door, false, 0.38f);
            Assert.IsTrue(liveGrid.Get((int)centre.x, (int)centre.y).walkable);
            Assert.AreEqual(remoteBefore, liveGrid.Get((int)remote.x, (int)remote.y).walkable);
        }

        [Test]
        public void SpatialHash_ReturnsStableUniqueNearbyFootprints()
        {
            var topology = WorldTopology.Build(TwoRoomLevel(), PropCatalog.Standard);
            var results = new List<SpatialFootprint>();
            topology.spatial.Query(new WorldBox { centerX = 0, centerZ = 0, width = 2, depth = 2 }, results);

            Assert.AreEqual(1, results.FindAll(item => item.id == "divider.n").Count);
            Assert.AreEqual(1, results.FindAll(item => item.id == "divider.s").Count);
        }

        [Test]
        public void CommittedRoute_RecordsOnlyCrossedPortalRevision()
        {
            var level = TwoRoomLevel();
            var state = new MissionState
            {
                Grid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.3f, 0.08f),
                Topology = WorldTopology.Build(level, PropCatalog.Standard)
            };
            state.Doors["door.ab"] = new DoorState { id = "door.ab", isOpen = true };
            state.Actors[1] = new ActorState
            {
                ActorId = 1, Position = new WorldPoint(-2, 0, 0),
                Profile = CharacterProfile.Standard
            };

            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(2, 0, 0));

            var actor = state.Actors[1];
            Assert.IsTrue(actor.HasPath);
            CollectionAssert.AreEqual(new[] { "portal.ab" }, actor.PortalDependencies);
            CollectionAssert.AreEqual(new uint[] { 0 }, actor.PortalDependencyRevisions);
            state.Topology.PublishDoorChange("unrelated");
            Assert.AreEqual(0u, state.Topology.rooms.GetPortalRevision("portal.ab"));
            state.Topology.PublishDoorChange("door.ab");
            Assert.AreEqual(1u, state.Topology.rooms.GetPortalRevision("portal.ab"));
        }

        private static LevelBlueprint TwoRoomLevel()
        {
            var level = new LevelBlueprint { metrics = new LevelMetrics(0.25f, 2.5f) };
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
