namespace DerClou.Gameplay.Level
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Lighting;
    using DerClou.Gameplay.Navigation;
    using DerClou.Gameplay.Props;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;
    using UnityEngine.AI;
    using UnityEngine.Rendering;
    using System.Collections.Generic;

    public class LevelBuilder : MonoBehaviour
    {
        [Header("Prefab References")]
        public GameObject floorPrefab;
        public GameObject wallPrefab;
        public GameObject doorPrefab;
        public GameObject cameraPrefab;
        public GameObject panelPrefab;
        public GameObject safePrefab;
        public GameObject lootPrefab;
        public GameObject extractionMarkerPrefab;
        public GameObject thiefPrefab;
        public GameObject guardPrefab;
        public GameObject civilianPrefab;
        public GameObject flashlightPrefab;

        [Header("Materials")]
        public Material floorMaterial;
        public Material wallMaterial;
        public Material doorMaterial;

        private PropCatalog catalog;
        private LevelBlueprint activeBlueprint;
        private Dictionary<string, GameObject> prefabCache = new();
        private List<GameObject> spawnedObjects = new();
        public UnityNavMeshWorld NavMeshWorld { get; private set; }

        public void Build(LevelBlueprint blueprint, PropCatalog catalog)
        {
            this.catalog = catalog;
            activeBlueprint = blueprint;
            Clear();

            // Before the building itself: `docs/ART_DIRECTION.md`'s settled
            // 2026-08-18 direction explicitly rejects a building with
            // nothing outside it ("the owner rightly called [it] a prison
            // cell") — grass, a paved apron and a few trees are what make
            // the level read as a place instead of a box floating in void.
            BuildSurroundings(blueprint);
            BuildFloors(blueprint);
            BuildWalls(blueprint);

            // Builds the walkability grid every actor paths against
            // (`PathFinder`, pure C#) straight from `blueprint` data — no
            // Unity NavMesh involved. See `ActorView`'s doc comment for
            // why: determinism and testability, matching how the Swift
            // version split simulation from presentation.
            // Lives on `MissionState` since U2 step 2b (replaces the old
            // `NavigationService` static) — `Build` also runs from
            // `LevelBuilderEditor`'s button outside Play, where
            // `GameBootstrap.Awake` never ran and `SimulationService.Current`
            // would otherwise still be null.
            if (SimulationService.Current == null) SimulationService.Current = new MissionState();
            // Bake for a real body, not a dimensionless point. The extra
            // 8 cm is the validated comfort margin used by the Swift
            // trajectory planner; authored door gaps are sized accordingly.
            var immutableBaseGrid = NavGrid.BuildFromBlueprint(
                blueprint, catalog, CharacterProfile.Standard.Radius, 0.08f);
            SimulationService.Current.ImmutableBaseGrid = immutableBaseGrid;
            SimulationService.Current.Grid = immutableBaseGrid.Clone();
            SimulationService.Current.Topology = WorldTopology.Build(blueprint, catalog);
            // Vision gets authored boxes, not scene colliders. This is the
            // exact immutable geometry both detection and the visible cone
            // use during deterministic replay.
            SimulationService.Current.VisionOccluders = BuildVisionOccluders(blueprint, catalog);

            BuildProps(blueprint);
            ApplyInitialDoorOccupancy(blueprint, SimulationService.Current);
            BuildUnityNavMesh(blueprint);
            BuildActors(blueprint);
            NavMeshWorld?.ValidateAuthoredRoutes(blueprint);

            // Everything above spawns at scene root with no parent, which is
            // why the hierarchy scattered floors/walls/props/actors as
            // siblings of GameBootstrap instead of grouped under it — collect
            // them under this builder's own transform instead.
            foreach (var obj in spawnedObjects) obj.transform.SetParent(transform, worldPositionStays: true);

            // Frame the camera on what was just built. `SetBounds` alone only
            // stores pan-clamp limits — it never moved the camera, and
            // nothing else does either, which is why the Game view showed
            // nothing: the camera was left wherever its GameObject started
            // (world origin), looking straight down at nothing in particular.
            var camera = FindObjectOfType<DerClou.Gameplay.Camera.TacticalCamera>();
            if (camera != null)
            {
                var bounds = CalculateBounds(blueprint);
                camera.SetBounds(bounds.min, bounds.max);
                var center = (bounds.min + bounds.max) * 0.5f;
                var span = Mathf.Max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y);
                // Half the longer side, plus a margin so walls at the edge
                // aren't clipped by the viewport — a bit more than the bare
                // minimum so the apron/grass around the building (see
                // `BuildSurroundings`) is actually visible, not just the
                // building footprint.
                camera.FocusOn(new Vector3(center.x, 0, center.y), span * 0.62f);
            }
        }

        private static void ApplyInitialDoorOccupancy(LevelBlueprint blueprint, MissionState state)
        {
            if (state?.Grid == null || state.ImmutableBaseGrid == null) return;
            foreach (var prop in blueprint.props)
            {
                if (!state.Doors.TryGetValue(prop.id, out var door) || door.isOpen) continue;
                state.Grid.ApplyLocalBoxOccupancy(
                    state.ImmutableBaseGrid,
                    prop.box,
                    true,
                    CharacterProfile.Standard.Radius + 0.08f);
            }
        }

        private void Clear()
        {
            NavMeshWorld = null;
            // `Build` runs both from Play (`GameBootstrap.Awake`) and from
            // the Editor (`LevelBuilderEditor`) — `DestroyImmediate` is only
            // safe outside Play; using it while playing is deprecated and
            // can corrupt transform state mid-frame.
            foreach (var obj in spawnedObjects)
            {
                if (obj == null) continue;
                if (Application.isPlaying) Destroy(obj); else DestroyImmediate(obj);
            }
            spawnedObjects.Clear();
        }

        private void BuildUnityNavMesh(LevelBlueprint blueprint)
        {
            var go = new GameObject("UnityNavMeshWorld");
            go.transform.SetParent(transform, false);
            NavMeshWorld = go.AddComponent<UnityNavMeshWorld>();
            NavMeshWorld.Build(blueprint);
            if (SimulationService.Current != null)
                SimulationService.Current.SpatialCorridors = NavMeshWorld;
            spawnedObjects.Add(go);
        }

        private static List<WorldBox> BuildVisionOccluders(
            LevelBlueprint blueprint,
            PropCatalog catalog)
        {
            var occluders = new List<WorldBox>(blueprint.walls.Count + blueprint.props.Count);
            occluders.AddRange(blueprint.walls);
            foreach (var prop in blueprint.props)
            {
                var prototype = catalog?.Get(prop.prototypeId);
                if (prototype == null) continue;
                bool isClosedDoor = prototype.mechanic == PropMechanic.HingedDoor
                    && !(prop.config.TryGetValue("open", out var open)
                        && open.type == LevelValue.Type.Bool && open.boolValue);
                if (!prototype.blocksMovement && !isClosedDoor) continue;
                // Glass and emissive markers do not cast an opaque gameplay
                // shadow. Every other blocking footprint participates in
                // the same analytic segment/box clipping as walls.
                if (prototype.surface == SurfaceKey.Glass
                    || prototype.surface == SurfaceKey.Emissive) continue;
                var box = prop.box;
                if (string.IsNullOrEmpty(box.sourceID)) box.sourceID = prop.id;
                occluders.Add(box);
            }
            return occluders;
        }

        /// Grass, a paved apron and a scatter of trees around the building
        /// footprint — none of it walkable, none of it part of the navmesh
        /// bake (`NavMeshBaker` only reads `blueprint.floors/walls/props`,
        /// never scans scene geometry, so nothing built here can leak into
        /// pathfinding). Purely so the level reads as a place rather than a
        /// box in void.
        private void BuildSurroundings(LevelBlueprint blueprint)
        {
            var bounds = CalculateBounds(blueprint);
            var center = (bounds.min + bounds.max) * 0.5f;
            var buildingWidth = bounds.max.x - bounds.min.x;
            var buildingDepth = bounds.max.y - bounds.min.y;

            var grassMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = new Color(0.42f, 0.55f, 0.30f) };
            var apronMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = new Color(0.62f, 0.60f, 0.56f) };
            var trunkMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = new Color(0.32f, 0.22f, 0.14f) };
            var canopyMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = new Color(0.28f, 0.45f, 0.22f) };

            var grass = GameObject.CreatePrimitive(PrimitiveType.Cube);
            grass.name = "Ground_Grass";
            grass.transform.position = new Vector3(center.x, -0.06f, center.y);
            grass.transform.localScale = new Vector3(buildingWidth + 40f, 0.1f, buildingDepth + 40f);
            grass.GetComponent<Renderer>().material = grassMaterial;
            var grassCol = grass.GetComponent<Collider>();
            if (grassCol != null) Object.DestroyImmediate(grassCol);
            spawnedObjects.Add(grass);

            const float apronMargin = 2f;
            var apron = GameObject.CreatePrimitive(PrimitiveType.Cube);
            apron.name = "Ground_Apron";
            apron.transform.position = new Vector3(center.x, -0.03f, center.y);
            apron.transform.localScale = new Vector3(buildingWidth + apronMargin * 2f, 0.1f, buildingDepth + apronMargin * 2f);
            apron.GetComponent<Renderer>().material = apronMaterial;
            var apronCol = apron.GetComponent<Collider>();
            if (apronCol != null) Object.DestroyImmediate(apronCol);
            spawnedObjects.Add(apron);

            // A handful of trees around the perimeter, clear of the apron,
            // taller than the building — a simple trunk + canopy, no
            // colliders (purely a backdrop).
            var treeOffsets = new[]
            {
                new Vector2(-1.35f, -1.3f), new Vector2(1.35f, -1.3f),
                new Vector2(-1.35f, 1.3f), new Vector2(1.35f, 1.3f),
                new Vector2(0f, -1.5f), new Vector2(-1.5f, 0f)
            };
            foreach (var offset in treeOffsets)
            {
                var pos = new Vector3(
                    center.x + offset.x * (buildingWidth * 0.5f + apronMargin + 4f),
                    0,
                    center.y + offset.y * (buildingDepth * 0.5f + apronMargin + 4f));

                var trunk = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                trunk.name = "Tree_Trunk";
                trunk.transform.position = pos + new Vector3(0, 1.5f, 0);
                trunk.transform.localScale = new Vector3(0.35f, 1.5f, 0.35f);
                trunk.GetComponent<Renderer>().material = trunkMaterial;
                var trunkCol = trunk.GetComponent<Collider>();
                if (trunkCol != null) Object.DestroyImmediate(trunkCol);
                spawnedObjects.Add(trunk);

                var canopy = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                canopy.name = "Tree_Canopy";
                canopy.transform.position = pos + new Vector3(0, 4.2f, 0);
                canopy.transform.localScale = new Vector3(2.6f, 2.6f, 2.6f);
                canopy.GetComponent<Renderer>().material = canopyMaterial;
                var canopyCol = canopy.GetComponent<Collider>();
                if (canopyCol != null) Object.DestroyImmediate(canopyCol);
                spawnedObjects.Add(canopy);
            }
        }

        private void BuildFloors(LevelBlueprint blueprint)
        {
            foreach (var floor in blueprint.floors)
            {
                var go = InstantiateFloor(floor);
                go.name = $"Floor_{floor.sourceID}";
                spawnedObjects.Add(go);
            }
        }

        private GameObject InstantiateFloor(WorldBox box)
        {
            var go = floorPrefab != null ? Instantiate(floorPrefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.transform.position = new Vector3(box.centerX, 0, box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, box.yaw, 0);
            go.transform.localScale = new Vector3(box.width, 0.1f, box.depth);
            // `InputManager.floorMask` raycasts against a "Floor" layer that
            // nothing was ever assigned to — every click fell through to
            // whatever the next mask matched (usually nothing), so floor
            // taps never registered.
            go.layer = LayerMask.NameToLayer("Floor");
            if (floorMaterial != null)
            {
                var r = go.GetComponent<Renderer>();
                if (r != null) r.material = floorMaterial;
            }
            var col = go.GetComponent<Collider>() ?? go.AddComponent<BoxCollider>();
            return go;
        }

        private void BuildWalls(LevelBlueprint blueprint)
        {
            foreach (var wall in blueprint.walls)
            {
                var go = InstantiateWall(wall);
                go.name = $"Wall_{wall.sourceID}";
                spawnedObjects.Add(go);
            }
        }

        private GameObject InstantiateWall(WorldBox box)
        {
            var go = wallPrefab != null ? Instantiate(wallPrefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.transform.position = new Vector3(box.centerX, box.height * 0.5f, box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, box.yaw, 0);
            go.transform.localScale = new Vector3(box.width, box.height, box.depth);
            if (wallMaterial != null)
            {
                var r = go.GetComponent<Renderer>();
                if (r != null) r.material = wallMaterial;
            }
            var col = go.GetComponent<Collider>() ?? go.AddComponent<BoxCollider>();
            return go;
        }

        private void BuildProps(LevelBlueprint blueprint)
        {
            foreach (var prop in blueprint.props)
            {
                var proto = catalog.Get(prop.prototypeId);
                if (proto == null) continue;

                GameObject go = null;
                switch (proto.mechanic)
                {
                    case PropMechanic.HingedDoor:
                        go = BuildDoor(prop, proto);
                        break;
                    case PropMechanic.SecurityCamera:
                        go = BuildCamera(prop, proto);
                        break;
                    case PropMechanic.Safe:
                        go = BuildSafe(prop, proto);
                        break;
                    default:
                        go = BuildGenericProp(prop, proto);
                        break;
                }

                if (go != null)
                {
                    go.name = $"{proto.kind}_{prop.id}";
                    spawnedObjects.Add(go);
                }
            }
        }

        private GameObject BuildDoor(PlacedProp prop, PropPrototype proto)
        {
            var hingeSide = prop.config.TryGetValue("hingeSide", out var h) && h.type == LevelValue.Type.String
                ? (DoorHingeSide)System.Enum.Parse(typeof(DoorHingeSide), h.stringValue)
                : DoorHingeSide.Left;
            var openAngle = prop.config.TryGetValue("openAngle", out var oa) && oa.type == LevelValue.Type.Float ? oa.floatValue : 90f;

            // A real door swings around its hinge edge, not its own center.
            // Rotating the leaf's own transform in place (the old approach)
            // spins it around the geometric middle of the doorway — visibly
            // wrong regardless of which "hinge side" was authored, since
            // that value only flipped the rotation's sign, never its pivot
            // position. Fix: an empty "hinge" parent sits at the door's
            // edge and is what actually rotates; the visual leaf is its
            // child, offset by half the door's width so it still fills the
            // original doorway when closed.
            // The door's box isn't necessarily authored with the swinging
            // dimension on the local-X ("width") axis — this sandbox's own
            // door is 0.12m wide x 1.6m deep, i.e. the swing span is on
            // local Z. Hinge on whichever axis actually holds the larger
            // (spanning) dimension rather than assuming X.
            bool spanIsWidth = prop.box.width >= prop.box.depth;
            float halfSpan = (spanIsWidth ? prop.box.width : prop.box.depth) * 0.5f;
            float sign = hingeSide == DoorHingeSide.Left ? -1f : 1f;
            var hingeLocalOffset = spanIsWidth
                ? new Vector3(halfSpan * sign, 0f, 0f)
                : new Vector3(0f, 0f, halfSpan * sign);
            var baseRot = Quaternion.Euler(0, prop.box.yaw, 0);
            var doorCenter = new Vector3(prop.box.centerX, prop.box.height * 0.5f, prop.box.centerZ);
            var hingeWorldPos = doorCenter + baseRot * hingeLocalOffset;

            var hinge = new GameObject($"DoorHinge_{prop.id}");
            hinge.transform.position = hingeWorldPos;
            hinge.transform.rotation = baseRot;

            // `new GameObject("Door")` with no fallback mesh, collider or
            // visible surface — the door has never been anything but empty
            // space to click through, whether or not `doorPrefab` is set.
            var leaf = doorPrefab != null ? Instantiate(doorPrefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);
            leaf.transform.SetParent(hinge.transform, worldPositionStays: false);
            leaf.transform.localPosition = -hingeLocalOffset;
            leaf.transform.localRotation = Quaternion.identity;
            leaf.transform.localScale = new Vector3(prop.box.width, prop.box.height, prop.box.depth);
            leaf.layer = LayerMask.NameToLayer("Door");

            var view = hinge.GetComponent<DoorView>() ?? hinge.AddComponent<DoorView>();
            view.DoorId = prop.id;
            view.SetHinge(hingeSide, openAngle);

            // Official AI Navigation dynamic-obstacle path, on the leaf so
            // the carved shape follows it as the hinge parent rotates. The
            // static surface supplies room navigation; the closed leaf
            // carves only its local footprint and DoorView disables it when
            // opened.
            var navObstacle = leaf.GetComponent<NavMeshObstacle>();
            if (navObstacle == null) navObstacle = leaf.AddComponent<NavMeshObstacle>();
            navObstacle.shape = NavMeshObstacleShape.Box;
            navObstacle.center = Vector3.zero;
            navObstacle.size = Vector3.one;
            navObstacle.carving = true;
            navObstacle.carveOnlyStationary = true;

            // Standard Unity renderers cast the physical spotlight shadow.
            // State/solver occlusion is kept separately in the 2D footprint.
            foreach (var renderer in leaf.GetComponentsInChildren<Renderer>())
            {
                renderer.shadowCastingMode = ShadowCastingMode.On;
                renderer.receiveShadows = true;
            }

            // U2 step 2d: the door's live state — open/closed target,
            // animation progress, lock — goes into `MissionState.Doors`,
            // not onto this MonoBehaviour.
            var state = SimulationService.Current;
            if (state != null)
            {
                bool initiallyOpen = prop.config.TryGetValue("open", out var initialOpen)
                    && initialOpen.type == LevelValue.Type.Bool && initialOpen.boolValue;
                state.Doors[prop.id] = new DoorState
                {
                    id = prop.id,
                    footprint = prop.box,
                    hingeSide = hingeSide,
                    openAngleDegrees = openAngle,
                    openDurationSeconds = prop.config.TryGetValue("openDuration", out var od) && od.type == LevelValue.Type.Float ? od.floatValue : 1f,
                    closeDurationSeconds = prop.config.TryGetValue("closeDuration", out var cd) && cd.type == LevelValue.Type.Float ? cd.floatValue : 1f,
                    isOpen = initiallyOpen,
                    openProgress = initiallyOpen ? 1f : 0f,
                    isLocked = prop.config.TryGetValue("locked", out var lk) && lk.type == LevelValue.Type.Bool && lk.boolValue,
                    lockDifficulty = prop.config.TryGetValue("lockDifficulty", out var ld) && ld.type == LevelValue.Type.Int ? ld.intValue : 1
                };
            }

            if (doorMaterial != null)
            {
                var r = leaf.GetComponentInChildren<Renderer>();
                if (r != null) r.material = doorMaterial;
            }

            var interactable = leaf.GetComponent<Interactable>() ?? leaf.AddComponent<Interactable>();
            interactable.InteractableId = prop.id;
            interactable.SupportedInteractions = proto.interactions;
            interactable.RuntimeState = new InteractableComponent { id = prop.id, interactions = proto.interactions, config = prop.config };

            return hinge;
        }

        private GameObject BuildCamera(PlacedProp prop, PropPrototype proto)
        {
            float mountHeight = prop.config.TryGetValue("mountHeight", out var mh) && mh.type == LevelValue.Type.Float ? mh.floatValue : 2.4f;
            const float presentationPlaneY = 0.07f;
            Vector3 planarPosition = ResolveCameraMountPosition(prop, 0.18f);

            // Root = gameplay/presentation bridge at the authoritative X/Z
            // source. The wall bracket and elevated 3D head are children;
            // their Y never enters navigation or detection.
            var go = new GameObject("SecurityCameraRoot");
            go.transform.position = new Vector3(planarPosition.x, presentationPlaneY, planarPosition.z);
            go.transform.rotation = Quaternion.identity;

            var mount = GameObject.CreatePrimitive(PrimitiveType.Cube);
            mount.name = "WallMount";
            mount.transform.SetParent(go.transform, false);
            mount.transform.localPosition = new Vector3(0f, mountHeight - presentationPlaneY, 0f);
            mount.transform.rotation = Quaternion.Euler(0f, prop.box.yaw, 0f);
            mount.transform.localScale = new Vector3(0.16f, 0.16f, 0.42f);
            var mountRenderer = mount.GetComponent<Renderer>();
            if (mountRenderer != null) mountRenderer.material.color = new Color(0.10f, 0.11f, 0.12f);
            var mountCollider = mount.GetComponent<Collider>();
            if (mountCollider != null)
            {
                if (Application.isPlaying) Destroy(mountCollider);
                else DestroyImmediate(mountCollider);
            }

            var head = cameraPrefab != null ? Instantiate(cameraPrefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);
            head.name = "CameraHead";
            head.transform.SetParent(go.transform, false);
            head.transform.localPosition = new Vector3(0f, mountHeight - presentationPlaneY, 0f);
            head.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
            if (cameraPrefab == null)
            {
                head.transform.localScale = new Vector3(0.38f, 0.24f, 0.48f);
                var fallbackRenderer = head.GetComponent<Renderer>();
                if (fallbackRenderer != null) fallbackRenderer.material.color = new Color(0.12f, 0.14f, 0.16f);
                var fallbackCollider = head.GetComponent<Collider>();
                if (fallbackCollider != null)
                {
                    if (Application.isPlaying) Destroy(fallbackCollider);
                    else DestroyImmediate(fallbackCollider);
                }
            }

            var view = go.GetComponent<CameraView>() ?? go.AddComponent<CameraView>();
            view.CameraId = prop.id;
            view.YawPivot = head.transform;
            // A wall camera covers the room it belongs to. Its range is
            // derived once from that room's authored bounds (farthest floor
            // corner), rather than hand-tuned independently per placement.
            view.GizmoRange = ResolveCameraRoomRange(planarPosition,
                prop.config.TryGetValue("range", out var r) && r.type == LevelValue.Type.Float ? r.floatValue : 8f);
            view.GizmoFieldOfView = prop.config.TryGetValue("fieldOfView", out var fov) && fov.type == LevelValue.Type.Float ? fov.floatValue : 90f;

            // U2 step 2c: the camera's live state — the only thing that
            // actually decides whether/how fast it scans — goes into
            // `MissionState.Cameras`, not onto this MonoBehaviour.
            var state = SimulationService.Current;
            if (state != null)
            {
                state.Cameras[prop.id] = new CameraState
                {
                    id = prop.id,
                    range = view.GizmoRange,
                    fieldOfView = view.GizmoFieldOfView,
                    mountHeight = mountHeight,
                    scanArc = prop.config.TryGetValue("scanArc", out var sa) && sa.type == LevelValue.Type.Float ? sa.floatValue : 90f,
                    scanPeriod = prop.config.TryGetValue("scanPeriod", out var sp) && sp.type == LevelValue.Type.Float ? sp.floatValue : 8f,
                    baseYaw = prop.box.yaw,
                    currentYaw = prop.box.yaw,
                    powered = prop.config.TryGetValue("powered", out var p) && p.type == LevelValue.Type.Bool && p.boolValue
                };

                int sourceId = GetActorId("camera:" + prop.id);
                state.VisionSources[sourceId] = new VisionSourceState
                {
                    sourceId = sourceId,
                    sourceLabel = prop.id,
                    kind = VisionSourceKind.SecurityCamera,
                    config = new VisionConfig
                    {
                        range = view.GizmoRange,
                        fieldOfViewDegrees = view.GizmoFieldOfView
                    },
                    fixedPosition = new WorldPoint(planarPosition.x, 0f, planarPosition.z),
                    // Presentation origin of the sloped beam. VisionSystem
                    // deliberately ignores Y and solves its floor projection
                    // from fixedPosition/currentFacingYaw only.
                    eyeHeight = mountHeight,
                    currentFacingYaw = prop.box.yaw,
                    isEnabled = true
                };
                (go.GetComponent<WorldSpotlightView>() ?? go.AddComponent<WorldSpotlightView>())
                    .Initialize(sourceId, head.transform);
            }

            return go;
        }

        private float ResolveCameraRoomRange(Vector3 position, float fallback)
        {
            if (activeBlueprint == null) return fallback;
            foreach (var room in activeBlueprint.rooms)
            {
                var box = room.bounds;
                float radians = -box.yaw * Mathf.Deg2Rad;
                float dx = position.x - box.centerX, dz = position.z - box.centerZ;
                float localX = dx * Mathf.Cos(radians) - dz * Mathf.Sin(radians);
                float localZ = dx * Mathf.Sin(radians) + dz * Mathf.Cos(radians);
                if (Mathf.Abs(localX) > box.width * 0.5f + 0.25f
                    || Mathf.Abs(localZ) > box.depth * 0.5f + 0.25f) continue;

                float farthest = 0f;
                for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                {
                    float lx = sx * box.width * 0.5f;
                    float lz = sz * box.depth * 0.5f;
                    float yaw = box.yaw * Mathf.Deg2Rad;
                    float wx = box.centerX + lx * Mathf.Cos(yaw) - lz * Mathf.Sin(yaw);
                    float wz = box.centerZ + lx * Mathf.Sin(yaw) + lz * Mathf.Cos(yaw);
                    farthest = Mathf.Max(farthest,
                        Mathf.Sqrt((wx - position.x) * (wx - position.x)
                            + (wz - position.z) * (wz - position.z)));
                }
                return farthest + 0.25f;
            }
            return fallback;
        }

        private Vector3 ResolveCameraMountPosition(PlacedProp prop, float offsetIntoRoom)
        {
            var authored = new Vector3(prop.box.centerX, 0f, prop.box.centerZ);
            if (activeBlueprint == null
                || !prop.config.TryGetValue("mountWallId", out var wallValue)
                || wallValue.type != LevelValue.Type.String) return authored;

            WorldBox? wall = null;
            foreach (var candidate in activeBlueprint.walls)
            {
                if (candidate.sourceID != wallValue.stringValue) continue;
                wall = candidate;
                break;
            }
            if (!wall.HasValue) return authored;

            float radians = prop.box.yaw * Mathf.Deg2Rad;
            var inward = new Vector3(Mathf.Sin(radians), 0f, Mathf.Cos(radians));
            var w = wall.Value;
            float support = Mathf.Abs(inward.x) * w.width * 0.5f
                + Mathf.Abs(inward.z) * w.depth * 0.5f;
            var wallCenter = new Vector3(w.centerX, 0f, w.centerZ);
            float targetNormal = Vector3.Dot(wallCenter, inward) + support + offsetIntoRoom;
            float authoredNormal = Vector3.Dot(authored, inward);
            return authored + inward * (targetNormal - authoredNormal);
        }

        private GameObject BuildSafe(PlacedProp prop, PropPrototype proto)
        {
            string assetKey = prop.appearance ?? proto.asset;
            bool usingRealMesh = safePrefab != null || (!string.IsNullOrEmpty(assetKey) && TryGetPrefab(assetKey, out _));
            GameObject go;
            if (safePrefab != null) go = Instantiate(safePrefab);
            else if (!string.IsNullOrEmpty(assetKey) && TryGetPrefab(assetKey, out var fbxPrefab)) go = Instantiate(fbxPrefab);
            else go = GameObject.CreatePrimitive(PrimitiveType.Cube);

            if (usingRealMesh) PlaceRealMeshProp(go, prop);
            else
            {
                go.transform.position = new Vector3(prop.box.centerX, prop.box.height * 0.5f, prop.box.centerZ);
                go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
                go.transform.localScale = new Vector3(prop.box.width, prop.box.height, prop.box.depth);
            }
            go.layer = LayerMask.NameToLayer("Interactable");

            var view = go.GetComponent<SafeView>() ?? go.AddComponent<SafeView>();
            view.SafeId = prop.id;

            // U2 step 2e: the safe's live state — lock, crack progress,
            // which actor (if any) is cracking it — goes into
            // `MissionState.Safes`, not onto this MonoBehaviour.
            var state = SimulationService.Current;
            if (state != null)
            {
                state.Safes[prop.id] = new SafeState
                {
                    id = prop.id,
                    position = new WorldPoint(prop.box.centerX, 0, prop.box.centerZ),
                    isLocked = !prop.config.TryGetValue("locked", out var lk) || lk.type != LevelValue.Type.Bool || lk.boolValue,
                    difficulty = prop.config.TryGetValue("difficulty", out var d) && d.type == LevelValue.Type.Int ? d.intValue : 3,
                    crackDurationSeconds = prop.config.TryGetValue("crackSafeDuration", out var cd) && cd.type == LevelValue.Type.Float ? cd.floatValue : 20f
                };
            }

            var interactable = go.GetComponent<Interactable>() ?? go.AddComponent<Interactable>();
            interactable.InteractableId = prop.id;
            interactable.SupportedInteractions = proto.interactions;
            interactable.RuntimeState = new InteractableComponent { id = prop.id, interactions = proto.interactions, config = prop.config };

            return go;
        }

        /// Builds the "board-game pawn" stand-in described in
        /// `docs/ART_DIRECTION.md`: a flat base, a tapered body, a head, and
        /// a facing wedge — all pure-primitive children of `parent`, which
        /// already carries the one collider that matters (selection
        /// raycasts and `ActorView` live on the root, not on these).
        private static void BuildPawnVisual(Transform parent, Color tint)
        {
            var material = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = tint };

            void AddPart(GameObject shape, Vector3 localPos, Vector3 localScale)
            {
                shape.transform.SetParent(parent, worldPositionStays: false);
                shape.transform.localPosition = localPos;
                shape.transform.localScale = localScale;
                var col = shape.GetComponent<Collider>();
                if (col != null) Object.DestroyImmediate(col);
                shape.GetComponent<Renderer>().material = material;
            }

            AddPart(GameObject.CreatePrimitive(PrimitiveType.Cylinder), new Vector3(0, 0.05f, 0), new Vector3(0.55f, 0.05f, 0.55f));
            // Capsule, not a true cone (Unity has no built-in cone) — still
            // rounded and narrower at the top than the base, close enough to
            // "tapered" at tactical-camera distance.
            AddPart(GameObject.CreatePrimitive(PrimitiveType.Capsule), new Vector3(0, 0.75f, 0), new Vector3(0.42f, 0.55f, 0.42f));
            AddPart(GameObject.CreatePrimitive(PrimitiveType.Sphere), new Vector3(0, 1.55f, 0), new Vector3(0.32f, 0.32f, 0.32f));
            // The facing wedge: a flat sliver on the base pointing along
            // local +Z, which is where `spec.yaw` on the parent already
            // aims — this is the only cue that reads facing direction from
            // directly above, which a bare capsule gave no way to show.
            AddPart(GameObject.CreatePrimitive(PrimitiveType.Cube), new Vector3(0, 0.09f, 0.4f), new Vector3(0.18f, 0.05f, 0.3f));
        }

        private GameObject BuildGenericProp(PlacedProp prop, PropPrototype proto)
        {
            GameObject go;
            string assetKey = prop.appearance ?? proto.asset;
            GameObject prefab = null;
            bool usingRealMesh = !string.IsNullOrEmpty(assetKey) && TryGetPrefab(assetKey, out prefab);
            go = usingRealMesh ? Instantiate(prefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);

            if (usingRealMesh)
            {
                PlaceRealMeshProp(go, prop);
            }
            else
            {
                go.transform.position = new Vector3(prop.box.centerX, prop.box.height * 0.5f, prop.box.centerZ);
                go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
                go.transform.localScale = new Vector3(prop.box.width, prop.box.height, prop.box.depth);

                // Emissive-surface generic props (test stimuli, markers) have
                // no dedicated prefab yet, so a plain default-material cube
                // is invisible among real furniture. Bright orange is a
                // deliberate "this is a test control, click me" cue, not a
                // production look.
                if (proto.surface == SurfaceKey.Emissive)
                {
                    var renderer = go.GetComponentInChildren<Renderer>();
                    if (renderer != null)
                        renderer.material = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = new Color(1f, 0.45f, 0f) };
                }
            }

            if (proto.interactions.Length > 0)
            {
                go.layer = LayerMask.NameToLayer("Interactable");
                var interactable = go.GetComponent<Interactable>() ?? go.AddComponent<Interactable>();
                interactable.InteractableId = prop.id;
                interactable.SupportedInteractions = proto.interactions;
                interactable.RuntimeState = new InteractableComponent { id = prop.id, interactions = proto.interactions, config = prop.config };

                // U3 step 3b: loot needs a presentation hook to disappear
                // once `PlanExecutor` marks it collected in `MissionState`.
                if (System.Array.IndexOf(proto.interactions, InteractionKind.TakeLoot) >= 0)
                {
                    var lootView = go.GetComponent<LootView>() ?? go.AddComponent<LootView>();
                    lootView.LootId = prop.id;
                }
            }

            return go;
        }

        /// Shared positioning for any prop built from a real authored mesh
        /// (Household Props FBX, a serialized prefab reference, etc.),
        /// used by both BuildGenericProp and BuildSafe. Real meshes already
        /// ship at real-world meter scale with the pivot at ground contact
        /// under the model — confirmed directly by measuring renderer
        /// bounds (minY == 0 for every prop tested). The level blueprint's
        /// box is a gameplay footprint, not a sculpting target:
        /// non-uniform-stretching a real mesh to exactly fill that box
        /// (correct for the primitive-cube placeholder) would visibly
        /// squash/stretch furniture not authored at the footprint's exact
        /// proportions. Scale uniformly so the model's own height matches
        /// the footprint's authored height instead, keeping proportions.
        private static void PlaceRealMeshProp(GameObject go, PlacedProp prop)
        {
            var renderers = go.GetComponentsInChildren<Renderer>();
            float meshHeight = 0f;
            Bounds localBounds = default;
            bool hasBounds = renderers.Length > 0;
            if (hasBounds)
            {
                localBounds = renderers[0].bounds;
                for (int i = 1; i < renderers.Length; i++) localBounds.Encapsulate(renderers[i].bounds);
                meshHeight = localBounds.size.y;
            }
            float uniformScale = (meshHeight > 0.001f && prop.box.height > 0f)
                ? prop.box.height / meshHeight : 1f;
            go.transform.position = new Vector3(prop.box.centerX, 0f, prop.box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
            go.transform.localScale = Vector3.one * uniformScale;

            // FBX imports carry no collider (only Unity primitives get one
            // automatically) — without this, raycast picking (Interactable
            // clicks) and physical blocking silently stop working the
            // moment a real mesh replaces the placeholder cube.
            // `localBounds` was measured at identity transform, so it's
            // already the correct local-space collider size.
            if (go.GetComponentInChildren<Collider>() == null && hasBounds)
            {
                var col = go.AddComponent<BoxCollider>();
                col.center = localBounds.center;
                col.size = localBounds.size;
            }
        }

        private bool TryGetPrefab(string key, out GameObject prefab)
        {
            if (prefabCache.TryGetValue(key, out prefab)) return true;
            prefab = Resources.Load<GameObject>($"Characters/{key}") ?? Resources.Load<GameObject>($"Props/{key}");
            if (prefab != null) prefabCache[key] = prefab;
            return prefab != null;
        }

        private void BuildActors(LevelBlueprint blueprint)
        {
            foreach (var actorSpec in blueprint.actors)
            {
                var proto = catalog.Get(actorSpec.prototypeId);
                if (proto == null || proto.actorRole == null) continue;

                var go = SpawnActor(actorSpec, proto);
                if (go != null)
                {
                    go.name = $"Actor_{actorSpec.id}";
                    spawnedObjects.Add(go);
                }
            }
        }

        private GameObject SpawnActor(ActorSpec spec, PropPrototype proto)
        {
            GameObject prefab = null;
            string assetKey = spec.appearance ?? proto.asset;
            if (!string.IsNullOrEmpty(assetKey) && TryGetPrefab(assetKey, out var p)) prefab = p;

            GameObject go;
            if (prefab != null)
            {
                go = Instantiate(prefab);

                // Real character meshes (e.g. a glTF import) aren't
                // authored at this project's exact target height and carry
                // no collider or animator controller of their own — same
                // gap PlaceRealMeshProp closes for furniture, but actors
                // also need a click/selection collider and their locomotion
                // controller wired up (ActorView.UpdateAnimation expects
                // "Walk"/"Idle" bools and a "Speed" float; see ActorView.cs).
                var skinnedRenderers = go.GetComponentsInChildren<SkinnedMeshRenderer>();
                if (skinnedRenderers.Length > 0)
                {
                    var bounds = skinnedRenderers[0].bounds;
                    for (int i = 1; i < skinnedRenderers.Length; i++) bounds.Encapsulate(skinnedRenderers[i].bounds);
                    float meshHeight = bounds.size.y;
                    float targetHeight = proto.height > 0f ? proto.height : meshHeight;
                    if (meshHeight > 0.001f)
                        go.transform.localScale = Vector3.one * (targetHeight / meshHeight);

                    // The click/selection collider lives on a dedicated
                    // child, not this glTF import's own root: on this
                    // particular hierarchy (root Animator + SkinnedMeshRenderers
                    // under it), AddComponent<CapsuleCollider> on the root
                    // reproducibly returns Unity's fake-null partway through
                    // this method — confirmed reproducible in live Play Mode,
                    // not reproducible in isolation. InputManager resolves
                    // ActorView via GetComponentInParent, so the collider
                    // doesn't need to share a GameObject with ActorView/Animator.
                    var colliderGo = new GameObject("PhysicsCollider");
                    colliderGo.transform.SetParent(go.transform, false);
                    // Counter-scale so the collider's own dimensions can be
                    // given directly in final world units, independent of
                    // the parent's mesh-fit scale set just above.
                    if (meshHeight > 0.001f)
                        colliderGo.transform.localScale = Vector3.one * (meshHeight / targetHeight);
                    var col = colliderGo.AddComponent<CapsuleCollider>();

                    col.radius = 0.3f;
                    col.height = targetHeight;
                    col.center = new Vector3(0, targetHeight * 0.5f, 0);

                    // glTFast bakes Idle/Walk as Generic clips (direct
                    // transform curves) — it has no Humanoid AnimationMethod
                    // at all, and a Humanoid Avatar on an Animator playing
                    // those Generic clips directly breaks them outright
                    // (confirmed live: Mecanim routes humanoid-mapped joint
                    // rotations through its muscle solver regardless of the
                    // driving clip's own type, and since these clips carry
                    // no muscle data the joints just freeze at the avatar's
                    // rest pose). A future accepted character may provide an
                    // asset-specific Humanoid controller, but no provisional
                    // controller or Avatar is retained in production Resources.
                    var animator = go.GetComponentInChildren<Animator>();
                    if (animator != null && animator.avatar == null)
                    {
                        var avatar = Resources.Load<Avatar>($"Characters/{assetKey}Avatar");
                        if (avatar != null) animator.avatar = avatar;
                    }
                    if (animator != null && animator.runtimeAnimatorController == null)
                    {
                        var runtimeController = Resources.Load<RuntimeAnimatorController>($"Characters/{assetKey}ControllerHumanoid")
                            ?? Resources.Load<RuntimeAnimatorController>($"Characters/{assetKey}Controller");
                        if (runtimeController != null) animator.runtimeAnimatorController = runtimeController;
                    }
                }
            }
            else
            {
                // No character models yet. `docs/ART_DIRECTION.md`'s settled
                // 2026-08-18 direction is specific about the stand-in shape:
                // "a base, a tapered body, a head, and a wedge on the base
                // for facing... the shape a board game would use" — not a
                // bare capsule, which reads the same from every direction
                // and gives no facing cue from directly above.
                var tint = proto.actorRole switch
                {
                    ActorRole.Thief => new Color(0.85f, 0.55f, 0.15f),
                    ActorRole.Guard => new Color(0.15f, 0.25f, 0.65f),
                    _ => new Color(0.5f, 0.5f, 0.5f)
                };
                go = new GameObject("PawnRoot");
                var col = go.AddComponent<CapsuleCollider>();
                col.radius = 0.3f;
                col.height = 1.8f;
                col.center = new Vector3(0, 0.9f, 0);
                BuildPawnVisual(go.transform, tint);
            }

            go.transform.position = new Vector3(spec.position.x, 0, spec.position.y);
            go.transform.rotation = Quaternion.Euler(0, spec.yaw, 0);
            // `InputManager.actorMask` raycasts an "Actor" layer nothing was
            // ever assigned to — actors could never be clicked/selected.
            go.layer = LayerMask.NameToLayer("Actor");

            var actor = go.GetComponent<ActorView>() ?? go.AddComponent<ActorView>();
            var profile = BuildCharacterProfile(spec, proto);
            var actorId = GetActorId(spec.id);
            actor.Initialize(
                actorId: actorId,
                role: proto.actorRole.Value,
                profile: profile,
                appearanceKey: spec.appearance ?? proto.asset
            );

            // U2 step 2b: the guard's live state goes straight into
            // `MissionState.Guards` — `Core.Systems.GuardPatrolSystem` reads
            // and drives it from there. `GuardView` (the renamed
            // MonoBehaviour) only needs to know which `ActorView` to animate
            // for which actor id.
            if (proto.actorRole == ActorRole.Guard && spec.route != null && spec.route.Count > 0)
            {
                var nodes = new PatrolNode[spec.route.Count];
                for (int i = 0; i < spec.route.Count; i++)
                {
                    nodes[i] = new PatrolNode
                    {
                        position = new WorldPoint(spec.route[i].x, 0, spec.route[i].y),
                        waitDuration = 1.5f,
                        facingYaw = -1f
                    };
                }
                var route = new PatrolRoute { actorId = actorId, nodes = nodes, loop = true };
                var state = SimulationService.Current;
                if (state != null) state.Guards[actorId] = new GuardState { actorId = actorId, route = route };

                if (spec.config.TryGetValue("showPatrolRoute", out var showRoute)
                    && showRoute.type == LevelValue.Type.Bool && showRoute.boolValue)
                {
                    BuildPatrolRouteLine(spec.id, nodes, route.loop);
                }

                var guardView = FindObjectOfType<GuardView>();
                if (guardView != null) guardView.RegisterView(actorId, actor);

                bool visionEnabled = spec.config.TryGetValue("visionEnabled", out var enabled)
                    && enabled.type == LevelValue.Type.Bool && enabled.boolValue;
                if (state != null && visionEnabled)
                {
                    float range = spec.config.TryGetValue("visionRange", out var rangeValue)
                        && rangeValue.type == LevelValue.Type.Float
                            ? rangeValue.floatValue : VisionProfiles.guardActor.range;
                    float fov = spec.config.TryGetValue("visionFov", out var fovValue)
                        && fovValue.type == LevelValue.Type.Float
                            ? fovValue.floatValue : VisionProfiles.guardActor.fieldOfViewDegrees;
                    state.VisionSources[actorId] = new VisionSourceState
                    {
                        sourceId = actorId,
                        sourceLabel = spec.id,
                        actorId = actorId,
                        kind = VisionSourceKind.GuardActor,
                        config = new VisionConfig { range = range, fieldOfViewDegrees = fov },
                        eyeHeight = profile.height * 0.88f,
                        currentFacingYaw = spec.yaw,
                        isEnabled = true
                    };
                    // Use the animation pack's matching right-hand Humanoid
                    // hold clip and SK_Flashlight prop. ActorView extracts the
                    // authored weapon_r socket instead of guessing a grip.
                    var heldFlashlightPrefab = flashlightPrefab
                        ?? Resources.Load<GameObject>("Props/FlashlightKit/StandardFlashlight");
                    var lightOrigin = actor.ConfigureFlashlight(heldFlashlightPrefab, useLeftHand: false);
                    if (lightOrigin == null)
                    {
                        lightOrigin = new GameObject("FlashlightOrigin").transform;
                        lightOrigin.SetParent(go.transform, false);
                        lightOrigin.localPosition = new Vector3(0.18f, profile.height * 0.78f, 0.42f);
                    }
                    (go.GetComponent<WorldSpotlightView>() ?? go.AddComponent<WorldSpotlightView>())
                        .Initialize(actorId, lightOrigin);
                }
            }

            return go;
        }

        /// Presentation-only authored patrol overlay. It reads the exact
        /// PatrolNode positions already given to Core, so the line cannot
        /// disagree with the route. No collider or gameplay component is
        /// created: it never participates in taps, pathfinding or detection.
        private void BuildPatrolRouteLine(string actorSpecId, PatrolNode[] nodes, bool loop)
        {
            if (nodes == null || nodes.Length < 2) return;

            var routeObject = new GameObject($"PatrolRoute_{actorSpecId}");
            var line = routeObject.AddComponent<LineRenderer>();
            line.useWorldSpace = true;
            line.loop = loop;
            line.positionCount = nodes.Length;
            line.startWidth = 0.09f;
            line.endWidth = 0.09f;
            line.numCornerVertices = 6;
            line.numCapVertices = 4;
            line.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            line.receiveShadows = false;

            var routeColor = new Color(1f, 0.68f, 0.08f, 0.92f);
            var shader = Shader.Find("Universal Render Pipeline/Unlit");
            line.material = new Material(shader) { color = routeColor };
            line.startColor = routeColor;
            line.endColor = routeColor;

            // Floor top is Y=0.05. Lift the overlay slightly to avoid
            // z-fighting while keeping it visually painted on the floor.
            for (int i = 0; i < nodes.Length; i++)
                line.SetPosition(i, new Vector3(nodes[i].position.x, 0.075f, nodes[i].position.z));

            spawnedObjects.Add(routeObject);
        }

        private int GetActorId(string specId)
        {
            // Simple hash for demo
            int hash = 0;
            foreach (char c in specId) hash = hash * 31 + c;
            return hash;
        }

        private CharacterProfile BuildCharacterProfile(ActorSpec spec, PropPrototype proto)
        {
            var resolved = proto.ResolvedConfig(spec.config);
            var profile = new CharacterProfile
            {
                // Prop footprints are placement-grid cells, not shoulder
                // widths. Treating actor.thief's 1x1 footprint as 1 metre
                // made every pawn much fatter than both its capsule and the
                // validated Swift CharacterProfile.
                width = resolved.TryGetValue("bodyWidth", out var bw) && bw.type == LevelValue.Type.Float ? bw.floatValue : CharacterProfile.Standard.width,
                height = proto.height,
                walkSpeed = resolved.TryGetValue("walkSpeed", out var ws) && ws.type == LevelValue.Type.Float ? ws.floatValue : 1.4f,
                acceleration = resolved.TryGetValue("acceleration", out var acc) && acc.type == LevelValue.Type.Float ? acc.floatValue : 2.8f,
                deceleration = resolved.TryGetValue("deceleration", out var dec) && dec.type == LevelValue.Type.Float ? dec.floatValue : 3.2f,
                preferredWallClearance = resolved.TryGetValue("preferredWallClearance", out var pwc) && pwc.type == LevelValue.Type.Float ? pwc.floatValue : 0.45f,
                wallAvoidanceWeight = resolved.TryGetValue("wallAvoidanceWeight", out var waw) && waw.type == LevelValue.Type.Float ? waw.floatValue : 4f,
                maxTurnRateDegrees = resolved.TryGetValue("maximumTurnRateDegrees", out var mtr) && mtr.type == LevelValue.Type.Float ? mtr.floatValue : 240f,
                preferredCornerRadius = resolved.TryGetValue("preferredCornerRadius", out var pcr) && pcr.type == LevelValue.Type.Float ? pcr.floatValue : 0.45f,
                interactionArrivalTolerance = resolved.TryGetValue("interactionArrivalTolerance", out var iat) && iat.type == LevelValue.Type.Float ? iat.floatValue : 0.08f
            };
            return profile;
        }

        private (Vector2 min, Vector2 max) CalculateBounds(LevelBlueprint blueprint)
        {
            float minX = float.MaxValue, maxX = float.MinValue, minZ = float.MaxValue, maxZ = float.MinValue;
            foreach (var f in blueprint.floors)
            {
                float hw = f.width * 0.5f, hd = f.depth * 0.5f;
                minX = Mathf.Min(minX, f.centerX - hw);
                maxX = Mathf.Max(maxX, f.centerX + hw);
                minZ = Mathf.Min(minZ, f.centerZ - hd);
                maxZ = Mathf.Max(maxZ, f.centerZ + hd);
            }
            return (new Vector2(minX, minZ), new Vector2(maxX, maxZ));
        }
    }
}
