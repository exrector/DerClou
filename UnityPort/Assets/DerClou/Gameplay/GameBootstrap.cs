namespace DerClou.Gameplay
{
    using DerClou.Core.Data;
    using DerClou.Core.Planning;
    using DerClou.Core.Time;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Camera;
    using DerClou.Gameplay.Input;
    using DerClou.Gameplay.Interaction;
    using DerClou.Gameplay.Level;
    using DerClou.Gameplay.Simulation;
    using DerClou.Core.Simulation;
    using UnityEngine;

    /// <summary>
    /// Bootstrap component - attach to an empty GameObject in the first scene.
    /// Auto-wires all core systems.
    /// </summary>
    public class GameBootstrap : MonoBehaviour
    {
        [Header("Auto-generated at runtime")]
        public GameController gameController;
        public MissionClock missionClock;
        public FixedStepAccumulator fixedStep;
        public LevelBuilder levelBuilder;
        public InputManager inputManager;
        public TacticalCamera tacticalCamera;
        public GuardView patrolSystem;
        public InteractionSystem interactionSystem;
        public Level01Builder level01Builder;

        [Header("Data Assets")]
        public PropCatalog catalog;
        public LevelBlueprint blueprint;

        private void Awake()
        {
            // Ensure singleton-like bootstrap
            if (FindObjectsOfType<GameBootstrap>().Length > 1)
            {
                Destroy(gameObject);
                return;
            }
            // No `DontDestroyOnLoad`: nothing here switches scenes yet, and
            // it was actively confusing to work with — it moves this object
            // and everything parented under it (the camera included) into a
            // separate, hidden "DontDestroyOnLoad" pseudo-scene that neither
            // the Hierarchy window nor scene-scoped tooling shows by default,
            // while anything spawned without an explicit parent (the level
            // geometry) stayed behind in the normal scene — so the bootstrap
            // and the level it built ended up split across two places that
            // don't appear together anywhere.

            CreateCoreSystems();
            GenerateLevel();
            WireReferences();
        }

        private void CreateCoreSystems()
        {
            missionClock = new MissionClock();
            fixedStep = new FixedStepAccumulator();
            currentPlan = new MissionPlan();

            // Create child objects for each system
            var clockGO = new GameObject("MissionClock");
            clockGO.transform.SetParent(transform);

            var levelGO = new GameObject("LevelBuilder");
            levelGO.transform.SetParent(transform);
            levelBuilder = levelGO.AddComponent<LevelBuilder>();

            var inputGO = new GameObject("InputManager");
            inputGO.transform.SetParent(transform);
            inputManager = inputGO.AddComponent<InputManager>();

            var camGO = new GameObject("TacticalCamera");
            camGO.transform.SetParent(transform);
            tacticalCamera = camGO.AddComponent<TacticalCamera>();
            // Fully qualified: `using DerClou.Gameplay.Camera;` (for
            // `TacticalCamera`) makes the bare name `Camera` ambiguous with
            // `UnityEngine.Camera` — the namespace wins name resolution.
            tacticalCamera.mainCamera = UnityEngine.Camera.main;
            if (tacticalCamera.mainCamera == null)
            {
                var camObj = new GameObject("MainCamera");
                // `worldPositionStays: false`, not the default `true`: by
                // this point `camGO` (the `TacticalCamera` rig) already has
                // its own Awake-assigned world position/rotation (height 20,
                // looking straight down). The default world-position-
                // preserving reparent would instead give this new child a
                // skewed local offset that cancels the parent's rotated
                // transform back down to almost world Y=0 — the actual
                // reason nothing rendered: the render camera itself ended up
                // sitting on the floor, not the rig it's attached to.
                camObj.transform.SetParent(camGO.transform, worldPositionStays: false);
                tacticalCamera.mainCamera = camObj.AddComponent<UnityEngine.Camera>();
            }
            tacticalCamera.ApplyCameraSettings();

            var patrolGO = new GameObject("GuardView");
            patrolGO.transform.SetParent(transform);
            patrolSystem = patrolGO.AddComponent<GuardView>();

            var interactionGO = new GameObject("InteractionSystem");
            interactionGO.transform.SetParent(transform);
            interactionSystem = interactionGO.AddComponent<InteractionSystem>();

            var controllerGO = new GameObject("GameController");
            controllerGO.transform.SetParent(transform);
            gameController = controllerGO.AddComponent<GameController>();

            var level01GO = new GameObject("Level01Builder");
            level01GO.transform.SetParent(transform);
            level01Builder = level01GO.AddComponent<Level01Builder>();
        }

        private MissionPlan currentPlan;

        private void GenerateLevel()
        {
            // Not `if (catalog == null)`: `catalog` is a public field on a
            // MonoBehaviour, so it is Unity-serializable, and Unity gives a
            // null `[Serializable]` class field a freshly constructed
            // instance (empty `prototypes` list) the moment the scene loads
            // — it is never actually null by the time this runs. That empty
            // stand-in catalog made every `catalog.Get(...)` call return
            // null, which is why the office scene generated 6 props and 4
            // actors as blueprint data but built zero of them: `LevelBuilder`
            // skips anything it can't resolve a prototype for.
            if (catalog == null || catalog.prototypes.Count == 0) catalog = PropCatalog.Standard;
            level01Builder.Generate();
            blueprint = level01Builder.blueprint;
        }

        private void WireReferences()
        {
            gameController.missionClock = missionClock;
            gameController.fixedStep = fixedStep;
            gameController.levelBuilder = levelBuilder;
            gameController.inputManager = inputManager;
            gameController.tacticalCamera = tacticalCamera;
            gameController.patrolSystem = patrolSystem;
            gameController.interactionSystem = interactionSystem;
            gameController.catalog = catalog;
            gameController.blueprint = blueprint;
            gameController.currentPlan = currentPlan;

            inputManager.tacticalCamera = tacticalCamera;
            inputManager.floorMask = LayerMask.GetMask("Floor", "Default");
            inputManager.interactableMask = LayerMask.GetMask("Interactable", "Door");
            inputManager.actorMask = LayerMask.GetMask("Actor");
            // Nothing ever assigned this — `HighlightActor` did
            // `new Material(selectionOutlineMaterial)` on a null field the
            // instant any actor was selected, crashing the very first click
            // on the thief.
            inputManager.selectionOutlineMaterial = SolidColorMaterial(inputManager.selectionColor);

            levelBuilder.floorPrefab = null; // will use primitives
            levelBuilder.wallPrefab = null;
            // No art assets exist yet (see the port README), so every prop
            // is a plain primitive — but the *colors* are not arbitrary:
            // `docs/ART_DIRECTION.md`'s settled "tabletop diorama" direction
            // (2026-08-18) is explicit that the palette must be pale and
            // warm — plaster walls near white, warm off-white floors — with
            // contrast coming from shadow, not from a dark base. The dark
            // charcoal walls this had before are exactly the "sealed
            // prison cell" look that direction was written to reject.
            levelBuilder.floorMaterial = SolidColorMaterial(new Color(0.87f, 0.83f, 0.74f));
            levelBuilder.wallMaterial = SolidColorMaterial(new Color(0.93f, 0.91f, 0.86f));
            levelBuilder.doorMaterial = SolidColorMaterial(new Color(0.55f, 0.40f, 0.24f));

            // U2 step 2a: the simulation state a fresh mission starts from.
            // Must exist before `Build` spawns any actor — `ActorView.Initialize`
            // registers each actor's `ActorState` into this the moment it runs.
            SimulationService.Current = new MissionState();

            // Build the level — `Build` takes and stores `catalog` itself;
            // `LevelBuilder.catalog` is private, so nothing outside it should
            // set that field directly.
            levelBuilder.Build(blueprint, catalog);
            interactionSystem.DiscoverRegistries();
        }

        private static Material SolidColorMaterial(Color color)
        {
            // U1: project moved Built-in RP → URP; "Standard" is the
            // Built-in shader and silently resolves to nothing under URP.
            var mat = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = color };
            return mat;
        }
    }
}