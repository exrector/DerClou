namespace DerClou.Gameplay.Level
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Props;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;
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
        private Dictionary<string, GameObject> prefabCache = new();
        private List<GameObject> spawnedObjects = new();

        public void Build(LevelBlueprint blueprint, PropCatalog catalog)
        {
            this.catalog = catalog;
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
            SimulationService.Current.Grid = NavGrid.BuildFromBlueprint(blueprint, catalog);

            BuildProps(blueprint);
            BuildActors(blueprint);

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

        private void Clear()
        {
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
            // `new GameObject("Door")` with no fallback mesh, collider or
            // visible surface — the door has never been anything but empty
            // space to click through, whether or not `doorPrefab` is set.
            var go = doorPrefab != null ? Instantiate(doorPrefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.transform.position = new Vector3(prop.box.centerX, prop.box.height * 0.5f, prop.box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
            go.transform.localScale = new Vector3(prop.box.width, prop.box.height, prop.box.depth);
            go.layer = LayerMask.NameToLayer("Door");

            var door = go.GetComponent<Door>() ?? go.AddComponent<Door>();
            door.DoorId = prop.id;
            door.HingeSide = prop.config.TryGetValue("hingeSide", out var h) && h.type == LevelValue.Type.String
                ? (DoorHingeSide)System.Enum.Parse(typeof(DoorHingeSide), h.stringValue)
                : DoorHingeSide.Left;
            door.OpenAngle = prop.config.TryGetValue("openAngle", out var oa) && oa.type == LevelValue.Type.Float ? oa.floatValue : 90f;
            door.OpenDuration = prop.config.TryGetValue("openDuration", out var od) && od.type == LevelValue.Type.Float ? od.floatValue : 1f;
            door.CloseDuration = prop.config.TryGetValue("closeDuration", out var cd) && cd.type == LevelValue.Type.Float ? cd.floatValue : 1f;
            door.IsLocked = prop.config.TryGetValue("locked", out var lk) && lk.type == LevelValue.Type.Bool && lk.boolValue;
            door.LockDifficulty = prop.config.TryGetValue("lockDifficulty", out var ld) && ld.type == LevelValue.Type.Int ? ld.intValue : 1;

            if (doorMaterial != null)
            {
                var r = go.GetComponentInChildren<Renderer>();
                if (r != null) r.material = doorMaterial;
            }

            var interactable = go.GetComponent<Interactable>() ?? go.AddComponent<Interactable>();
            interactable.InteractableId = prop.id;
            interactable.SupportedInteractions = proto.interactions;
            interactable.RuntimeState = new InteractableComponent { id = prop.id, interactions = proto.interactions, config = prop.config };

            return go;
        }

        private GameObject BuildCamera(PlacedProp prop, PropPrototype proto)
        {
            var go = cameraPrefab != null ? Instantiate(cameraPrefab) : new GameObject("Camera");
            go.transform.position = new Vector3(prop.box.centerX, prop.config.TryGetValue("mountHeight", out var mh) && mh.type == LevelValue.Type.Float ? mh.floatValue : 2.4f, prop.box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);

            var cam = go.GetComponent<SecurityCamera>() ?? go.AddComponent<SecurityCamera>();
            cam.CameraId = prop.id;
            cam.Range = prop.config.TryGetValue("range", out var r) && r.type == LevelValue.Type.Float ? r.floatValue : 8f;
            cam.FieldOfView = prop.config.TryGetValue("fieldOfView", out var fov) && fov.type == LevelValue.Type.Float ? fov.floatValue : 90f;
            cam.ScanArc = prop.config.TryGetValue("scanArc", out var sa) && sa.type == LevelValue.Type.Float ? sa.floatValue : 90f;
            cam.ScanPeriod = prop.config.TryGetValue("scanPeriod", out var sp) && sp.type == LevelValue.Type.Float ? sp.floatValue : 8f;
            cam.Powered = prop.config.TryGetValue("powered", out var p) && p.type == LevelValue.Type.Bool && p.boolValue;

            return go;
        }

        private GameObject BuildSafe(PlacedProp prop, PropPrototype proto)
        {
            var go = safePrefab != null ? Instantiate(safePrefab) : GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.transform.position = new Vector3(prop.box.centerX, prop.box.height * 0.5f, prop.box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
            go.transform.localScale = new Vector3(prop.box.width, prop.box.height, prop.box.depth);
            go.layer = LayerMask.NameToLayer("Interactable");

            var safe = go.GetComponent<Safe>() ?? go.AddComponent<Safe>();
            safe.SafeId = prop.id;
            safe.IsLocked = !prop.config.TryGetValue("locked", out var lk) || lk.type != LevelValue.Type.Bool || lk.boolValue;
            safe.Difficulty = prop.config.TryGetValue("difficulty", out var d) && d.type == LevelValue.Type.Int ? d.intValue : 3;
            safe.CrackDuration = prop.config.TryGetValue("crackSafeDuration", out var cd) && cd.type == LevelValue.Type.Float ? cd.floatValue : 20f;

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
            if (!string.IsNullOrEmpty(assetKey) && TryGetPrefab(assetKey, out var prefab))
            {
                go = Instantiate(prefab);
            }
            else
            {
                go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            }

            go.transform.position = new Vector3(prop.box.centerX, prop.box.height * 0.5f, prop.box.centerZ);
            go.transform.rotation = Quaternion.Euler(0, prop.box.yaw, 0);
            go.transform.localScale = new Vector3(prop.box.width, prop.box.height, prop.box.depth);

            if (proto.interactions.Length > 0)
            {
                go.layer = LayerMask.NameToLayer("Interactable");
                var interactable = go.GetComponent<Interactable>() ?? go.AddComponent<Interactable>();
                interactable.InteractableId = prop.id;
                interactable.SupportedInteractions = proto.interactions;
                interactable.RuntimeState = new InteractableComponent { id = prop.id, interactions = proto.interactions, config = prop.config };
            }

            return go;
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

                var guardView = FindObjectOfType<GuardView>();
                if (guardView != null) guardView.RegisterView(actorId, actor);
            }

            // Flashlight for Guard03
            if (proto.actorRole == ActorRole.Guard && (spec.appearance == "guard03" || proto.asset == "guard03"))
            {
                actor.carryFlashlight = true;
                actor.flashlightPrefab = flashlightPrefab;
                // Find right hand bone. No character models are imported yet
                // (a primitive capsule stands in — see the port README), so
                // there is no Humanoid Avatar for `GetBoneTransform` to read;
                // calling it without one throws, which used to abort this
                // whole `BuildActors` loop partway through and silently drop
                // every actor after guard03 in spec order.
                var animator = go.GetComponent<Animator>();
                if (animator != null && animator.isHuman)
                {
                    actor.rightHandBone = animator.GetBoneTransform(HumanBodyBones.RightHand);
                }
                actor.ApplyFlashlightPose();
            }

            return go;
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
                width = proto.footprint.width,
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