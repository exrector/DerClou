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
        public GuardPatrolSystem patrolSystem;
        public InteractionSystem interactionSystem;

        [Header("Data")]
        public PropCatalog catalog;
        public LevelBlueprint blueprint;

        [Header("Planning")]
        public MissionPlan currentPlan;
        public PlanActionType pendingActionType;
        public IActionDurationProvider durationProvider = new DefaultDurationProvider();

        public GamePhase CurrentPhase { get; private set; } = GamePhase.Recon;

        private Dictionary<int, ActorEntity> actors = new();
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

            // Wire up patrol system
            if (patrolSystem != null) patrolSystem.missionClock = missionClock;

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
            // the side effect of freezing `GuardPatrolSystem` (it checks
            // `missionClock.IsPaused`) before the player ever sees it move.
            // Keep the world live for this minimum slice.
            missionClock.Resume();
        }

        private void Update()
        {
            float dt = Time.deltaTime;
            missionClock.Tick(dt);
            fixedStep.Accumulate(dt);

            while (fixedStep.TryConsume())
            {
                FixedTick(fixedStep.FixedDt);
            }

            if (isExecuting)
            {
                TickExecution(dt);
            }
        }

        private void FixedTick(float dt)
        {
            // Fixed-step systems: patrol, physics, etc.
            if (patrolSystem != null) patrolSystem.enabled = true; // runs in its own Update
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

        private void OnActorSelected(ActorEntity actor)
        {
            if (CurrentPhase == GamePhase.Planning)
            {
                // Show actor info / action queue
            }
        }

        private void OnFloorClicked(Vector3 worldPos)
        {
            if (CurrentPhase != GamePhase.Planning || inputManager.SelectedActor == null) return;

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

        private void QueueMoveAction(ActorEntity actor, Vector3 targetPos)
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