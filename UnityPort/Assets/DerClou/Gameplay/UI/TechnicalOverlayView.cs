namespace DerClou.Gameplay.UI
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;
    using UnityEngine.Rendering;

    /// Runtime counterpart of Unity's Scene gizmos. It deliberately reads the
    /// authoritative 2D mission state, so the Game-view overlay describes the
    /// exact space used by pathfinding and detection rather than approximate
    /// 3D light/collider geometry.
    public sealed class TechnicalOverlayView : MonoBehaviour
    {
        private const int RangeArcSamples = 28;
        private const int ActorCircleSamples = 32;
        private const float OverlayHeight = 0.055f;
        private const float RefreshInterval = 1f / 30f;

        public bool IsVisible { get; private set; }

        private readonly Dictionary<int, SourceVisual> sourceVisuals = new();
        private readonly Dictionary<int, ActorVisual> actorVisuals = new();
        private readonly List<float> rayAngles = new(96);
        private readonly List<Vector3> polygonPoints = new(96);
        private readonly List<Vector3> meshVertices = new(96);
        private readonly List<int> meshTriangles = new(288);
        private readonly List<Vector3> walkableVertices = new(4096);
        private readonly List<int> walkableTriangles = new(6144);
        private readonly List<Vector3> blockedVertices = new(2048);
        private readonly List<int> blockedTriangles = new(3072);

        private Transform visualRoot;
        private Mesh walkableMesh;
        private Mesh blockedMesh;
        private Material guardLineMaterial;
        private Material cameraLineMaterial;
        private Material actorLineMaterial;
        private Material guardFillMaterial;
        private Material cameraFillMaterial;
        private Material walkableMaterial;
        private Material blockedMaterial;
        private float nextRefreshTime;
        private uint gridHash;

        public void Initialize(bool initiallyVisible = false)
        {
            EnsureVisuals();
            SetVisible(initiallyVisible);
        }

        public void Toggle() => SetVisible(!IsVisible);

        public void SetVisible(bool visible)
        {
            EnsureVisuals();
            IsVisible = visible;
            visualRoot.gameObject.SetActive(visible);
            if (!visible) return;
            gridHash = 0;
            nextRefreshTime = 0f;
            RefreshNow();
        }

        private void LateUpdate()
        {
            if (!IsVisible || Time.unscaledTime < nextRefreshTime) return;
            RefreshNow();
        }

        private void RefreshNow()
        {
            nextRefreshTime = Time.unscaledTime + RefreshInterval;
            var state = SimulationService.Current;
            if (state == null) return;
            UpdateVision(state);
            UpdateActors(state);
            UpdateGridIfChanged(state.Grid);
        }

        private void UpdateVision(MissionState state)
        {
            foreach (var pair in sourceVisuals) pair.Value.Root.SetActive(false);

            foreach (var pair in state.VisionSources)
            {
                VisionSourceState source = pair.Value;
                if (!source.isEnabled) continue;

                WorldPoint observer;
                if (source.kind == VisionSourceKind.GuardActor)
                {
                    if (!state.Actors.TryGetValue(source.actorId, out var actor)) continue;
                    observer = new WorldPoint(actor.Position.x, 0f, actor.Position.z);
                }
                else if (source.kind == VisionSourceKind.SecurityCamera)
                {
                    if (!state.Cameras.TryGetValue(source.sourceLabel, out var camera) || !camera.powered) continue;
                    observer = new WorldPoint(source.fixedPosition.x, 0f, source.fixedPosition.z);
                }
                else continue;

                SourceVisual visual = EnsureSourceVisual(source.sourceId, source.kind);
                visual.Root.SetActive(true);
                BuildVisibilityPolygon(observer, source, state.VisionOccluders, visual);
            }
        }

        private void BuildVisibilityPolygon(
            WorldPoint observer,
            VisionSourceState source,
            IReadOnlyList<WorldBox> occluders,
            SourceVisual visual)
        {
            float halfFov = Mathf.Max(0f, source.config.fieldOfViewDegrees) * 0.5f;
            rayAngles.Clear();
            for (int i = 0; i <= RangeArcSamples; i++)
                rayAngles.Add(Mathf.Lerp(-halfFov, halfFov, i / (float)RangeArcSamples));

            // Uniform rays describe the circular range boundary. Rays on
            // either side of every rotated-box corner make occlusion edges
            // agree with VisionSolver rather than visually cutting corners.
            if (occluders != null)
            {
                for (int boxIndex = 0; boxIndex < occluders.Count; boxIndex++)
                {
                    WorldBox box = occluders[boxIndex];
                    float yaw = box.yaw * Mathf.Deg2Rad;
                    float c = Mathf.Cos(yaw), s = Mathf.Sin(yaw);
                    for (int corner = 0; corner < 4; corner++)
                    {
                        float localX = (corner & 1) == 0 ? -box.width * 0.5f : box.width * 0.5f;
                        float localZ = (corner & 2) == 0 ? -box.depth * 0.5f : box.depth * 0.5f;
                        float worldX = box.centerX + c * localX + s * localZ;
                        float worldZ = box.centerZ - s * localX + c * localZ;
                        float absolute = Mathf.Atan2(worldX - observer.x, worldZ - observer.z) * Mathf.Rad2Deg;
                        float relative = Mathf.DeltaAngle(source.currentFacingYaw, absolute);
                        if (relative < -halfFov - 0.1f || relative > halfFov + 0.1f) continue;
                        rayAngles.Add(Mathf.Clamp(relative - 0.04f, -halfFov, halfFov));
                        rayAngles.Add(Mathf.Clamp(relative, -halfFov, halfFov));
                        rayAngles.Add(Mathf.Clamp(relative + 0.04f, -halfFov, halfFov));
                    }
                }
            }
            rayAngles.Sort();

            polygonPoints.Clear();
            polygonPoints.Add(new Vector3(observer.x, OverlayHeight, observer.z));
            float lastAngle = float.NegativeInfinity;
            for (int i = 0; i < rayAngles.Count; i++)
            {
                float relative = rayAngles[i];
                if (relative - lastAngle < 0.001f) continue;
                lastAngle = relative;
                float yaw = source.currentFacingYaw + relative;
                float reach = VisionSolver.VisibleReach(observer, 0f, yaw, source.config.range, occluders);
                float radians = yaw * Mathf.Deg2Rad;
                polygonPoints.Add(new Vector3(
                    observer.x + Mathf.Sin(radians) * reach,
                    OverlayHeight,
                    observer.z + Mathf.Cos(radians) * reach));
            }

            visual.Outline.positionCount = polygonPoints.Count + 1;
            for (int i = 0; i < polygonPoints.Count; i++) visual.Outline.SetPosition(i, polygonPoints[i]);
            visual.Outline.SetPosition(polygonPoints.Count, polygonPoints[0]);

            meshVertices.Clear();
            meshTriangles.Clear();
            meshVertices.AddRange(polygonPoints);
            for (int i = 1; i < polygonPoints.Count - 1; i++)
            {
                meshTriangles.Add(0);
                meshTriangles.Add(i);
                meshTriangles.Add(i + 1);
            }
            visual.FillMesh.Clear(false);
            visual.FillMesh.SetVertices(meshVertices);
            visual.FillMesh.SetTriangles(meshTriangles, 0, true);
        }

        private void UpdateActors(MissionState state)
        {
            foreach (var pair in actorVisuals) pair.Value.Root.SetActive(false);
            foreach (var pair in state.Actors)
            {
                ActorState actor = pair.Value;
                ActorVisual visual = EnsureActorVisual(actor.ActorId, actor.Role);
                visual.Root.SetActive(true);
                float radius = actor.Profile.Radius > 0f
                    ? actor.Profile.Radius
                    : CharacterProfile.Standard.Radius;
                for (int i = 0; i <= ActorCircleSamples; i++)
                {
                    float angle = i * Mathf.PI * 2f / ActorCircleSamples;
                    visual.Circle.SetPosition(i, new Vector3(
                        actor.Position.x + Mathf.Cos(angle) * radius,
                        OverlayHeight + 0.015f,
                        actor.Position.z + Mathf.Sin(angle) * radius));
                }

                int remaining = actor.HasPath && actor.CurrentPath != null
                    ? Mathf.Max(0, actor.CurrentPath.Length - actor.PathIndex)
                    : 0;
                visual.Path.positionCount = remaining > 0 ? remaining + 1 : 0;
                if (remaining <= 0) continue;
                visual.Path.SetPosition(0, new Vector3(actor.Position.x, OverlayHeight + 0.01f, actor.Position.z));
                for (int i = 0; i < remaining; i++)
                {
                    WorldPoint point = actor.CurrentPath[actor.PathIndex + i];
                    visual.Path.SetPosition(i + 1, new Vector3(point.x, OverlayHeight + 0.01f, point.z));
                }
            }
        }

        private void UpdateGridIfChanged(NavGrid grid)
        {
            if (grid?.cells == null) return;
            uint hash = 2166136261u;
            for (int i = 0; i < grid.cells.Length; i++)
            {
                hash ^= grid.cells[i].walkable ? (byte)1 : (byte)0;
                hash *= 16777619u;
            }
            if (hash == gridHash) return;
            gridHash = hash;

            walkableVertices.Clear();
            walkableTriangles.Clear();
            blockedVertices.Clear();
            blockedTriangles.Clear();
            for (int y = 0; y < grid.height; y++)
            for (int x = 0; x < grid.width; x++)
            {
                NavCell cell = grid.cells[grid.Index(x, y)];
                WorldPoint center = grid.CellToWorld(new CellPoint(x, y));
                if (cell.walkable)
                    AddCellQuad(walkableVertices, walkableTriangles, center, grid.cellSize);
                else
                    AddCellQuad(blockedVertices, blockedTriangles, center, grid.cellSize);
            }

            ApplyMesh(walkableMesh, walkableVertices, walkableTriangles);
            ApplyMesh(blockedMesh, blockedVertices, blockedTriangles);
        }

        private static void AddCellQuad(List<Vector3> vertices, List<int> triangles, WorldPoint center, float size)
        {
            int start = vertices.Count;
            float h = size * 0.47f;
            vertices.Add(new Vector3(center.x - h, OverlayHeight - 0.018f, center.z - h));
            vertices.Add(new Vector3(center.x + h, OverlayHeight - 0.018f, center.z - h));
            vertices.Add(new Vector3(center.x + h, OverlayHeight - 0.018f, center.z + h));
            vertices.Add(new Vector3(center.x - h, OverlayHeight - 0.018f, center.z + h));
            triangles.Add(start); triangles.Add(start + 2); triangles.Add(start + 1);
            triangles.Add(start); triangles.Add(start + 3); triangles.Add(start + 2);
        }

        private static void ApplyMesh(Mesh mesh, List<Vector3> vertices, List<int> triangles)
        {
            mesh.Clear(false);
            mesh.indexFormat = vertices.Count > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16;
            mesh.SetVertices(vertices);
            mesh.SetTriangles(triangles, 0, true);
        }

        private void EnsureVisuals()
        {
            if (visualRoot != null) return;
            var root = new GameObject("TechnicalOverlayRuntime");
            root.transform.SetParent(transform, false);
            visualRoot = root.transform;

            guardLineMaterial = CreateMaterial(new Color(1f, 0.82f, 0.08f, 1f));
            cameraLineMaterial = CreateMaterial(new Color(1f, 0.08f, 0.12f, 1f));
            actorLineMaterial = CreateMaterial(new Color(0.05f, 0.95f, 1f, 1f));
            guardFillMaterial = CreateMaterial(new Color(1f, 0.76f, 0.05f, 0.14f));
            cameraFillMaterial = CreateMaterial(new Color(1f, 0.03f, 0.08f, 0.15f));
            walkableMaterial = CreateMaterial(new Color(0.05f, 0.8f, 0.45f, 0.055f));
            blockedMaterial = CreateMaterial(new Color(0.95f, 0.08f, 0.12f, 0.19f));

            walkableMesh = CreateGridMesh("WalkableCells", walkableMaterial);
            blockedMesh = CreateGridMesh("BlockedCells", blockedMaterial);
        }

        private Mesh CreateGridMesh(string name, Material material)
        {
            var go = new GameObject(name, typeof(MeshFilter), typeof(MeshRenderer));
            go.transform.SetParent(visualRoot, false);
            var mesh = new Mesh { name = name + "Mesh", indexFormat = IndexFormat.UInt32 };
            go.GetComponent<MeshFilter>().sharedMesh = mesh;
            go.GetComponent<MeshRenderer>().sharedMaterial = material;
            return mesh;
        }

        private SourceVisual EnsureSourceVisual(int sourceId, VisionSourceKind kind)
        {
            if (sourceVisuals.TryGetValue(sourceId, out var existing)) return existing;
            var root = new GameObject("Vision_" + sourceId);
            root.transform.SetParent(visualRoot, false);
            Material lineMaterial = kind == VisionSourceKind.SecurityCamera ? cameraLineMaterial : guardLineMaterial;
            Material fillMaterial = kind == VisionSourceKind.SecurityCamera ? cameraFillMaterial : guardFillMaterial;
            var outline = CreateLine("Perimeter", root.transform, lineMaterial, 0.055f);
            var fillObject = new GameObject("Area", typeof(MeshFilter), typeof(MeshRenderer));
            fillObject.transform.SetParent(root.transform, false);
            var mesh = new Mesh { name = "VisionArea_" + sourceId, indexFormat = IndexFormat.UInt32 };
            fillObject.GetComponent<MeshFilter>().sharedMesh = mesh;
            fillObject.GetComponent<MeshRenderer>().sharedMaterial = fillMaterial;
            var visual = new SourceVisual(root, outline, mesh);
            sourceVisuals[sourceId] = visual;
            return visual;
        }

        private ActorVisual EnsureActorVisual(int actorId, ActorRole role)
        {
            if (actorVisuals.TryGetValue(actorId, out var existing)) return existing;
            var root = new GameObject("ActorClearance_" + actorId);
            root.transform.SetParent(visualRoot, false);
            var circle = CreateLine("BodyRadius", root.transform, actorLineMaterial, 0.045f);
            circle.positionCount = ActorCircleSamples + 1;
            var path = CreateLine("CommittedPath", root.transform, actorLineMaterial, 0.035f);
            path.colorGradient = role == ActorRole.Guard
                ? SolidGradient(new Color(1f, 0.58f, 0.05f, 0.95f))
                : SolidGradient(new Color(0.05f, 0.95f, 1f, 0.95f));
            var visual = new ActorVisual(root, circle, path);
            actorVisuals[actorId] = visual;
            return visual;
        }

        private static LineRenderer CreateLine(string name, Transform parent, Material material, float width)
        {
            var go = new GameObject(name, typeof(LineRenderer));
            go.transform.SetParent(parent, false);
            var line = go.GetComponent<LineRenderer>();
            line.useWorldSpace = true;
            line.loop = false;
            line.widthMultiplier = width;
            line.numCornerVertices = 2;
            line.numCapVertices = 2;
            line.sharedMaterial = material;
            line.colorGradient = SolidGradient(Color.white);
            line.shadowCastingMode = ShadowCastingMode.Off;
            line.receiveShadows = false;
            return line;
        }

        private static Gradient SolidGradient(Color color)
        {
            var gradient = new Gradient();
            gradient.SetKeys(
                new[] { new GradientColorKey(color, 0f), new GradientColorKey(color, 1f) },
                new[] { new GradientAlphaKey(color.a, 0f), new GradientAlphaKey(color.a, 1f) });
            return gradient;
        }

        private static Material CreateMaterial(Color color)
        {
            Shader shader = Shader.Find("Sprites/Default") ?? Shader.Find("Universal Render Pipeline/Unlit");
            var material = new Material(shader)
            {
                name = "TechnicalOverlay_" + ColorUtility.ToHtmlStringRGBA(color),
                color = color,
                renderQueue = (int)RenderQueue.Transparent,
                hideFlags = HideFlags.HideAndDontSave
            };
            if (material.HasProperty("_BaseColor")) material.SetColor("_BaseColor", color);
            if (material.HasProperty("_Surface")) material.SetFloat("_Surface", 1f);
            if (material.HasProperty("_ZWrite")) material.SetFloat("_ZWrite", 0f);
            return material;
        }

        private void OnDestroy()
        {
            foreach (var pair in sourceVisuals) if (pair.Value.FillMesh != null) Destroy(pair.Value.FillMesh);
            if (walkableMesh != null) Destroy(walkableMesh);
            if (blockedMesh != null) Destroy(blockedMesh);
            DestroyMaterial(guardLineMaterial); DestroyMaterial(cameraLineMaterial); DestroyMaterial(actorLineMaterial);
            DestroyMaterial(guardFillMaterial); DestroyMaterial(cameraFillMaterial);
            DestroyMaterial(walkableMaterial); DestroyMaterial(blockedMaterial);
        }

        private static void DestroyMaterial(Material material)
        {
            if (material != null) Destroy(material);
        }

        private sealed class SourceVisual
        {
            public readonly GameObject Root;
            public readonly LineRenderer Outline;
            public readonly Mesh FillMesh;
            public SourceVisual(GameObject root, LineRenderer outline, Mesh fillMesh)
            { Root = root; Outline = outline; FillMesh = fillMesh; }
        }

        private sealed class ActorVisual
        {
            public readonly GameObject Root;
            public readonly LineRenderer Circle;
            public readonly LineRenderer Path;
            public ActorVisual(GameObject root, LineRenderer circle, LineRenderer path)
            { Root = root; Circle = circle; Path = path; }
        }
    }
}
