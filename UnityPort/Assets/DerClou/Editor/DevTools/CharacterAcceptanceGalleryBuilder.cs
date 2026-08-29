namespace DerClou.Editor.DevTools
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Linq;
    using DerClou.Gameplay.DevTools;
    using UnityEditor;
    using UnityEditor.Animations;
    using UnityEditor.SceneManagement;
    using UnityEngine;
    using UnityEngine.Rendering;

    /// <summary>
    /// Builds a visual acceptance gallery with exactly one character from each
    /// package whose Generic skeleton is structurally compatible with the
    /// proven Epic/UE5 flashlight clip. No Humanoid conversion or retargeting is
    /// allowed here: an incompatible character must fail honestly instead of
    /// receiving a visibly altered arm and hand pose.
    /// </summary>
    public static class CharacterAcceptanceGalleryBuilder
    {
        private const string ScenePath = "Assets/DerClou/CharacterReview/CharacterAcceptanceGallery.unity";
        private const string ControllerPath = "Assets/DerClou/CharacterReview/EpicFlashlightAcceptance.controller";
        private const string FlashlightGenericPath = "Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx";
        private const string GeneratedFolder = "Assets/DerClou/CharacterReview/GeneratedMaterials";
        private static int materialSerial;

        [MenuItem("DerClou/Character Review/Rebuild One Per Package")]
        public static void BuildFromMenu() => Build();

        public static string Build()
        {
            EnsureFolder("Assets/DerClou/CharacterReview");
            if (AssetDatabase.IsValidFolder(GeneratedFolder))
            {
                AssetDatabase.DeleteAsset(GeneratedFolder);
            }

            AssetDatabase.CreateFolder("Assets/DerClou/CharacterReview", "GeneratedMaterials");
            materialSerial = 0;
            PrepareFlashlightController();

            var controller = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(ControllerPath);
            if (controller == null)
            {
                throw new InvalidOperationException($"Missing review controller: {ControllerPath}");
            }

            var groups = DiscoverCandidates()
                .GroupBy(candidate => candidate.Package)
                .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
                .ToList();

            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var root = new GameObject("CharacterAcceptanceGrid");
            var accepted = new List<Animator>();
            var labels = new List<string>();
            var reports = new List<string>();

            const int columns = 5;
            const float xSpacing = 3.4f;
            const float zSpacing = 3.9f;

            foreach (var group in groups)
            {
                GameObject chosenInstance = null;
                Animator chosenAnimator = null;
                Candidate chosen = null;

                foreach (var candidate in group.OrderByDescending(item => item.Score).ThenBy(item => item.Path))
                {
                    var asset = AssetDatabase.LoadAssetAtPath<GameObject>(candidate.Path);
                    if (asset == null)
                    {
                        continue;
                    }

                    var instance = PrefabUtility.InstantiatePrefab(asset) as GameObject;
                    if (instance == null)
                    {
                        instance = UnityEngine.Object.Instantiate(asset);
                    }

                    instance.SetActive(true);
                    var animator = instance.GetComponentsInChildren<Animator>(true)
                        .FirstOrDefault(IsCompatibleGenericAnimator);
                    // Preserve the prefab author's chosen clothing/body setup.
                    // Enabling every inactive child activates mutually exclusive
                    // modular outfits on top of one another and produces a false
                    // broken/red candidate in the review scene.
                    var visibleBodies = instance.GetComponentsInChildren<SkinnedMeshRenderer>(false)
                        .Where(IsCharacterBody)
                        .ToArray();

                    if (animator == null || visibleBodies.Length == 0)
                    {
                        UnityEngine.Object.DestroyImmediate(instance);
                        continue;
                    }

                    // Package demo controllers must not influence the shared
                    // acceptance animation. Some assets run root-motion or
                    // camera/player scripts from Animator callbacks and can
                    // overwrite the pose or throw while the clip is sampled.
                    foreach (var behaviour in instance.GetComponentsInChildren<MonoBehaviour>(true))
                    {
                        behaviour.enabled = false;
                    }

                    foreach (var renderer in instance.GetComponentsInChildren<Renderer>(false))
                    {
                        ConvertRendererMaterials(renderer, group.Key);
                    }

                    chosenInstance = instance;
                    chosenAnimator = animator;
                    chosen = candidate;
                    break;
                }

                if (chosenInstance == null)
                {
                    reports.Add($"{group.Key}: SKIPPED (no visible Epic Generic character)");
                    continue;
                }

                var index = accepted.Count;
                var column = index % columns;
                var row = index / columns;
                var x = (column - (columns - 1) * 0.5f) * xSpacing;
                var z = -row * zSpacing;

                chosenInstance.name = $"Candidate_{SafeName(group.Key)}";
                chosenInstance.transform.SetParent(root.transform, true);
                chosenInstance.transform.SetPositionAndRotation(Vector3.zero, Quaternion.identity);
                chosenInstance.transform.localScale = Vector3.one;

                var bounds = CalculateBounds(chosenInstance);
                chosenInstance.transform.localScale = Vector3.one * (1.82f / Mathf.Max(0.01f, bounds.size.y));
                bounds = CalculateBounds(chosenInstance);
                chosenInstance.transform.position += new Vector3(x - bounds.center.x, -bounds.min.y, z - bounds.center.z);

                chosenAnimator.runtimeAnimatorController = controller;
                chosenAnimator.applyRootMotion = false;
                chosenAnimator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
                chosenAnimator.updateMode = AnimatorUpdateMode.Normal;
                    var mappedFingerBones = CountRightFingerBones(chosenAnimator);
                var fingerStatus = mappedFingerBones == 15 ? "FINGERS 15/15" : $"PARTIAL {mappedFingerBones}/15";
                CreateLabel(root.transform, group.Key, Path.GetFileNameWithoutExtension(chosen.Path), fingerStatus, x, z);
                accepted.Add(chosenAnimator);
                labels.Add($"{group.Key} — {Path.GetFileNameWithoutExtension(chosen.Path)} — {fingerStatus}");
                reports.Add($"{group.Key}: {chosen.Path}");
            }

            var rows = Mathf.Max(1, Mathf.CeilToInt(accepted.Count / (float)columns));
            CreateEnvironment(rows, columns);
            CreateCameraAndControls(accepted, labels, rows, zSpacing);

            EditorSceneManager.SaveScene(scene, ScenePath);
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();

            var summary = $"Gallery rebuilt: {accepted.Count} packages represented, {groups.Count} package groups discovered.\n" +
                          string.Join("\n", reports);
            Debug.Log(summary);
            return summary;
        }

        private static List<Candidate> DiscoverCandidates()
        {
            var guids = new HashSet<string>(AssetDatabase.FindAssets("t:Prefab"));
            foreach (var guid in AssetDatabase.FindAssets("t:Model"))
            {
                guids.Add(guid);
            }

            var candidates = new List<Candidate>();
            foreach (var guid in guids)
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (!path.StartsWith("Assets/", StringComparison.Ordinal))
                {
                    continue;
                }

                var parts = path.Split('/');
                if (parts.Length < 3)
                {
                    continue;
                }

                var package = parts[1];
                if (IsProjectFolder(package) || IsLikelyNonCharacter(path))
                {
                    continue;
                }

                var asset = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                if (asset == null)
                {
                    continue;
                }

                var animator = asset.GetComponentsInChildren<Animator>(true)
                    .FirstOrDefault(IsCompatibleGenericAnimator);
                if (animator == null || !asset.GetComponentsInChildren<SkinnedMeshRenderer>(true).Any(IsCharacterBody))
                {
                    continue;
                }

                candidates.Add(new Candidate(package, path, Score(path)));
            }

            return candidates;
        }

        private static void PrepareFlashlightController()
        {
            var source = AssetDatabase.LoadAllAssetsAtPath(FlashlightGenericPath)
                .OfType<AnimationClip>()
                .FirstOrDefault(clip => !clip.name.StartsWith("__preview__", StringComparison.Ordinal));
            if (source == null || source.humanMotion)
            {
                throw new InvalidOperationException(
                    $"Flashlight acceptance clip must remain Generic: {FlashlightGenericPath}");
            }

            var controller = AssetDatabase.LoadAssetAtPath<AnimatorController>(ControllerPath);
            if (controller == null)
            {
                controller = AnimatorController.CreateAnimatorControllerAtPath(ControllerPath);
            }

            var stateMachine = controller.layers[0].stateMachine;
            var states = stateMachine.states;
            var state = states.Length > 0 ? states[0].state : stateMachine.AddState("Flashlight Pose");
            state.motion = source;
            state.speed = 1f;
            state.cycleOffset = 0f;
            stateMachine.defaultState = state;
            foreach (var childState in stateMachine.states)
            {
                if (childState.state != state)
                {
                    stateMachine.RemoveState(childState.state);
                }
            }

            EditorUtility.SetDirty(controller);
            AssetDatabase.SaveAssets();
        }

        private static bool IsCharacterBody(SkinnedMeshRenderer renderer) =>
            renderer.sharedMesh != null &&
            renderer.sharedMesh.vertexCount > 500 &&
            renderer.bones != null &&
            renderer.bones.Length > 15;

        private static bool IsProjectFolder(string package) =>
            package is "DerClou" or "Settings" or "Scenes" or "Resources" or "Tests" or "Editor";

        private static bool IsLikelyNonCharacter(string path)
        {
            var lower = path.ToLowerInvariant();
            string[] excluded =
            {
                "/animation/", "/animations/", "/anim/", "/motion/", "/motions/",
                "/weapon/", "/weapons/", "/gun/", "/guns/", "/prop/", "/props/",
                "/furniture/", "/environment/", "/vehicle/", "/vehicles/",
                "/effect/", "/effects/", "/vfx/", "/camera/", "/door/",
                "/cargo/", "/tabletop/", "/garage/", "/flashlight/"
            };
            return excluded.Any(lower.Contains);
        }

        private static int Score(string path)
        {
            var lower = path.ToLowerInvariant();
            var score = path.EndsWith(".prefab", StringComparison.OrdinalIgnoreCase) ? 80 : 40;
            if (lower.Contains("/urp") || lower.Contains("_urp")) score += 35;
            if (lower.Contains("prefab")) score += 15;
            if (lower.Contains("character")) score += 8;
            if (lower.Contains("male") || lower.Contains("man")) score += 3;
            if (lower.Contains("hdrp")) score -= 35;
            if (lower.Contains("legacy")) score -= 20;
            if (lower.Contains("/demo/") || lower.Contains("/sample")) score -= 10;
            return score;
        }

        private static Bounds CalculateBounds(GameObject root)
        {
            var renderers = root.GetComponentsInChildren<Renderer>(false)
                .Where(renderer => renderer.enabled && renderer.gameObject.activeInHierarchy && renderer is not ParticleSystemRenderer)
                .ToArray();
            if (renderers.Length == 0)
            {
                return new Bounds(root.transform.position, Vector3.one);
            }

            var bounds = renderers[0].bounds;
            for (var index = 1; index < renderers.Length; index++)
            {
                bounds.Encapsulate(renderers[index].bounds);
            }

            return bounds;
        }

        private static void CreateLabel(
            Transform root,
            string package,
            string assetName,
            string fingerStatus,
            float x,
            float z)
        {
            var labelObject = new GameObject($"Label_{SafeName(package)}");
            labelObject.transform.SetParent(root, false);
            labelObject.transform.position = new Vector3(x, 2.18f, z + 0.18f);
            labelObject.transform.rotation = Quaternion.Euler(0f, 180f, 0f);
            var text = labelObject.AddComponent<TextMesh>();
            text.text = $"{package}\n{assetName}\n{fingerStatus}";
            text.fontSize = 44;
            text.characterSize = 0.032f;
            text.anchor = TextAnchor.MiddleCenter;
            text.alignment = TextAlignment.Center;
            text.color = fingerStatus.StartsWith("FINGERS", StringComparison.Ordinal)
                ? new Color(0.78f, 1f, 0.82f, 1f)
                : new Color(1f, 0.67f, 0.30f, 1f);
        }

        private static int CountRightFingerBones(Animator animator)
        {
            string[] fingers =
            {
                "thumb_01_r", "thumb_02_r", "thumb_03_r",
                "index_01_r", "index_02_r", "index_03_r",
                "middle_01_r", "middle_02_r", "middle_03_r",
                "ring_01_r", "ring_02_r", "ring_03_r",
                "pinky_01_r", "pinky_02_r", "pinky_03_r"
            };
            var names = animator.GetComponentsInChildren<Transform>(true)
                .Select(item => item.name)
                .ToHashSet(StringComparer.Ordinal);
            return fingers.Count(names.Contains);
        }

        private static bool IsCompatibleGenericAnimator(Animator animator)
        {
            if (animator == null || animator.avatar == null || !animator.avatar.isValid || animator.avatar.isHuman)
            {
                return false;
            }

            // Corrective/twist helper bones are optional because the proven
            // VoxelVision reference itself intentionally omits some of them.
            // The deforming spine, limbs, hands and every finger must match.
            string[] requiredPaths =
            {
                "root", "root/pelvis",
                "root/pelvis/spine_01", "root/pelvis/spine_01/spine_02",
                "root/pelvis/spine_01/spine_02/spine_03",
                "root/pelvis/spine_01/spine_02/spine_03/spine_04",
                "root/pelvis/spine_01/spine_02/spine_03/spine_04/spine_05",
                "root/pelvis/spine_01/spine_02/spine_03/spine_04/spine_05/neck_01",
                "root/pelvis/spine_01/spine_02/spine_03/spine_04/spine_05/neck_01/neck_02",
                "root/pelvis/spine_01/spine_02/spine_03/spine_04/spine_05/neck_01/neck_02/head",
                "root/pelvis/thigh_l", "root/pelvis/thigh_l/calf_l", "root/pelvis/thigh_l/calf_l/foot_l",
                "root/pelvis/thigh_r", "root/pelvis/thigh_r/calf_r", "root/pelvis/thigh_r/calf_r/foot_r"
            };
            if (requiredPaths.Any(path => animator.transform.Find(path) == null)) return false;

            foreach (var side in new[] { "l", "r" })
            {
                var hand = $"root/pelvis/spine_01/spine_02/spine_03/spine_04/spine_05/clavicle_{side}/upperarm_{side}/lowerarm_{side}/hand_{side}";
                if (animator.transform.Find(hand) == null) return false;
                foreach (var finger in new[] { "thumb", "index", "middle", "ring", "pinky" })
                {
                    var first = finger == "thumb" ? $"{hand}/{finger}_01_{side}" : $"{hand}/{finger}_metacarpal_{side}/{finger}_01_{side}";
                    if (animator.transform.Find(first) == null ||
                        animator.transform.Find($"{first}/{finger}_02_{side}") == null ||
                        animator.transform.Find($"{first}/{finger}_02_{side}/{finger}_03_{side}") == null)
                    {
                        return false;
                    }
                }
            }

            return true;
        }

        private static void CreateCameraAndControls(
            IReadOnlyCollection<Animator> accepted,
            IReadOnlyCollection<string> labels,
            int rows,
            float zSpacing)
        {
            var cameraObject = new GameObject("Main Camera");
            cameraObject.tag = "MainCamera";
            var camera = cameraObject.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.055f, 0.065f, 0.085f, 1f);
            camera.nearClipPlane = 0.05f;
            camera.farClipPlane = 100f;

            var centerZ = -(rows - 1) * zSpacing * 0.5f;
            var overviewTarget = new Vector3(0f, 1.05f, centerZ);
            var overviewPosition = new Vector3(0f, 9.3f, 13.5f);
            cameraObject.transform.SetPositionAndRotation(
                overviewPosition,
                Quaternion.LookRotation(overviewTarget - overviewPosition, Vector3.up));

            var controls = new GameObject("Gallery Controls");
            var gallery = controls.AddComponent<CharacterAcceptanceGallery>();
            gallery.galleryCamera = camera;
            gallery.candidates = accepted.ToArray();
            gallery.labels = labels.ToArray();
            gallery.overviewPosition = overviewPosition;
            gallery.overviewTarget = overviewTarget;
            gallery.overviewSize = Mathf.Max(5.5f, rows * 1.65f);
        }

        private static void CreateEnvironment(int rows, int columns)
        {
            var ground = GameObject.CreatePrimitive(PrimitiveType.Cube);
            ground.name = "Review Floor";
            ground.transform.position = new Vector3(0f, -0.12f, -(rows - 1) * 1.95f);
            ground.transform.localScale = new Vector3(columns * 3.6f, 0.2f, rows * 4.1f);
            ground.GetComponent<Renderer>().sharedMaterial = CreateColorMaterial("ReviewFloor", new Color(0.11f, 0.13f, 0.17f, 1f));

            var key = new GameObject("Key Light");
            var keyLight = key.AddComponent<Light>();
            keyLight.type = LightType.Directional;
            keyLight.intensity = 1.35f;
            keyLight.color = new Color(1f, 0.93f, 0.84f);
            key.transform.rotation = Quaternion.Euler(42f, -28f, 0f);

            var fill = new GameObject("Fill Light");
            var fillLight = fill.AddComponent<Light>();
            fillLight.type = LightType.Directional;
            fillLight.intensity = 0.72f;
            fillLight.color = new Color(0.62f, 0.76f, 1f);
            fill.transform.rotation = Quaternion.Euler(35f, 145f, 0f);

            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.36f, 0.39f, 0.45f, 1f);
        }

        private static void ConvertRendererMaterials(Renderer renderer, string package)
        {
            var source = renderer.sharedMaterials;
            if (source == null || source.Length == 0)
            {
                return;
            }

            var converted = new Material[source.Length];
            for (var index = 0; index < source.Length; index++)
            {
                var material = source[index];
                if (material != null && IsUrpMaterial(material))
                {
                    converted[index] = material;
                    continue;
                }

                var shader = Shader.Find("Universal Render Pipeline/Lit") ??
                             Shader.Find("Universal Render Pipeline/Simple Lit");
                var copy = new Material(shader)
                {
                    name = $"{(material != null ? material.name : "Missing")}_ReviewURP"
                };
                CopySurface(material, copy);

                var fileName = $"{SafeName(package)}_{SafeName(copy.name)}_{++materialSerial:D3}.mat";
                var assetPath = AssetDatabase.GenerateUniqueAssetPath($"{GeneratedFolder}/{fileName}");
                AssetDatabase.CreateAsset(copy, assetPath);
                converted[index] = copy;
            }

            renderer.sharedMaterials = converted;
        }

        private static bool IsUrpMaterial(Material material)
        {
            if (material == null || material.shader == null || !material.shader.isSupported)
            {
                return false;
            }

            var shaderName = material.shader.name.ToLowerInvariant();
            return shaderName.Contains("universal render pipeline") || shaderName.Contains("shader graphs/");
        }

        private static void CopySurface(Material source, Material target)
        {
            if (source == null)
            {
                return;
            }

            var color = source.HasProperty("_BaseColor") ? source.GetColor("_BaseColor") :
                source.HasProperty("_Color") ? source.GetColor("_Color") : Color.white;
            if (target.HasProperty("_BaseColor")) target.SetColor("_BaseColor", color);

            var baseMap = FirstTexture(source, "_BaseMap", "_MainTex", "_BaseColorMap", "_BaseColorTexture", "_Albedo");
            if (baseMap != null && target.HasProperty("_BaseMap")) target.SetTexture("_BaseMap", baseMap);

            var normal = FirstTexture(source, "_BumpMap", "_NormalMap", "_Normal");
            if (normal != null && target.HasProperty("_BumpMap"))
            {
                target.SetTexture("_BumpMap", normal);
                target.EnableKeyword("_NORMALMAP");
            }

            if (source.HasProperty("_Metallic") && target.HasProperty("_Metallic"))
                target.SetFloat("_Metallic", source.GetFloat("_Metallic"));
            var smoothness = source.HasProperty("_Smoothness") ? source.GetFloat("_Smoothness") :
                source.HasProperty("_Glossiness") ? source.GetFloat("_Glossiness") : 0.35f;
            if (target.HasProperty("_Smoothness")) target.SetFloat("_Smoothness", smoothness);

            var emission = FirstTexture(source, "_EmissionMap", "_EmissiveColorMap");
            var emissionColor = source.HasProperty("_EmissionColor") ? source.GetColor("_EmissionColor") : Color.black;
            if (emission != null && target.HasProperty("_EmissionMap")) target.SetTexture("_EmissionMap", emission);
            if (target.HasProperty("_EmissionColor")) target.SetColor("_EmissionColor", emissionColor);
            if (emission != null || emissionColor.maxColorComponent > 0.001f) target.EnableKeyword("_EMISSION");

            if (color.a < 0.99f)
            {
                if (target.HasProperty("_Surface")) target.SetFloat("_Surface", 1f);
                if (target.HasProperty("_SrcBlend")) target.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
                if (target.HasProperty("_DstBlend")) target.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
                if (target.HasProperty("_ZWrite")) target.SetFloat("_ZWrite", 0f);
                target.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                target.renderQueue = (int)RenderQueue.Transparent;
            }
        }

        private static Texture FirstTexture(Material material, params string[] properties)
        {
            foreach (var property in properties)
            {
                if (!material.HasProperty(property))
                {
                    continue;
                }

                var texture = material.GetTexture(property);
                if (texture != null)
                {
                    return texture;
                }
            }

            return null;
        }

        private static Material CreateColorMaterial(string name, Color color)
        {
            var shader = Shader.Find("Universal Render Pipeline/Lit") ??
                         Shader.Find("Universal Render Pipeline/Simple Lit");
            var material = new Material(shader) { name = name };
            if (material.HasProperty("_BaseColor")) material.SetColor("_BaseColor", color);
            AssetDatabase.CreateAsset(material, $"{GeneratedFolder}/{name}.mat");
            return material;
        }

        private static string SafeName(string value)
        {
            if (string.IsNullOrEmpty(value))
            {
                return "Unnamed";
            }

            var invalid = Path.GetInvalidFileNameChars();
            var safe = new string(value.Select(character =>
                invalid.Contains(character) || character is '/' or '\\' ? '_' : character).ToArray());
            return safe.Length > 56 ? safe[..56] : safe;
        }

        private static void EnsureFolder(string path)
        {
            var parts = path.Split('/');
            var current = parts[0];
            for (var index = 1; index < parts.Length; index++)
            {
                var next = $"{current}/{parts[index]}";
                if (!AssetDatabase.IsValidFolder(next)) AssetDatabase.CreateFolder(current, parts[index]);
                current = next;
            }
        }

        private sealed class Candidate
        {
            public Candidate(string package, string path, int score)
            {
                Package = package;
                Path = path;
                Score = score;
            }

            public string Package { get; }
            public string Path { get; }
            public int Score { get; }
        }
    }
}
