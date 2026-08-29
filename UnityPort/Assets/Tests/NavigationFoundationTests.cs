namespace DerClou.Core.Tests
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using NUnit.Framework;

    public class NavigationGeometryTests
    {
        [Test]
        public void ThinWallBetweenCellCentres_CannotBeCrossed()
        {
            var level = new LevelBlueprint { metrics = new LevelMetrics(0.5f, 2.5f) };
            level.floors.Add(new WorldBox { centerX = 0, centerZ = 0, width = 6, depth = 6 });
            level.walls.Add(new WorldBox { centerX = 0, centerZ = 0, width = 0.3f, depth = 6, height = 2.5f });
            var grid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.3f, 0.08f);

            var path = PathFinder.FindPath(grid, new WorldPoint(-2, 0, 0), new WorldPoint(2, 0, 0));
            Assert.IsEmpty(path, "A 0.3m wall must not disappear inside a 0.5m grid.");
        }

        [Test]
        public void BlockingFurniture_IsRasterizedWithBodyClearance()
        {
            var level = new LevelBlueprint { metrics = new LevelMetrics(0.25f, 2.5f) };
            level.floors.Add(new WorldBox { centerX = 0, centerZ = 0, width = 5, depth = 5 });
            level.props.Add(new PlacedProp
            {
                id = "desk", prototypeId = "desk.office",
                box = new WorldBox { centerX = 0, centerZ = 0, width = 2, depth = 1, height = 0.75f }
            });
            var grid = NavGrid.BuildFromBlueprint(level, PropCatalog.Standard, 0.3f, 0.08f);
            var centre = grid.WorldToCell(new WorldPoint(0, 0, 0));
            Assert.IsFalse(grid.Get((int)centre.x, (int)centre.y).walkable);
        }
    }

    public class TrajectoryBuilderPortTests
    {
        [Test]
        public void RightAngle_IsRoundedDeterministically_AndStaysLegal()
        {
            var grid = OpenGrid();
            var start = new WorldPoint(0, 0, 0);
            var raw = new[] { new WorldPoint(2, 0, 0), new WorldPoint(2, 0, 2) };
            var first = TrajectoryBuilder.Rounded(start, raw, grid, CharacterProfile.Standard);
            var second = TrajectoryBuilder.Rounded(start, raw, grid, CharacterProfile.Standard);

            Assert.Greater(first.Length, raw.Length);
            Assert.AreEqual(first.Length, second.Length);
            for (int i = 0; i < first.Length; i++)
            {
                Assert.AreEqual(first[i].x, second[i].x);
                Assert.AreEqual(first[i].z, second[i].z);
            }
            var previous = start;
            foreach (var point in first)
            {
                Assert.IsTrue(PathFinder.HasLineOfSight(grid, previous, point));
                previous = point;
            }
        }

        [Test]
        public void OrdinaryRetarget_BeginsAlongCurrentHeading_ButReversalDoesNotInventSide()
        {
            var grid = OpenGrid();
            var start = new WorldPoint(0, 0, 0);
            var east = new[] { new WorldPoint(3, 0, 0) };
            var curve = TrajectoryBuilder.Continuous(start, east, 0, grid, CharacterProfile.Standard);
            Assert.Greater(curve.Length, 2);
            float firstYaw = System.MathF.Atan2(curve[0].x, curve[0].z) * 180f / System.MathF.PI;
            Assert.Less(System.MathF.Abs(TrajectoryBuilder.DeltaAngle(0, firstYaw)), 4f);

            var west = new[] { new WorldPoint(-3, 0, 0) };
            var reversal = TrajectoryBuilder.Continuous(start, west, 90, grid, CharacterProfile.Standard);
            Assert.AreEqual(1, reversal.Length);
        }

        private static NavGrid OpenGrid()
        {
            int size = 80;
            var cells = new NavCell[size * size];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++)
                cells[y * size + x] = new NavCell { x = x, y = y, walkable = true };
            return new NavGrid { width = size, height = size, cellSize = 0.1f, originX = -2, originZ = -2, cells = cells };
        }
    }

    public class TangentDetourPlannerTests
    {
        [Test]
        public void StationaryBody_ProducesOneSmoothTangentArcToDestination()
        {
            var grid = OpenGrid();
            var start = new WorldPoint(-3, 0, 0);
            var destination = new WorldPoint(3, 0, 0);
            var blocker = new WorldPoint(0, 0, 0);
            const float clearance = 0.68f;

            Assert.IsTrue(TangentDetourPlanner.TryBuild(
                start, destination, 90f, blocker, clearance,
                grid, CharacterProfile.Standard, out var path));
            Assert.Greater(path.Length, 8);
            Assert.AreEqual(destination.x, path[^1].x, 0.0001f);
            Assert.AreEqual(destination.z, path[^1].z, 0.0001f);

            var previous = start;
            float previousYaw = 90f;
            foreach (var point in path)
            {
                float dx = point.x - previous.x, dz = point.z - previous.z;
                float yaw = System.MathF.Atan2(dx, dz) * 180f / System.MathF.PI;
                Assert.Less(System.MathF.Abs(TrajectoryBuilder.DeltaAngle(previousYaw, yaw)), 35f);
                previousYaw = yaw;
                previous = point;
            }
        }

        private static NavGrid OpenGrid()
        {
            int size = 120;
            var cells = new NavCell[size * size];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++)
                cells[y * size + x] = new NavCell { x = x, y = y, walkable = true };
            return new NavGrid { width = size, height = size, cellSize = 0.1f, originX = -6, originZ = -6, cells = cells };
        }
    }

    public class MultiActorMovementTests
    {
        [Test]
        public void SteadyStateFixedTicks_DoNotAllocateAfterWarmup()
        {
            var state = new MissionState { Grid = OpenGrid() };
            state.Actors[1] = Actor(1, -3, 0, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(3, 0, 0));
            for (int tick = 0; tick < 20; tick++) ActorMovementSystem.Tick(state, 1f / 60f);

            System.GC.Collect();
            long before = System.GC.GetAllocatedBytesForCurrentThread();
            for (int tick = 0; tick < 120; tick++) ActorMovementSystem.Tick(state, 1f / 60f);
            long allocated = System.GC.GetAllocatedBytesForCurrentThread() - before;

            Assert.LessOrEqual(allocated, 64L,
                "Stable fixed-step movement must not allocate per frame; path solves are event-only.");
        }

        [Test]
        public void StationaryActor_IsBuiltIntoRoute_AndBodiesNeverOverlap()
        {
            var state = new MissionState { Grid = OpenGrid() };
            state.Actors[1] = Actor(1, -2, 0, 10);
            state.Actors[2] = Actor(2, 0, 0, 50);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(2, 0, 0));
            Assert.IsTrue(state.Actors[1].HasPath);

            for (int i = 0; i < 600; i++)
            {
                ActorMovementSystem.Tick(state, 1f / 60f);
                float dx = state.Actors[1].Position.x - state.Actors[2].Position.x;
                float dz = state.Actors[1].Position.z - state.Actors[2].Position.z;
                Assert.GreaterOrEqual(dx * dx + dz * dz, 0.62f * 0.62f - 0.0001f);
            }
            Assert.Greater(state.Actors[1].Position.x, 1.5f);
        }

        [Test]
        public void SameStationaryBlocker_DoesNotCauseRepeatedReplans()
        {
            var state = new MissionState { Grid = OpenGrid() };
            state.Actors[1] = Actor(1, -2, 0, 10);
            state.Actors[2] = Actor(2, 0, 0, 50);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(2, 0, 0));
            for (int i = 0; i < 600; i++) ActorMovementSystem.Tick(state, 1f / 60f);
            Assert.LessOrEqual(state.Actors[1].RouteRevision, 2,
                "The same body in the same position may trigger at most one corrective route.");
        }

        [Test]
        public void BrakingCurve_ReachesExactDestinationWithoutFreezingShort()
        {
            var state = new MissionState { Grid = OpenGrid() };
            state.Actors[1] = Actor(1, -2, 0, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(2, 0, 0));
            for (int i = 0; i < 600; i++) ActorMovementSystem.Tick(state, 1f / 60f);
            var actor = state.Actors[1];
            Assert.IsFalse(actor.HasPath);
            Assert.AreEqual(2f, actor.Position.x, 0.06f);
            Assert.AreEqual(0f, actor.CurrentSpeed, 0.0001f);
        }

        [Test]
        public void RetargetWhileMoving_PreservesSpeedAndDoesNotInsertAStop()
        {
            var state = new MissionState { Grid = OpenGrid() };
            state.Actors[1] = Actor(1, -2, 0, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(3, 0, 0));
            for (int i = 0; i < 60; i++) ActorMovementSystem.Tick(state, 1f / 60f);
            float before = state.Actors[1].CurrentSpeed;
            Assert.Greater(before, 1f);

            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(1, 0, 3));
            var after = state.Actors[1];
            Assert.AreEqual(before, after.CurrentSpeed, 0.000001f);
            Assert.IsTrue(after.HasPath);
            Assert.Greater(after.CurrentPath.Length, 1);
        }

        [Test]
        public void CorrectiveReplan_PreservesOriginalRightOfWayTimestamp()
        {
            var state = new MissionState { Grid = OpenGrid(), CurrentTime = 2f };
            state.Actors[1] = Actor(1, -2, 0, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(3, 0, 0));
            Assert.AreEqual(2f, state.Actors[1].TrajectoryCommittedAt);

            state.CurrentTime = 8f;
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(3, 0, 0), true);
            Assert.AreEqual(2f, state.Actors[1].TrajectoryCommittedAt);
        }

        [Test]
        public void LaterCrossingRoute_DetoursAroundFirstCommittedTrajectory()
        {
            var state = new MissionState { Grid = OpenGrid(), CurrentTime = 1f };
            state.Actors[1] = Actor(1, -2, 0, 50);
            state.Actors[2] = Actor(2, 0, -2, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(2, 0, 0));
            state.CurrentTime = 2f;
            ActorMovementSystem.RequestPath(state, 2, new WorldPoint(0, 0, 2));

            var later = state.Actors[2];
            Assert.IsTrue(later.HasPath);
            Assert.IsTrue(System.Array.Exists(later.CurrentPath, p => System.MathF.Abs(p.x) > 0.25f));
            Assert.Less(state.Actors[1].TrajectoryCommittedAt, later.TrajectoryCommittedAt);

            for (int tick = 0; tick < 360; tick++)
            {
                ActorMovementSystem.Tick(state, 1f / 60f);
                float dx = state.Actors[1].Position.x - state.Actors[2].Position.x;
                float dz = state.Actors[1].Position.z - state.Actors[2].Position.z;
                Assert.GreaterOrEqual(dx * dx + dz * dz, 0.62f * 0.62f - 0.0001f);
            }
        }

        [Test]
        public void UnexpectedStationaryActorAhead_InstallsOneEarlyArcWithoutJitter()
        {
            var state = new MissionState { Grid = OpenGrid(), CurrentTime = 1f };
            state.Actors[1] = Actor(1, -3, 0, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(3, 0, 0));
            for (int tick = 0; tick < 30; tick++) ActorMovementSystem.Tick(state, 1f / 60f);
            Assert.AreEqual(1, state.Actors[1].RouteRevision);

            state.Actors[2] = Actor(2, 0, 0, 50);
            ActorMovementSystem.Tick(state, 1f / 60f);
            var detour = state.Actors[1];
            Assert.AreEqual(2, detour.RouteRevision);
            Assert.IsTrue(System.Array.Exists(detour.CurrentPath, p => System.MathF.Abs(p.z) > 0.5f));
            Assert.Greater(-detour.Position.x, 1.5f, "Avoidance must be planned before contact.");

            for (int tick = 0; tick < 600; tick++)
            {
                ActorMovementSystem.Tick(state, 1f / 60f);
                float dx = state.Actors[1].Position.x - state.Actors[2].Position.x;
                float dz = state.Actors[1].Position.z - state.Actors[2].Position.z;
                Assert.GreaterOrEqual(dx * dx + dz * dz, 0.62f * 0.62f - 0.0001f);
            }
            Assert.AreEqual(2, state.Actors[1].RouteRevision,
                "One unchanged blocker must produce one maneuver, not short replans.");
            Assert.AreEqual(3f, state.Actors[1].Position.x, 0.07f);
        }

        [Test]
        public void OccupiedPatrolNode_IsSkippedToFollowingNodeWithoutStopping()
        {
            var state = new MissionState { Grid = OpenGrid(), CurrentTime = 1f };
            state.Actors[1] = Actor(1, -2, 0, 10);
            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(0, 0, 0));
            for (int tick = 0; tick < 30; tick++) ActorMovementSystem.Tick(state, 1f / 60f);
            float speedBefore = state.Actors[1].CurrentSpeed;
            float commitment = state.Actors[1].TrajectoryCommittedAt;
            state.Actors[2] = Actor(2, 0, 0, 50);
            state.Guards[1] = new GuardState
            {
                actorId = 1,
                currentNodeIndex = 1,
                state = GuardState.State.Moving,
                route = new PatrolRoute
                {
                    actorId = 1,
                    nodes = new[]
                    {
                        new PatrolNode { position = new WorldPoint(-2, 0, 0) },
                        new PatrolNode { position = new WorldPoint(0, 0, 0) },
                        new PatrolNode { position = new WorldPoint(0, 0, 2) },
                        new PatrolNode { position = new WorldPoint(-2, 0, 2) }
                    }
                }
            };

            GuardPatrolSystem.Tick(state, 1f / 60f);
            var guard = state.Guards[1];
            var actor = state.Actors[1];
            Assert.AreEqual(2, guard.currentNodeIndex);
            Assert.IsTrue(actor.HasPath);
            Assert.AreEqual(0f, actor.LastRequestedDestination.x, 0.0001f);
            Assert.AreEqual(2f, actor.LastRequestedDestination.z, 0.0001f);
            Assert.AreEqual(speedBefore, actor.CurrentSpeed, 0.000001f);
            Assert.AreEqual(commitment, actor.TrajectoryCommittedAt);
            Assert.IsTrue(System.Array.Exists(actor.CurrentPath, p => p.x < -0.35f && p.z > 0.2f),
                "The occupied right-angle corner must be rounded through its short inner sector.");
            float closestToOccupied = float.PositiveInfinity;
            int pointsNearCorner = 0;
            foreach (var point in actor.CurrentPath)
            {
                float distance = System.MathF.Sqrt(point.x * point.x + point.z * point.z);
                closestToOccupied = System.MathF.Min(closestToOccupied, distance);
                if (distance < 0.9f)
                {
                    pointsNearCorner++;
                    Assert.LessOrEqual(point.x, 0.03f,
                        "An occupied corner must never be bypassed on the exterior X side.");
                    Assert.GreaterOrEqual(point.z, -0.03f,
                        "An occupied corner must never be bypassed on the exterior Z side.");
                }
            }
            Assert.Greater(pointsNearCorner, 3, "The test must inspect the curved section around node 2.");
            Assert.Less(closestToOccupied, 0.85f,
                "The bypass must stay close to the occupied node instead of taking a wide generic detour.");
        }

        [Test]
        public void AlertEnded_RejoinsNearestReachablePatrolNode_NotStaleNextNode()
        {
            var state = new MissionState { Grid = OpenGrid(), CurrentTime = 12f };
            state.Actors[1] = Actor(1, 2.8f, 2.9f, 10);
            state.Guards[1] = new GuardState
            {
                actorId = 1,
                currentNodeIndex = 1,
                state = GuardState.State.Alert,
                isAlerted = false,
                alertLevel = 0.8f,
                route = new PatrolRoute
                {
                    actorId = 1,
                    nodes = new[]
                    {
                        new PatrolNode { position = new WorldPoint(-3, 0, -3) },
                        new PatrolNode { position = new WorldPoint(3, 0, -3) },
                        new PatrolNode { position = new WorldPoint(3, 0, 3) },
                        new PatrolNode { position = new WorldPoint(-3, 0, 3) }
                    }
                }
            };

            GuardPatrolSystem.Tick(state, 1f / 60f);

            Assert.AreEqual(2, state.Guards[1].currentNodeIndex,
                "The closest route node must replace the stale next-node index.");
            Assert.AreEqual(GuardState.State.Moving, state.Guards[1].state);
            Assert.AreEqual(0f, state.Guards[1].alertLevel);
            Assert.IsTrue(state.Actors[1].HasPath);
            Assert.AreEqual(3f, state.Actors[1].LastRequestedDestination.x, 0.0001f);
            Assert.AreEqual(3f, state.Actors[1].LastRequestedDestination.z, 0.0001f);
        }

        [Test]
        public void OccupiedPatrolCorner_UsesOneBroadCurveTangentToBothRouteLegs()
        {
            var start = new WorldPoint(-10, 0, -5);
            var occupiedCorner = new WorldPoint(-2, 0, -5);
            var followingNode = new WorldPoint(-2, 0, 5);

            Assert.IsTrue(TangentDetourPlanner.TryBuildInsideCorner(
                start, followingNode, 90f, occupiedCorner, 0.68f,
                LargeOpenGrid(), CharacterProfile.Standard, out var path));

            float closest = float.PositiveInfinity;
            foreach (var point in path)
            {
                float dx = point.x - occupiedCorner.x;
                float dz = point.z - occupiedCorner.z;
                closest = System.MathF.Min(closest, System.MathF.Sqrt(dx * dx + dz * dz));
                Assert.LessOrEqual(point.x, occupiedCorner.x + 0.001f);
                Assert.GreaterOrEqual(point.z, occupiedCorner.z - 0.001f);
            }

            Assert.Greater(closest, 2.5f,
                "The guard must turn early in one broad curve, not orbit tightly around the blocking body.");
            Assert.Less(closest, 3.5f,
                "The skipped corner must still shape the route instead of becoming a direct diagonal cut.");
            var first = path[0];
            var beforeLast = path[path.Length - 2];
            Assert.Less(System.MathF.Abs(first.z - start.z), System.MathF.Abs(first.x - start.x) * 0.08f,
                "The curve must enter tangent to the incoming patrol leg.");
            Assert.Less(System.MathF.Abs(followingNode.x - beforeLast.x),
                System.MathF.Abs(followingNode.z - beforeLast.z) * 0.08f,
                "The curve must exit tangent to the outgoing patrol leg.");
        }

        private static ActorState Actor(int id, float x, float z, int priority) => new ActorState
        {
            ActorId = id, Position = new WorldPoint(x, 0, z), FacingYawDegrees = 90,
            Profile = CharacterProfile.Standard, AvoidancePriority = priority,
            TrajectoryCommittedAt = float.PositiveInfinity
        };

        private static NavGrid OpenGrid()
        {
            int size = 80;
            var cells = new NavCell[size * size];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++)
                cells[y * size + x] = new NavCell { x = x, y = y, walkable = true };
            return new NavGrid { width = size, height = size, cellSize = 0.1f, originX = -4, originZ = -4, cells = cells };
        }

        private static NavGrid LargeOpenGrid()
        {
            int size = 300;
            var cells = new NavCell[size * size];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++)
                cells[y * size + x] = new NavCell { x = x, y = y, walkable = true };
            return new NavGrid
            {
                width = size, height = size, cellSize = 0.1f,
                originX = -15, originZ = -15, cells = cells
            };
        }
    }
}
