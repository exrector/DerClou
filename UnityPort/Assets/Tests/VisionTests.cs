namespace DerClou.Core.Tests
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using DerClou.Core.Time;
    using NUnit.Framework;

    public class VisionSolverTests
    {
        private readonly VisionConfig config = new VisionConfig { range = 10f, fieldOfViewDegrees = 90f };
        private readonly WorldPoint observer = new WorldPoint(0f, 1.5f, 0f);

        [Test]
        public void GuardAndCameraProfiles_AreIntentionallyDifferent()
        {
            Assert.Greater(VisionProfiles.guardActor.range, VisionProfiles.securityCamera.range);
            Assert.Less(VisionProfiles.guardActor.fieldOfViewDegrees, VisionProfiles.securityCamera.fieldOfViewDegrees);
            Assert.GreaterOrEqual(VisionProfiles.guardActor.range, 20f);
            Assert.GreaterOrEqual(VisionProfiles.securityCamera.range, 14f);
            Assert.LessOrEqual(VisionProfiles.guardActor.fieldOfViewDegrees, 30f);
        }

        [Test]
        public void ClearTarget_InsideRangeAndCone_IsVisible()
        {
            var result = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(2f, 1.5f, 5f), config, new List<WorldBox>());
            Assert.IsTrue(result.IsVisible);
        }

        [Test]
        public void AuthoredRangeAndConeBoundaries_AreInclusive()
        {
            var rangeEdge = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(0f, 1.5f, 10f), config, new List<WorldBox>());
            var coneEdge = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(5f, 1.5f, 5f), config, new List<WorldBox>());
            Assert.IsTrue(rangeEdge.IsVisible);
            Assert.IsTrue(coneEdge.IsVisible);
        }

        [Test]
        public void OutsideRangeAndBehind_AreRejectedForExactReasons()
        {
            var far = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(0f, 1.5f, 10.01f), config, new List<WorldBox>());
            var behind = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(0f, 1.5f, -2f), config, new List<WorldBox>());
            Assert.AreEqual(VisionResultKind.OutOfRange, far.Kind);
            Assert.AreEqual(VisionResultKind.OutsideFieldOfView, behind.Kind);
        }

        [Test]
        public void WallBlocksSight_ButWallMissingRayDoesNot()
        {
            var target = new WorldPoint(0f, 1.5f, 8f);
            var blocked = VisionSolver.Evaluate(
                observer, 0f, target, config, new[] { Wall("wall", 0f, 4f) });
            var clear = VisionSolver.Evaluate(
                observer, 0f, target, config, new[] { Wall("wall", 4f, 4f) });
            Assert.AreEqual(VisionResultKind.Occluded, blocked.Kind);
            Assert.AreEqual("wall", blocked.OccluderId);
            Assert.IsTrue(clear.IsVisible);
        }

        [Test]
        public void RotatedWallFootprint_OccludesCorrectly()
        {
            var result = VisionSolver.Evaluate(
                observer, 90f, new WorldPoint(8f, 1.5f, 0f), config,
                new[] { Wall("rotated", 4f, 0f, 90f) });
            Assert.AreEqual(VisionResultKind.Occluded, result.Kind);
        }

        [Test]
        public void Occlusion_IsDeterminedByFootprint_NotHeight()
        {
            var lintel = new WorldBox
            {
                sourceID = "door.lintel",
                centerX = 0f,
                centerZ = 4f,
                width = 2f,
                depth = 0.2f,
                bottomY = 2.1f,
                height = 0.9f
            };
            var result = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(0f, 1.5f, 8f), config, new[] { lintel });
            Assert.AreEqual(VisionResultKind.Occluded, result.Kind);
        }

        [Test]
        public void DisplayedReach_StopsAtSameWallUsedForDetection()
        {
            float reach = VisionSolver.VisibleReach(
                observer, 1.5f, 0f, 10f, new[] { Wall("wall", 0f, 4f) });
            Assert.Greater(reach, 3.8f);
            Assert.Less(reach, 4f);
        }

        [Test]
        public void LowFurniture_BlocksBothDisplayedFieldAndDetection()
        {
            var desk = new WorldBox
            {
                sourceID = "desk", centerX = 0f, centerZ = 3f,
                width = 2f, depth = 1f, height = 0.75f
            };
            var floorObserver = new WorldPoint(observer.x, 0.07f, observer.z);
            float floorReach = VisionSolver.VisibleReach(
                floorObserver, 0.07f, 0f, 10f, new[] { desk });
            var eyeSight = VisionSolver.Evaluate(
                observer, 0f, new WorldPoint(0f, 1.5f, 8f), config, new[] { desk });

            Assert.Less(floorReach, 3f);
            Assert.AreEqual(VisionResultKind.Occluded, eyeSight.Kind);
        }

        [Test]
        public void ReportedBlocker_IsStableRegardlessOfInputOrder()
        {
            var target = new WorldPoint(0f, 1.5f, 8f);
            var a = Wall("a", 0f, 5f);
            var b = Wall("b", 0f, 3f);
            var first = VisionSolver.Evaluate(observer, 0f, target, config, new[] { b, a });
            var second = VisionSolver.Evaluate(observer, 0f, target, config, new[] { a, b });
            Assert.AreEqual("a", first.OccluderId);
            Assert.AreEqual(first.OccluderId, second.OccluderId);
        }

        private static WorldBox Wall(string id, float x, float z, float yaw = 0f) => new WorldBox
        {
            sourceID = id,
            centerX = x,
            centerZ = z,
            width = 4f,
            height = 3f,
            depth = 0.2f,
            yaw = yaw
        };
    }

    public class VisionSystemTests
    {
        [Test]
        public void FixedSecurityCamera_UsesItsOwnPositionAndWideProfile()
        {
            var state = new MissionState { DetectionEnabled = true, CurrentTime = 3f };
            state.Actors[2] = new ActorState
            {
                ActorId = 2, Role = ActorRole.Thief,
                Position = new WorldPoint(0f, 0f, 5f),
                Profile = CharacterProfile.Standard
            };
            state.Cameras["cam"] = new CameraState
            {
                id = "cam", powered = true, currentYaw = 0f,
                range = 6f, fieldOfView = 120f
            };
            state.VisionSources[7] = new VisionSourceState
            {
                sourceId = 7, sourceLabel = "cam",
                kind = VisionSourceKind.SecurityCamera,
                fixedPosition = new WorldPoint(0f, 2.4f, 0f),
                eyeHeight = 2.4f,
                config = VisionProfiles.securityCamera,
                isEnabled = true
            };

            VisionSystem.Tick(state);

            Assert.IsTrue(state.Failure.HasValue);
            Assert.AreEqual("cam", state.Failure.Value.source);
            Assert.AreEqual(3f, state.Failure.Value.time);
        }

        [Test]
        public void CameraSweep_IsOffsetFromAuthoredBaseYaw()
        {
            var state = new MissionState();
            state.Cameras["cam"] = new CameraState
            {
                id = "cam", powered = true, baseYaw = -90f,
                currentYaw = -90f, scanArc = 80f, scanPeriod = 8f
            };

            SecurityCameraSystem.Tick(state, 2f);

            Assert.AreEqual(-50f, state.Cameras["cam"].currentYaw, 0.0001f);
        }

        [Test]
        public void EnabledGuardSeeingThief_ProducesStructuredFailureAtMissionTime()
        {
            var state = CreateVisiblePair();
            state.CurrentTime = 12.4f;
            state.DetectionEnabled = true;

            VisionSystem.Tick(state);

            Assert.IsTrue(state.Failure.HasValue);
            var failure = state.Failure.Value;
            Assert.AreEqual(2, failure.actorId);
            Assert.AreEqual("guard1", failure.source);
            Assert.AreEqual("Seen", failure.reason);
            Assert.AreEqual(12.4f, failure.time);
        }

        [Test]
        public void PlanningGate_PreventsFailureWithoutChangingGeometry()
        {
            var state = CreateVisiblePair();
            state.DetectionEnabled = false;

            VisionSystem.Tick(state);

            Assert.IsFalse(state.Failure.HasValue);
        }

        [Test]
        public void PlanningGate_StillSynchronizesCameraConeFacing()
        {
            var state = new MissionState { DetectionEnabled = false };
            state.Cameras["cam"] = new CameraState
            {
                id = "cam", powered = true, currentYaw = 37f
            };
            state.VisionSources[7] = new VisionSourceState
            {
                sourceId = 7, sourceLabel = "cam",
                kind = VisionSourceKind.SecurityCamera,
                currentFacingYaw = -90f,
                isEnabled = true
            };

            VisionSystem.Tick(state);

            Assert.AreEqual(37f, state.VisionSources[7].currentFacingYaw);
            Assert.IsFalse(state.Failure.HasValue);
        }

        [Test]
        public void SnapshotClone_PreservesVisionDataButOwnsRuntimeSourceState()
        {
            var state = CreateVisiblePair();
            state.DetectionEnabled = true;
            var clone = state.Clone();

            clone.VisionSources[1].isEnabled = false;

            Assert.IsTrue(state.VisionSources[1].isEnabled);
            Assert.IsTrue(clone.DetectionEnabled);
            Assert.AreEqual(state.VisionOccluders.Count, clone.VisionOccluders.Count);
        }

        [Test]
        public void DoorStateTransition_ControlsOneAuthoritativeVisionOccluder()
        {
            var state = new MissionState();
            state.Doors["door"] = new DoorState
            {
                id = "door",
                footprint = new WorldBox
                {
                    sourceID = "door", centerX = 0f, centerZ = 2f,
                    width = 1.6f, depth = 0.12f, height = 2.1f
                },
                isOpen = false
            };
            DoorSystem.SynchronizeVisionOccluder(state, state.Doors["door"]);
            Assert.AreEqual(1, state.VisionOccluders.Count);

            DoorSystem.SetOpen(state, "door", true);
            Assert.IsEmpty(state.VisionOccluders);

            DoorSystem.SetOpen(state, "door", false);
            DoorSystem.SetOpen(state, "door", false);
            Assert.AreEqual(1, state.VisionOccluders.Count,
                "Repeated identical state must not duplicate door geometry.");
        }

        [Test]
        public void DetectionTimestamp_IsIdenticalAt30_60And120RenderFps()
        {
            float at30 = RunUntilDetected(1f / 30f);
            float at60 = RunUntilDetected(1f / 60f);
            float at120 = RunUntilDetected(1f / 120f);

            Assert.AreEqual(at30, at60);
            Assert.AreEqual(at60, at120);
            Assert.AreEqual(1f / 60f, at60, 0.000001f);
        }

        [Test]
        public void DueAction_IsAppliedAfterClockAndBeforeVisionInSameStep()
        {
            var state = CreateVisiblePair();
            state.DetectionEnabled = true;
            var clock = new MissionClock();

            SimulationStep.Tick(state, clock, 1f / 60f, (mission, timestamp) =>
            {
                Assert.AreEqual(1f / 60f, timestamp, 0.000001f);
                var thief = mission.Actors[2];
                thief.Position = new WorldPoint(0f, 0f, -5f);
                mission.Actors[2] = thief;
            });

            Assert.IsFalse(state.Failure.HasValue);
        }

        private static float RunUntilDetected(float renderDelta)
        {
            var state = CreateVisiblePair();
            state.DetectionEnabled = true;
            var clock = new MissionClock();
            var accumulator = new FixedStepAccumulator(1f / 60f);

            for (int frame = 0; frame < 10 && !state.Failure.HasValue; frame++)
            {
                accumulator.Accumulate(renderDelta);
                while (accumulator.TryConsume())
                    SimulationStep.Tick(state, clock, accumulator.FixedDt);
            }
            Assert.IsTrue(state.Failure.HasValue);
            return state.Failure.Value.time;
        }

        private static MissionState CreateVisiblePair()
        {
            var state = new MissionState();
            state.Actors[1] = new ActorState
            {
                ActorId = 1,
                Role = ActorRole.Guard,
                Position = new WorldPoint(0f, 0f, 0f),
                FacingYawDegrees = 0f,
                Profile = CharacterProfile.Standard
            };
            state.Actors[2] = new ActorState
            {
                ActorId = 2,
                Role = ActorRole.Thief,
                Position = new WorldPoint(0f, 0f, 5f),
                FacingYawDegrees = 180f,
                Profile = CharacterProfile.Standard
            };
            state.VisionSources[1] = new VisionSourceState
            {
                sourceId = 1,
                sourceLabel = "guard1",
                actorId = 1,
                kind = VisionSourceKind.GuardActor,
                config = new VisionConfig { range = 10f, fieldOfViewDegrees = 70f },
                eyeHeight = 1.55f,
                isEnabled = true
            };
            return state;
        }
    }
}
