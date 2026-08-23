namespace DerClou.Gameplay
{
    using DerClou.Core.Data;
    using DerClou.Core.Time;
    using DerClou.Core.Planning;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Level;
    using DerClou.Gameplay.Input;
    using DerClou.Gameplay.Camera;
    using DerClou.Gameplay.Interaction;
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
        public InteractionSystem interactionSystem;

        [Header("Data")]
        public PropCatalog catalog;
        public LevelBlueprint blueprint;

        [Header("Planning")]
        public MissionPlan currentPlan;
        public PlanActionType pendingActionType;
        public IActionDurationProvider durationProvider = new DefaultDurationProvider();

        public GamePhase CurrentPhase { get; private set; } = GamePhase.Recon;

        private Dictionary<int, ActorView> actors = new();
        private bool isExecuting = false;

        // U3 (`docs/U3_PLANNING_LOOP_DESIGN.md`): where each actor's next
        // planned action starts from. Lazily seeded from the actor's live
        // position the first time it's queued — valid because Planning taps
        // never move the actor, so "live position" and "start of Planning
        // position" are the same thing until 3c (Retry) needs to rebuild
        // this from a preserved plan instead.
        private Dictionary<int, PlanCursor> planCursors = new();

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

            if (interactionSystem != null) interactionSystem.OnMissionComplete += HandleMissionComplete;

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

            if (isExecuting)
            {
                TickExecution(dt);
            }
        }

        private void TickExecution(float dt)
        {
            // Execute current plan
            if (currentPlan != null)
            {
                float t = missionClock.CurrentTime;
                // TODO: execute actions based on time
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
            interactionSystem.RequestInteract(inputManager.SelectedActor, interactable);
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
            SetPhase(GamePhase.Execution);
            isExecuting = true;
            missionClock.Resume();
            // TODO: start plan execution
        }

        public void StopExecution()
        {
            if (CurrentPhase != GamePhase.Execution) return;
            SetPhase(GamePhase.Planning);
            isExecuting = false;
            missionClock.Pause();
            missionClock.Reset();
            currentPlan = new MissionPlan();
            // Reset actor positions
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
            if (interactionSystem != null) interactionSystem.OnMissionComplete -= HandleMissionComplete;
        }
    }
}