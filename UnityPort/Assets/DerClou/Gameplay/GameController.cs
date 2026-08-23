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

            // Move happens immediately — this slice keeps the world live
            // during "planning" (see `SetPhase`'s comment) rather than
            // waiting for a commit/execute step that doesn't exist yet.
            // Still record it into the plan so that infrastructure isn't
            // dead code once `TickExecution` actually replays plans.
            inputManager.SelectedActor.SetDestination(worldPos);
            QueueMoveAction(inputManager.SelectedActor, worldPos);
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

        private void QueueMoveAction(ActorView actor, Vector3 targetPos)
        {
            var wp = new WorldPoint { x = targetPos.x, y = 0, z = targetPos.z };
            var action = new PlanAction
            {
                type = PlanActionType.MoveTo,
                actorId = actor.ActorId,
                targetPos = wp,
                earliestStart = missionClock.CurrentTime,
                duration = 0f // computed from path
            };
            currentPlan.GetOrCreate(actor.ActorId).AddAction(action);
            currentPlan.RecalculateDuration();
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