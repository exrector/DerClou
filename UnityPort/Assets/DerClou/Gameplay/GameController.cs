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
        private bool wasMissionComplete;

        private void Awake()
        {
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
        }

        private void Update()
        {
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
                SimulationStep.Tick(SimulationService.Current, missionClock, fixedStep.FixedDt);
            }

            if (CurrentPhase == GamePhase.Execution)
            {
                TickExecution();
            }
        }

        private void TickExecution()
        {
            var state = SimulationService.Current;
            planExecutor.Tick(state, missionClock.CurrentTime);

            if (planExecutor.LastFailure is FailureEvent failure)
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
            cursor = new PlanCursor { Position = position, Time = 0f };
            planCursors[actorId] = cursor;
            return cursor;
        }

        private void OnInteractableClicked(Interactable interactable)
        {
            if (CurrentPhase != GamePhase.Planning || inputManager.SelectedActor == null) return;

            // U3 step 3b: resolving "what does tapping this mean" is
            // Gameplay-side work (it inspects Unity components — DoorView,
            // SafeView — and MonoBehaviour config) that pure-C# PlanBuilder
            // has no way to do itself. `PlanBuilder.QueueInteract` only
            // takes the already-resolved result.
            PlanActionType actionType;
            if (interactable.GetComponent<DoorView>() != null) actionType = PlanActionType.OpenDoor;
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
            var targetPos = new WorldPoint(interactable.transform.position.x, 0, interactable.transform.position.z);
            // The prop's own config already carries every duration key
            // DefaultDurationProvider reads (hackDuration, crackSafeDuration,
            // …) plus the panel→camera link (controlsCameraId) and the
            // loot→safe gate (requiresSafeId) — reusing it directly resolves
            // both at planning time instead of needing PlanExecutor to look
            // anything else up later.
            var parameters = new Dictionary<string, LevelValue>(interactable.RuntimeState.config);

            PlanBuilder.QueueInteract(currentPlan, SimulationService.Current, actor.ActorId, ref cursor,
                targetPos, actionType, interactable.InteractableId, parameters, durationProvider);
            planCursors[actor.ActorId] = cursor;

            Debug.Log($"[GameController] queued {actionType} on {interactable.InteractableId} for actor {actor.ActorId} " +
                $"({currentPlan.GetOrCreate(actor.ActorId).actions.Count} actions queued, cursor time={cursor.Time:0.0}s)");
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
            missionClock.Reset();
            wasMissionComplete = false;
            planExecutor.Begin(currentPlan);

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
            missionClock.Reset();
            wasMissionComplete = false;
            RebuildCursorsFromPlan();

            SetPhase(GamePhase.Planning);
            // Same reasoning as `Start()`: keep guard patrol visibly live
            // during Planning rather than frozen on the snapshot.
            missionClock.Resume();
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
                planCursors[kv.Key] = actions.Count > 0
                    ? new PlanCursor { Position = actions[^1].targetPos, Time = actions[^1].EndTime }
                    : GetCursor(kv.Key);
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