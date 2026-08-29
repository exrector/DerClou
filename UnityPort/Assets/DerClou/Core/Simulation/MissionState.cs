namespace DerClou.Core.Simulation
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;

    /// <summary>
    /// Everything <see cref="Systems.ActorMovementSystem"/> (and, as later U2
    /// steps land, the guard/camera/door/safe systems) needs to know about
    /// one actor. This is the actor's real position and path — the
    /// presentation-side <c>ActorView</c>'s Transform is a read-only mirror
    /// of this, not the other way around (`docs/U2_SIMULATION_DESIGN.md`).
    /// </summary>
    public struct ActorState
    {
        public int ActorId;
        public ActorRole Role;
        public CharacterProfile Profile;
        public WorldPoint Position;
        public float FacingYawDegrees;
        public WorldPoint[] CurrentPath;
        public int PathIndex;
        public bool HasPath;
        public float CurrentSpeed;
        public float TrajectoryCommittedAt;
        public int AvoidancePriority;
        public int RouteRevision;
        // Room/portal dependencies captured when the route is committed.
        // A door event can reject unrelated actors without inspecting their
        // paths; an actor that already passed the portal simply refreshes the
        // revision after its remaining corridor proves legal.
        public string[] PortalDependencies;
        public uint[] PortalDependencyRevisions;
        public bool ManualControl;
        public bool HasAvoidanceRecord;
        public int LastAvoidedActorId;
        public WorldPoint LastAvoidedActorPosition;
        public WorldPoint LastAvoidanceDestination;

        // Dedup guard for `ActorMovementSystem.RequestPath` — without it,
        // a caller that re-requests the same destination every tick (guard
        // patrol in particular) would re-solve A* every single fixed step
        // for a destination that hasn't moved. Lived on `ActorView` itself
        // before step 2b; moved here because it's a fact about the
        // simulation's last routing decision, not a presentation concern.
        public WorldPoint LastRequestedDestination;
        public bool HasRequestedDestination;
    }

    /// <summary>
    /// The gameplay-authoritative state for the current mission. Grew
    /// <see cref="HasLoot"/>/<see cref="MissionComplete"/>/
    /// <see cref="CollectedLootIds"/> in U3 step 3b — mission outcome has to
    /// live here too, not as private `InteractionSystem` fields, or Retry
    /// can't cleanly reset it by restoring a `MissionState` snapshot
    /// (`docs/U3_PLANNING_LOOP_DESIGN.md`).
    /// </summary>
    public class MissionState
    {
        public Dictionary<int, ActorState> Actors = new();
        public Dictionary<int, GuardState> Guards = new();
        public Dictionary<string, CameraState> Cameras = new();
        public Dictionary<string, DoorState> Doors = new();
        public Dictionary<string, SafeState> Safes = new();
        public Dictionary<int, VisionSourceState> VisionSources = new();
        public List<WorldBox> VisionOccluders = new();

        // Reused fixed-step work buffers. Movement, patrol, camera and vision
        // run many times per second; allocating a fresh key list in each
        // system tick creates avoidable GC spikes and battery cost. These
        // buffers are execution machinery, not mission state, so snapshots
        // intentionally start with empty buffers of their own.
        internal readonly List<int> ActorIdScratch = new();
        internal readonly List<int> GuardIdScratch = new();
        internal readonly List<int> VisionSourceIdScratch = new();
        internal readonly List<string> CameraIdScratch = new();

        // Explicit execution gate: planning may preview a moving patrol, but
        // it can never fail the mission before the player presses Execute.
        public bool DetectionEnabled;
        public FailureEvent? Failure;

        public bool HasLoot;
        public bool MissionComplete;
        public HashSet<string> CollectedLootIds = new();

        /// The grid every actor/guard paths against. Pure C# already
        /// (`NavGrid`), so it belongs on the simulation side rather than
        /// behind a separate Unity-side static accessor — one less place
        /// pure-C# systems would otherwise need to reach into `Gameplay.*`
        /// for. Replaces the old `Gameplay.Level.NavigationService`.
        public NavGrid Grid;
        public NavGrid ImmutableBaseGrid;
        public WorldTopology Topology;
        // Runtime service boundary, not serializable mission data. A planning
        // query may use Unity NavMesh through this interface, but the result
        // is copied into the plan/actor state before deterministic execution.
        public ISpatialCorridorProvider SpatialCorridors;

        /// Mirrors `MissionClock.CurrentTime`, set once per fixed step by
        /// `SimulationStep.Tick` before running any system — lets systems
        /// (`GuardPatrolSystem` in particular, for wait-duration checks)
        /// take only `MissionState`, not a separate clock reference.
        public float CurrentTime;

        /// Deep copy — the one primitive U2 owes U3's future snapshot/reset
        /// (`docs/U2_SIMULATION_DESIGN.md`). Nothing in U2 calls this yet.
        /// `Grid` and each `GuardState.route` are shared by reference, not
        /// deep-cloned — both are authored/static level data, never mutated
        /// at runtime, so cloning them would only cost memory for no benefit.
        public MissionState Clone()
        {
            var clone = new MissionState
            {
                Grid = Grid?.Clone(),
                ImmutableBaseGrid = ImmutableBaseGrid,
                Topology = Topology?.Clone(),
                SpatialCorridors = SpatialCorridors,
                CurrentTime = CurrentTime,
                HasLoot = HasLoot,
                MissionComplete = MissionComplete,
                DetectionEnabled = DetectionEnabled,
                Failure = Failure,
                VisionOccluders = new List<WorldBox>(VisionOccluders),
                CollectedLootIds = new HashSet<string>(CollectedLootIds)
            };
            foreach (var kv in Actors)
            {
                var copy = kv.Value;
                copy.CurrentPath = kv.Value.CurrentPath != null
                    ? (WorldPoint[])kv.Value.CurrentPath.Clone()
                    : null;
                copy.PortalDependencies = kv.Value.PortalDependencies != null
                    ? (string[])kv.Value.PortalDependencies.Clone()
                    : null;
                copy.PortalDependencyRevisions = kv.Value.PortalDependencyRevisions != null
                    ? (uint[])kv.Value.PortalDependencyRevisions.Clone()
                    : null;
                clone.Actors[kv.Key] = copy;
            }
            foreach (var kv in Guards)
            {
                clone.Guards[kv.Key] = new GuardState
                {
                    actorId = kv.Value.actorId,
                    route = kv.Value.route,
                    currentNodeIndex = kv.Value.currentNodeIndex,
                    nodeArrivalTime = kv.Value.nodeArrivalTime,
                    state = kv.Value.state,
                    isAlerted = kv.Value.isAlerted,
                    alertLevel = kv.Value.alertLevel
                };
            }
            foreach (var kv in VisionSources)
            {
                clone.VisionSources[kv.Key] = new VisionSourceState
                {
                    sourceId = kv.Value.sourceId,
                    sourceLabel = kv.Value.sourceLabel,
                    actorId = kv.Value.actorId,
                    kind = kv.Value.kind,
                    config = kv.Value.config,
                    fixedPosition = kv.Value.fixedPosition,
                    eyeHeight = kv.Value.eyeHeight,
                    currentFacingYaw = kv.Value.currentFacingYaw,
                    isEnabled = kv.Value.isEnabled
                };
            }
            foreach (var kv in Cameras)
            {
                clone.Cameras[kv.Key] = new CameraState
                {
                    id = kv.Value.id,
                    range = kv.Value.range,
                    fieldOfView = kv.Value.fieldOfView,
                    mountHeight = kv.Value.mountHeight,
                    scanArc = kv.Value.scanArc,
                    scanPeriod = kv.Value.scanPeriod,
                    baseYaw = kv.Value.baseYaw,
                    powered = kv.Value.powered,
                    currentYaw = kv.Value.currentYaw,
                    scanPhase = kv.Value.scanPhase
                };
            }
            foreach (var kv in Doors)
            {
                clone.Doors[kv.Key] = new DoorState
                {
                    id = kv.Value.id,
                    footprint = kv.Value.footprint,
                    hingeSide = kv.Value.hingeSide,
                    openAngleDegrees = kv.Value.openAngleDegrees,
                    isOpen = kv.Value.isOpen,
                    openProgress = kv.Value.openProgress,
                    openDurationSeconds = kv.Value.openDurationSeconds,
                    closeDurationSeconds = kv.Value.closeDurationSeconds,
                    isLocked = kv.Value.isLocked,
                    lockDifficulty = kv.Value.lockDifficulty
                };
            }
            foreach (var kv in Safes)
            {
                clone.Safes[kv.Key] = new SafeState
                {
                    id = kv.Value.id,
                    position = kv.Value.position,
                    isLocked = kv.Value.isLocked,
                    difficulty = kv.Value.difficulty,
                    crackProgress = kv.Value.crackProgress,
                    isOpen = kv.Value.isOpen,
                    crackDurationSeconds = kv.Value.crackDurationSeconds,
                    isBeingCracked = kv.Value.isBeingCracked,
                    crackingActorId = kv.Value.crackingActorId,
                    containedLootIds = new List<string>(kv.Value.containedLootIds)
                };
            }
            return clone;
        }
    }
}
