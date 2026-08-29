namespace DerClou.Gameplay
{
    using DerClou.Core.Data;
    using DerClou.Core.Time;
    using DerClou.Core.Planning;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Level;
    using DerClou.Gameplay.Input;
    using DerClou.Gameplay.Camera;
    using DerClou.Gameplay.Props;
    using DerClou.Gameplay.Simulation;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using UnityEngine;
    using System.Collections.Generic;

    public enum GamePhase { Recon, CrewLoadout, Planning, Execution, Result }

    public class GameController : MonoBehaviour
    {
        [Header("Core Systems")]
        public MissionClock missionClock;
        public FixedStepAccumulator fixedStep;
        public LevelBuilder levelBuilder;
        public InputManager inputManager;
        public TacticalCamera tacticalCamera;
        public GuardView patrolSystem;

        [Header("Data")]
        public PropCatalog catalog;
        public LevelBlueprint blueprint;

        [Header("Planning")]
        public MissionPlan currentPlan;
        public PlanActionType pendingActionType;
        public IActionDurationProvider durationProvider = new DefaultDurationProvider();

        public GamePhase CurrentPhase { get; private set; } = GamePhase.Recon;
        public int PlannedActionCount
        {
            get
            {
                int count = 0;
                if (currentPlan == null) return count;
                foreach (var actorPlan in currentPlan.actorPlans.Values) count += actorPlan.actions.Count;
                return count;
            }
        }
        public FailureEvent? CurrentFailure => SimulationService.Current?.Failure;
        public bool DeveloperSandboxMode { get; set; }

        // U3 (`docs/U3_PLANNING_LOOP_DESIGN.md`): where each actor's next
        // planned action starts from. Lazily seeded from the actor's live
        // position the first time it's queued — valid because Planning taps
        // never move the actor, so "live position" and "start of Planning
        // position" are the same thing until 3c (Retry) needs to rebuild
        // this from a preserved plan instead.
        private Dictionary<int, PlanCursor> planCursors = new();

        // U3 step 3b: the state right after the level finished building,
        // before any Planning tap could have touched it. Execute and every
        // Retry restore from this same one — Planning taps never mutate
        // MissionState (3a/3b both), so it never needs retaking.
        private MissionState initialSnapshot;
        private readonly PlanExecutor planExecutor = new();
        private readonly PlanExecutor sandboxCommandExecutor = new();
        private MissionPlan sandboxCommandPlan;
        private float sandboxCommandStartedAt;
        private bool sandboxCommandActive;
        private bool wasMissionComplete;

        private void Awake()
        {
            EnsureRuntimeObjects();
        }

        private void OnEnable() => EnsureRuntimeObjects();

        private void EnsureRuntimeObjects()
        {
            // These are pure C# runtime objects, not UnityEngine.Objects, so
            // Play Mode domain reload cannot serialize them. Recreate the
            // deterministic wrappers before the first post-reload frame.
            if (missionClock == null) missionClock = new MissionClock();
            if (fixedStep == null) fixedStep = new FixedStepAccumulator();
            if (currentPlan == null) currentPlan = new MissionPlan();
        }

        private void Start()
        {
            if (catalog == null) catalog = PropCatalog.Standard;
            // Not `levelBuilder.Build(...)` again here: `GameBootstrap.Awake`
            // (which runs before any `Start`) already built the level and
            // assigned this `blueprint`, so this re-ran the exact same build
            // a second time on every session — including a second NavMesh
            // bake stacked on top of the first one.

            // Subscribe to input events
            if (inputManager != null)
            {
                inputManager.OnActorSelected += OnActorSelected;
                inputManager.OnFloorClicked += OnFloorClicked;
                inputManager.OnInteractableClicked += OnInteractableClicked;
            }

            // U3 step 3b: the one-time snapshot Execute/Retry always restore
            // from. Must happen here, not earlier — `GameBootstrap.Awake`
            // (which builds the level and populates `SimulationService.Current`)
            // runs before any `Start`, so this is the first point a fully
            // built `MissionState` is guaranteed to exist.
            initialSnapshot = SimulationService.Current.Clone();

            SetPhase(GamePhase.Planning);
            // `SetPhase(Planning)` pauses `missionClock`, which is what a
            // real planning UI should do once one exists — for now it has
            // the side effect of freezing `GuardView` (it checks
            // `missionClock.IsPaused`) before the player ever sees it move.
            // Keep the world live for this minimum slice.
            missionClock.Resume();
            if (DeveloperSandboxMode) RefreshSandboxNavigation();
            if (!inputManager.SelectDefaultPlayerActor())
                Debug.LogWarning("[GameController] No player-controlled thief exists to auto-select.");
        }

        private void Update()
        {
            EnsureRuntimeObjects();
            float dt = Time.deltaTime;
            fixedStep.Accumulate(dt);

            // U2 step 2a (`docs/U2_SIMULATION_DESIGN.md`): `missionClock` used
            // to tick here directly off `Time.deltaTime` — a variable,
            // render-frame-rate delta — which was the actual reason the
            // project wasn't deterministic yet despite already having a
            // clock and an accumulator. `SimulationStep.Tick` now ticks the
            // clock itself, once per fixed step, and runs the (so far: one)
            // pure-C# simulation system against `SimulationService.Current`.
            while (fixedStep.TryConsume())
            {
                if (CurrentPhase == GamePhase.Execution)
                {
                    // SimulationStep advances the clock, dispatches due plan
                    // actions, then runs movement/vision in one fixed order.
                    // None of these decisions are render-frame-bound.
                    SimulationStep.Tick(
                        SimulationService.Current,
                        missionClock,
                        fixedStep.FixedDt,
                        DispatchPlanActions);
                }
                else
                {
                    if (DeveloperSandboxMode && sandboxCommandActive)
                        sandboxCommandExecutor.Tick(
                            SimulationService.Current,
                            SimulationService.Current.CurrentTime - sandboxCommandStartedAt);
                    SimulationStep.Tick(SimulationService.Current, missionClock, fixedStep.FixedDt);
                }
            }

            if (CurrentPhase == GamePhase.Execution)
            {
                TickExecution();
            }
            else if (DeveloperSandboxMode && sandboxCommandActive
                && sandboxCommandPlan != null
                && SimulationService.Current.CurrentTime - sandboxCommandStartedAt
                    > sandboxCommandPlan.estimatedDuration + 0.5f)
            {
                sandboxCommandActive = false;
            }
        }

        private void TickExecution()
        {
            var state = SimulationService.Current;
            if (state.Failure is FailureEvent failure)
            {
                Debug.Log($"=== ПРОВАЛ: actor {failure.actorId}, {failure.source}/{failure.reason}, t={failure.time:0.0}s ===");
                missionClock.Pause();
                CurrentPhase = GamePhase.Result;
                inputManager.SetMode(InputMode.Inspecting);
                return;
            }

            if (state.MissionComplete && !wasMissionComplete)
            {
                wasMissionComplete = true;
                HandleMissionComplete();
            }
        }

        private void DispatchPlanActions(MissionState state, float currentTime) =>
            planExecutor.Tick(state, currentTime);

        private void OnActorSelected(ActorView actor)
        {
            if (CurrentPhase == GamePhase.Planning)
            {
                // Show actor info / action queue
            }
        }

        private void OnFloorClicked(Vector3 worldPos)
        {
            if (CurrentPhase != GamePhase.Planning || inputManager.SelectedActor == null)
            {
                Debug.Log($"[GameController] floor tap ignored (phase={CurrentPhase}, selected={inputManager.SelectedActor != null})");
                return;
            }

            if (DeveloperSandboxMode)
            {
                var selected = inputManager.SelectedActor;
                var state = SimulationService.Current;
                if (state.Actors.TryGetValue(selected.ActorId, out var actorState))
                {
                    actorState.ManualControl = true;
                    state.Actors[selected.ActorId] = actorState;
                }
                else return;
                var sandboxCursor = new PlanCursor
                {
                    Position = state.Actors[selected.ActorId].Position,
                    Time = 0f,
                    FacingYawDegrees = state.Actors[selected.ActorId].FacingYawDegrees,
                    HasFacing = true
                };
                var command = new MissionPlan();
                if (!PlanBuilder.QueueMove(command, state, selected.ActorId, ref sandboxCursor,
                        new WorldPoint(worldPos.x, 0f, worldPos.z)))
                {
                    Debug.LogWarning($"[Sandbox] no smart route actor={selected.ActorId} " +
                                     $"({worldPos.x:0.00}, {worldPos.z:0.00})");
                    return;
                }
                sandboxCommandPlan = command;
                sandboxCommandExecutor.Begin(command);
                sandboxCommandStartedAt = state.CurrentTime;
                sandboxCommandActive = true;
                sandboxCommandExecutor.Tick(state, 0f);
                Debug.Log($"[Sandbox] smart command actor={selected.ActorId}: " +
                          $"{command.GetOrCreate(selected.ActorId).actions.Count} actions, " +
                          $"eta={command.estimatedDuration:0.00}s, target=({worldPos.x:0.00}, {worldPos.z:0.00})");
                return;
            }

            // U3 step 3a: the actor no longer moves on a Planning tap — this
            // only appends a MoveTo to the plan. Nothing actually happens
            // until StartExecution replays it (step 3b).
            var actor = inputManager.SelectedActor;
            var cursor = GetCursor(actor.ActorId);
            PlanBuilder.QueueMove(currentPlan, SimulationService.Current, actor.ActorId, ref cursor,
                new WorldPoint(worldPos.x, 0, worldPos.z));
            planCursors[actor.ActorId] = cursor;

            Debug.Log($"[GameController] queued MoveTo for actor {actor.ActorId} " +
                $"({currentPlan.GetOrCreate(actor.ActorId).actions.Count} actions queued, cursor time={cursor.Time:0.0}s)");
        }

        private PlanCursor GetCursor(int actorId)
        {
            if (planCursors.TryGetValue(actorId, out var cursor)) return cursor;

            var state = SimulationService.Current;
            var position = state != null && state.Actors.TryGetValue(actorId, out var a)
                ? a.Position
                : default;
            cursor = new PlanCursor
            {
                Position = position,
                Time = 0f,
                FacingYawDegrees = state != null && state.Actors.TryGetValue(actorId, out var facingActor)
                    ? facingActor.FacingYawDegrees : 0f,
                HasFacing = true
            };
            planCursors[actorId] = cursor;
            return cursor;
        }

        private void OnInteractableClicked(Interactable interactable)
        {
            if (CurrentPhase != GamePhase.Planning || inputManager.SelectedActor == null) return;

            if (DeveloperSandboxMode)
            {
                var door = interactable.GetComponentInParent<DoorView>();
                var state = SimulationService.Current;
                if (door != null && state.Doors.TryGetValue(door.DoorId, out var doorState))
                {
                    DoorSystem.SetOpen(state, door.DoorId, !doorState.isOpen);
                    RefreshSandboxNavigation(door.DoorId);
                    Debug.Log($"[Sandbox] door {door.DoorId} target open={!doorState.isOpen}");
                    return;
                }

                if (interactable.Supports(InteractionKind.MakeNoise))
                {
                    float radius = interactable.RuntimeState.config.TryGetValue("noiseRadius", out var r)
                        && r.type == LevelValue.Type.Float ? r.floatValue : 6f;
                    var pos = new WorldPoint(
                        interactable.transform.position.x, 0f, interactable.transform.position.z);
                    StimulusSystem.EmitNoise(state, pos, radius);
                    int alerted = 0;
                    foreach (var g in state.Guards.Values) if (g.isAlerted) alerted++;
                    Debug.Log($"[Sandbox] noise emitted at ({pos.x:0.0},{pos.z:0.0}) radius={radius}, guards alerted={alerted}");
                }
                return;
            }

            // U3 step 3b: resolving "what does tapping this mean" is
            // Gameplay-side work (it inspects Unity components — DoorView,
            // SafeView — and MonoBehaviour config) that pure-C# PlanBuilder
            // has no way to do itself. `PlanBuilder.QueueInteract` only
            // takes the already-resolved result.
            PlanActionType actionType;
            if (interactable.GetComponentInParent<DoorView>() != null) actionType = PlanActionType.OpenDoor;
            else if (interactable.GetComponent<SafeView>() != null) actionType = PlanActionType.CrackSafe;
            else if (interactable.Supports(InteractionKind.ToggleSwitch) || interactable.Supports(InteractionKind.Hack)) actionType = PlanActionType.Hack;
            else if (interactable.Supports(InteractionKind.TakeLoot)) actionType = PlanActionType.TakeLoot;
            else if (interactable.Supports(InteractionKind.Extract)) actionType = PlanActionType.Extract;
            else
            {
                Debug.Log($"[GameController] {interactable.InteractableId}: нечего планировать.");
                return;
            }

            var actor = inputManager.SelectedActor;
            var cursor = GetCursor(actor.ActorId);
            var collider = interactable.GetComponentInChildren<Collider>();
            var colliderBounds = collider != null ? collider.bounds : new Bounds(interactable.transform.position, Vector3.one * 0.2f);
            var targetBounds = new WorldBox
            {
                sourceID = interactable.InteractableId,
                centerX = colliderBounds.center.x,
                centerZ = colliderBounds.center.z,
                width = colliderBounds.size.x,
                depth = colliderBounds.size.z,
                yaw = interactable.transform.eulerAngles.y
            };
            // The prop's own config already carries every duration key
            // DefaultDurationProvider reads (hackDuration, crackSafeDuration,
            // …) plus the panel→camera link (controlsCameraId) and the
            // loot→safe gate (requiresSafeId) — reusing it directly resolves
            // both at planning time instead of needing PlanExecutor to look
            // anything else up later.
            var parameters = new Dictionary<string, LevelValue>(interactable.RuntimeState.config);

            PlanBuilder.QueueInteract(currentPlan, SimulationService.Current, actor.ActorId, ref cursor,
                targetBounds, actionType, interactable.InteractableId, parameters, durationProvider);
            planCursors[actor.ActorId] = cursor;

            Debug.Log($"[GameController] queued {actionType} on {interactable.InteractableId} for actor {actor.ActorId} " +
                $"({currentPlan.GetOrCreate(actor.ActorId).actions.Count} actions queued, cursor time={cursor.Time:0.0}s)");
        }

        /// Sandbox HUD button: fires the first MakeNoise prop's own
        /// configured radius, same as tapping it in the world — a reachable
        /// alternative for the owner to a small colored cube in a 3D scene.
        public void TestEmitSandboxNoise()
        {
            if (!DeveloperSandboxMode) return;
            var state = SimulationService.Current;
            var all = FindObjectsByType<Interactable>(FindObjectsSortMode.None);
            foreach (var i in all)
            {
                if (!i.Supports(InteractionKind.MakeNoise)) continue;
                float radius = i.RuntimeState.config.TryGetValue("noiseRadius", out var r)
                    && r.type == LevelValue.Type.Float ? r.floatValue : 6f;
                var pos = new WorldPoint(i.transform.position.x, 0f, i.transform.position.z);
                StimulusSystem.EmitNoise(state, pos, radius);
                Debug.Log($"[Sandbox] HUD test noise at ({pos.x:0.0},{pos.z:0.0}) radius={radius}");
                return;
            }
        }

        /// Sandbox HUD button: forces the first still-locked safe open,
        /// firing the same noise event a real crack does. See
        /// SafeSystem.ForceOpenForTest for why this skips the real
        /// duration/proximity requirement.
        public void TestCrackSandboxSafe()
        {
            if (!DeveloperSandboxMode) return;
            var state = SimulationService.Current;
            foreach (var id in state.Safes.Keys)
            {
                if (state.Safes[id].isOpen) continue;
                SafeSystem.ForceOpenForTest(state, id);
                Debug.Log($"[Sandbox] HUD forced safe '{id}' open");
                return;
            }
        }

        private void RefreshSandboxNavigation(string changedDoorId = null)
        {
            if (!DeveloperSandboxMode || blueprint == null || catalog == null || SimulationService.Current == null) return;
            var state = SimulationService.Current;
            if (state.Grid == null || state.ImmutableBaseGrid == null) return;
            // Initial sandbox construction still synchronizes every door.
            // Individual runtime changes are already handled centrally by
            // DoorSystem.SetOpen and must not be applied/published twice.
            if (changedDoorId == null) foreach (var prop in blueprint.props)
            {
                if (!state.Doors.TryGetValue(prop.id, out var door)) continue;
                state.Grid.ApplyLocalBoxOccupancy(
                    state.ImmutableBaseGrid,
                    prop.box,
                    !door.isOpen,
                    CharacterProfile.Standard.Radius + 0.08f);
            }

            // Opening/closing the shared door only invalidates a route whose
            // remaining corridor actually crosses that doorway.
            var ids = new List<int>(state.Actors.Keys);
            foreach (var id in ids)
            {
                var actor = state.Actors[id];
                if (!actor.HasPath || actor.CurrentPath == null) continue;
                bool dependencyChanged = changedDoorId == null;
                if (!dependencyChanged && actor.PortalDependencies != null
                    && actor.PortalDependencyRevisions != null)
                {
                    for (int i = 0; i < actor.PortalDependencies.Length; i++)
                    {
                        if (state.Topology.rooms.GetPortalRevision(actor.PortalDependencies[i])
                            == actor.PortalDependencyRevisions[i]) continue;
                        dependencyChanged = true;
                        break;
                    }
                }
                if (!dependencyChanged) continue;
                var previous = actor.Position;
                bool invalid = false;
                for (int i = actor.PathIndex; i < actor.CurrentPath.Length; i++)
                {
                    if (!DerClou.Core.Navigation.PathFinder.HasLineOfSight(state.Grid, previous, actor.CurrentPath[i]))
                    { invalid = true; break; }
                    previous = actor.CurrentPath[i];
                }
                if (invalid)
                    DerClou.Core.Systems.ActorMovementSystem.RequestPath(state, id, actor.LastRequestedDestination, true);
                else if (actor.PortalDependencies != null)
                {
                    for (int i = 0; i < actor.PortalDependencies.Length; i++)
                        actor.PortalDependencyRevisions[i] = state.Topology.rooms.GetPortalRevision(actor.PortalDependencies[i]);
                    state.Actors[id] = actor;
                }
            }
        }

        private void HandleMissionComplete()
        {
            missionClock.Pause();
            // Reusing `Inspecting` (otherwise-unused input mode) stops
            // `InputManager.Update`'s early-return gate from processing any
            // further clicks — the simplest way to freeze the level on
            // success without a dedicated `GamePhase.Result` UI yet.
            inputManager.SetMode(InputMode.Inspecting);
            CurrentPhase = GamePhase.Result;
        }

        public void StartExecution()
        {
            if (CurrentPhase != GamePhase.Planning) return;

            RestoreSnapshot();
            SimulationService.Current.DetectionEnabled = true;
            missionClock.Reset();
            wasMissionComplete = false;
            planExecutor.Begin(currentPlan);
            // Time-zero actions exist before the first simulation step. Later
            // actions are dispatched by SimulationStep after advancing its
            // deterministic clock and before movement/vision.
            planExecutor.Tick(SimulationService.Current, 0f);

            SetPhase(GamePhase.Execution);
            missionClock.Resume();
        }

        /// Retry, per U3 step 3c (`docs/U3_PLANNING_LOOP_DESIGN.md`): the
        /// plan is deliberately *not* cleared — that is the entire point of
        /// Retry versus starting over. Cursors rebuild from the plan's own
        /// recorded end-state so further Planning taps append correctly
        /// instead of replanning from the actor's (now snapshot-restored)
        /// spawn position.
        public void StopExecution()
        {
            if (CurrentPhase != GamePhase.Execution && CurrentPhase != GamePhase.Result) return;

            RestoreSnapshot();
            SimulationService.Current.DetectionEnabled = false;
            missionClock.Reset();
            wasMissionComplete = false;
            RebuildCursorsFromPlan();

            SetPhase(GamePhase.Planning);
            // Same reasoning as `Start()`: keep guard patrol visibly live
            // during Planning rather than frozen on the snapshot.
            missionClock.Resume();
        }

        public void ClearPlan()
        {
            if (CurrentPhase != GamePhase.Planning || currentPlan == null) return;
            currentPlan.actorPlans.Clear();
            currentPlan.RecalculateDuration();
            planCursors.Clear();
        }

        public void RetryExecution()
        {
            if (CurrentPhase != GamePhase.Result && CurrentPhase != GamePhase.Execution) return;
            StopExecution();
            StartExecution();
        }

        private void RestoreSnapshot()
        {
            SimulationService.Current = initialSnapshot.Clone();
        }

        private void RebuildCursorsFromPlan()
        {
            planCursors.Clear();
            foreach (var kv in currentPlan.actorPlans)
            {
                var actions = kv.Value.actions;
                if (actions.Count == 0)
                {
                    planCursors[kv.Key] = GetCursor(kv.Key);
                    continue;
                }
                float facing = 0f;
                bool hasFacing = false;
                for (int i = actions.Count - 1; i >= 0; i--)
                {
                    var trajectory = actions[i].frozenTrajectory;
                    if (trajectory == null || trajectory.Length == 0) continue;
                    var from = i > 0 ? actions[i - 1].targetPos
                        : initialSnapshot.Actors[kv.Key].Position;
                    var last = trajectory[^1];
                    var previous = trajectory.Length > 1 ? trajectory[^2] : from;
                    float dx = last.x - previous.x, dz = last.z - previous.z;
                    if (dx * dx + dz * dz > 0.000001f)
                    {
                        facing = System.MathF.Atan2(dx, dz) * 180f / System.MathF.PI;
                        hasFacing = true;
                    }
                    break;
                }
                planCursors[kv.Key] = new PlanCursor
                {
                    Position = actions[^1].targetPos,
                    Time = actions[^1].EndTime,
                    FacingYawDegrees = facing,
                    HasFacing = hasFacing
                };
            }
        }

        public void SetPhase(GamePhase phase)
        {
            CurrentPhase = phase;
            switch (phase)
            {
                case GamePhase.Planning:
                    inputManager.SetMode(InputMode.Planning);
                    missionClock.Pause();
                    break;
                case GamePhase.Execution:
                    inputManager.SetMode(InputMode.Execution);
                    missionClock.Resume();
                    break;
            }
        }

        private void OnDestroy()
        {
            if (inputManager != null)
            {
                inputManager.OnActorSelected -= OnActorSelected;
                inputManager.OnFloorClicked -= OnFloorClicked;
                inputManager.OnInteractableClicked -= OnInteractableClicked;
            }
        }
    }
}
