namespace DerClou.Core.Tests
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Planning;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using NUnit.Framework;

    public sealed class PlanningCorridorTests
    {
        [Test]
        public void MovementRequest_UsesStandardProvider_WhenCorridorIsGridLegal()
        {
            var provider = new RecordingProvider();
            var state = State(provider);

            ActorMovementSystem.RequestPath(state, 1, new WorldPoint(2f, 0f, 0f));

            Assert.AreEqual(1, provider.CallCount);
            Assert.IsTrue(state.Actors[1].HasPath);
            Assert.IsTrue(System.Array.Exists(
                state.Actors[1].CurrentPath, point => point.z > 0.5f));
        }

        [Test]
        public void PlannedMove_ExecutesFrozenTrajectory_WithoutSecondProviderQuery()
        {
            var provider = new RecordingProvider();
            var state = State(provider);
            var plan = new MissionPlan();
            var cursor = new PlanCursor
            {
                Position = state.Actors[1].Position,
                FacingYawDegrees = 90f,
                HasFacing = true
            };

            Assert.IsTrue(PlanBuilder.QueueMove(
                plan, state, 1, ref cursor, new WorldPoint(2f, 0f, 0f)));
            Assert.AreEqual(1, provider.CallCount);
            var compiled = plan.actorPlans[1].actions[0].frozenTrajectory;
            Assert.IsNotNull(compiled);
            Assert.IsNotEmpty(compiled);

            var forbiddenDuringExecution = new RecordingProvider { ReturnFailure = true };
            state.SpatialCorridors = forbiddenDuringExecution;
            var executor = new PlanExecutor();
            executor.Begin(plan);
            executor.Tick(state, 0f);

            Assert.AreEqual(0, forbiddenDuringExecution.CallCount,
                "Execute must install the compiled route, not ask NavMesh/A* again.");
            Assert.IsTrue(state.Actors[1].HasPath);
            Assert.AreNotSame(compiled, state.Actors[1].CurrentPath,
                "Actor state owns a copy; the immutable plan remains reusable for Retry.");
            Assert.AreEqual(compiled.Length, state.Actors[1].CurrentPath.Length);
            for (int i = 0; i < compiled.Length; i++)
            {
                Assert.AreEqual(compiled[i].x, state.Actors[1].CurrentPath[i].x);
                Assert.AreEqual(compiled[i].z, state.Actors[1].CurrentPath[i].z);
            }
        }

        private static MissionState State(ISpatialCorridorProvider provider)
        {
            var state = new MissionState
            {
                Grid = OpenGrid(),
                SpatialCorridors = provider
            };
            state.Actors[1] = new ActorState
            {
                ActorId = 1,
                Role = ActorRole.Thief,
                Position = new WorldPoint(-2f, 0f, 0f),
                FacingYawDegrees = 90f,
                Profile = CharacterProfile.Standard,
                TrajectoryCommittedAt = float.PositiveInfinity
            };
            return state;
        }

        private static NavGrid OpenGrid()
        {
            const int size = 100;
            var cells = new NavCell[size * size];
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                cells[y * size + x] = new NavCell { x = x, y = y, walkable = true };
            return new NavGrid
            {
                width = size,
                height = size,
                cellSize = 0.1f,
                originX = -5f,
                originZ = -5f,
                cells = cells
            };
        }

        private sealed class RecordingProvider : ISpatialCorridorProvider
        {
            public int CallCount;
            public bool ReturnFailure;

            public bool TryFindCorridor(
                WorldPoint start,
                WorldPoint destination,
                out WorldPoint[] corridor)
            {
                CallCount++;
                if (ReturnFailure)
                {
                    corridor = System.Array.Empty<WorldPoint>();
                    return false;
                }
                corridor = new[]
                {
                    new WorldPoint(0f, 0f, 1f),
                    new WorldPoint(destination.x, 0f, 1f),
                    destination
                };
                return true;
            }
        }
    }
}
