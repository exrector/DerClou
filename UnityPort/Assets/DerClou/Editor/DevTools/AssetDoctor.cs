namespace DerClou.Editor.DevTools
{
    using System.Collections.Generic;
    using System.IO;
    using System.Linq;
    using System.Text;
    using UnityEditor;
    using UnityEngine;

    /// One-shot conditioning + vetting pass for freshly downloaded art.
    ///
    /// Every character/animation pack needs the same chores before it works:
    /// characters and character animations must be Humanoid, prop animations
    /// must NOT be, textures embedded in the FBX have to be extracted, and
    /// Built-in "Standard" materials have to be moved onto URP. Skipping any
    /// one of them is what makes an asset show up grey, white, or with an
    /// open hand -- which reads as "this pack is incompatible" when it is
    /// really just unconditioned.
    ///
    /// This runs all of it, then reports a verdict per file, including the
    /// defects that no import setting can fix (no skeleton at all, or blank
    /// placeholder colour maps shipped instead of real ones).
    public static class AssetDoctor
    {
        private const string MenuRoot = "DerClou/Asset Doctor/";

        [MenuItem(MenuRoot + "Condition + Vet Selected Folder")]
        public static void RunOnSelection()
        {
            var roots = Selection.objects
                .Select(AssetDatabase.GetAssetPath)
                .Where(p => !string.IsNullOrEmpty(p))
                .ToArray();

            if (roots.Length == 0)
            {
                EditorUtility.DisplayDialog("Asset Doctor",
                    "Select a folder (or asset) in the Project window first.", "OK");
                return;
            }
            Run(roots);
        }

        [MenuItem(MenuRoot + "Condition + Vet Everything Outside DerClou")]
        public static void RunOnAllImportedArt()
        {
            var roots = AssetDatabase.GetSubFolders("Assets")
                .Where(f => !f.StartsWith("Assets/DerClou") && !f.StartsWith("Assets/Settings"))
                .ToArray();
            Run(roots);
        }

        private static void Run(string[] searchFolders)
        {
            var report = new StringBuilder();
            report.AppendLine("=== Asset Doctor ===");

            var guids = AssetDatabase.FindAssets("t:Model", searchFolders);
            int conditioned = 0, usable = 0, rejected = 0;

            try
            {
                for (int i = 0; i < guids.Length; i++)
                {
                    string path = AssetDatabase.GUIDToAssetPath(guids[i]);
                    EditorUtility.DisplayProgressBar("Asset Doctor",
                        Path.GetFileName(path), (float)i / guids.Length);

                    var importer = AssetImporter.GetAtPath(path) as ModelImporter;
                    if (importer == null) continue;

                    if (Condition(importer, path, report)) conditioned++;

                    string verdict = Vet(path, report);
                    if (verdict == "REJECT") rejected++; else if (verdict == "OK") usable++;
                }
            }
            finally { EditorUtility.ClearProgressBar(); }

            report.AppendLine();
            report.AppendLine($"scanned {guids.Length} model files | conditioned {conditioned} | usable {usable} | rejected {rejected}");
            Debug.Log(report.ToString());
        }

        /// Applies the import settings the asset needs. Returns true if
        /// anything actually changed.
        private static bool Condition(ModelImporter importer, string path, StringBuilder report)
        {
            bool changed = false;

            // Decide Humanoid vs Generic by TRYING it, never by guessing from
            // the folder name: packs routinely keep real characters in a
            // folder called "Meshes", and a name-based guess silently strips
            // Humanoid off perfectly good characters.
            if (importer.animationType != ModelImporterAnimationType.Human)
            {
                importer.animationType = ModelImporterAnimationType.Human;
                importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
                importer.SaveAndReimport();
                changed = true;
            }

            if (!HasWorkingHumanoidAvatar(path))
            {
                // Not a human rig (a door, a locker, a weapon): Humanoid would
                // spam "Required human bone not found", so put it on Generic.
                if (importer.animationType != ModelImporterAnimationType.Generic)
                {
                    importer.animationType = ModelImporterAnimationType.Generic;
                    importer.SaveAndReimport();
                    report.AppendLine($"  Generic (not a human rig): {path}");
                    changed = true;
                }
                return changed;
            }

            if (changed) report.AppendLine($"  Humanoid: {path}");

            // Pull embedded textures out so materials have something to bind.
            // Only reached for confirmed human rigs, so no prop check needed.
            if (NeedsTextureExtraction(path))
            {
                string dir = Path.Combine(Path.GetDirectoryName(path), "Textures");
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                if (importer.ExtractTextures(dir))
                {
                    AssetDatabase.Refresh();
                    report.AppendLine($"  extracted textures -> {dir}");
                    changed = true;
                }
            }

            if (ConditionMaterials(path, report)) changed = true;
            return changed;
        }

        /// Did Unity actually manage to build a human avatar for this file?
        /// This is the only trustworthy way to tell a character (or character
        /// animation) apart from a prop.
        private static bool HasWorkingHumanoidAvatar(string path)
        {
            // Read the Avatar sub-asset the importer produced, not the
            // Animator on a cached GameObject: right after SaveAndReimport
            // that GameObject can still hold a stale avatar and report a
            // perfectly good character as "not human".
            var avatar = AssetDatabase.LoadAllAssetsAtPath(path).OfType<Avatar>().FirstOrDefault();
            return avatar != null && avatar.isHuman && avatar.isValid;
        }

        private static bool NeedsTextureExtraction(string path)
        {
            // If any material still has no albedo bound, it is worth trying.
            var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (go == null) return false;
            foreach (var r in go.GetComponentsInChildren<Renderer>(true))
                foreach (var m in r.sharedMaterials)
                {
                    if (m == null) continue;
                    if (m.HasProperty("_BaseMap") && m.GetTexture("_BaseMap") == null) return true;
                }
            return false;
        }

        /// Moves Built-in "Standard" materials onto URP and kills the metallic
        /// defaults that make untextured skin read as polished grey metal.
        private static bool ConditionMaterials(string path, StringBuilder report)
        {
            var lit = Shader.Find("Universal Render Pipeline/Lit");
            if (lit == null) return false;

            bool changed = false;
            var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (go == null) return false;

            var seen = new HashSet<Material>();
            foreach (var r in go.GetComponentsInChildren<Renderer>(true))
                foreach (var m in r.sharedMaterials)
                {
                    if (m == null || !seen.Add(m)) continue;
                    if (!AssetDatabase.IsMainAsset(m) && !AssetDatabase.IsSubAsset(m)) continue;

                    // Never touch anything living under Packages/: those are
                    // immutable, shared by every project, and editing them
                    // silently changes rendering everywhere.
                    string mp = AssetDatabase.GetAssetPath(m);
                    if (string.IsNullOrEmpty(mp) || !mp.StartsWith("Assets/")) continue;

                    if (m.shader != null && m.shader.name == "Standard")
                    {
                        var tex = m.HasProperty("_MainTex") ? m.GetTexture("_MainTex") : null;
                        var col = m.HasProperty("_Color") ? m.GetColor("_Color") : Color.white;
                        m.shader = lit;
                        if (tex != null) m.SetTexture("_BaseMap", tex);
                        m.SetColor("_BaseColor", col);
                        report.AppendLine($"  material Standard -> URP/Lit: {m.name}");
                        changed = true;
                    }

                    if (m.HasProperty("_Metallic") && m.GetFloat("_Metallic") > 0f)
                    {
                        m.SetFloat("_Metallic", 0f);
                        changed = true;
                    }
                    if (m.HasProperty("_Smoothness") && m.GetFloat("_Smoothness") > 0.3f)
                    {
                        m.SetFloat("_Smoothness", 0.15f);
                        changed = true;
                    }
                    if (changed) EditorUtility.SetDirty(m);
                }

            if (changed) AssetDatabase.SaveAssets();
            return changed;
        }

        /// Reports what no import setting can repair.
        private static string Vet(string path, StringBuilder report)
        {
            var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (go == null) return "SKIP";

            var clips = AssetDatabase.LoadAllAssetsAtPath(path).OfType<AnimationClip>()
                .Where(c => !c.name.StartsWith("__preview__")).ToArray();
            var renderers = go.GetComponentsInChildren<Renderer>(true);
            bool isAnimationOnly = clips.Length > 0 && renderers.Length == 0;
            if (isAnimationOnly) return "SKIP";                 // pure animation file
            if (renderers.Length == 0) return "SKIP";

            var importer = AssetImporter.GetAtPath(path) as ModelImporter;
            if (importer != null && importer.animationType == ModelImporterAnimationType.Generic)
                return "SKIP";                                   // prop, not a character

            // An animation file ships the rig (and often a preview mesh) but
            // is not a character you would place in a level - judging it as
            // one produces meaningless rejections.
            if (clips.Length > 0 && go.GetComponentsInChildren<SkinnedMeshRenderer>(true).Length == 0)
                return "SKIP";

            string name = Path.GetFileName(path);
            var animator = go.GetComponent<Animator>();
            bool human = animator != null && animator.avatar != null && animator.avatar.isHuman;

            if (!human)
            {
                report.AppendLine($"REJECT {name}: no usable humanoid skeleton - cannot be animated");
                return "REJECT";
            }

            var problems = new List<string>();

            // Finger coverage decides whether grips (flashlight, tools) can work.
            HumanBodyBones[] fingers = {
                HumanBodyBones.RightThumbProximal, HumanBodyBones.RightThumbIntermediate, HumanBodyBones.RightThumbDistal,
                HumanBodyBones.RightIndexProximal, HumanBodyBones.RightIndexIntermediate, HumanBodyBones.RightIndexDistal,
                HumanBodyBones.RightMiddleProximal, HumanBodyBones.RightMiddleIntermediate, HumanBodyBones.RightMiddleDistal,
                HumanBodyBones.RightRingProximal, HumanBodyBones.RightRingIntermediate, HumanBodyBones.RightRingDistal,
                HumanBodyBones.RightLittleProximal, HumanBodyBones.RightLittleIntermediate, HumanBodyBones.RightLittleDistal };

            var probe = (GameObject)PrefabUtility.InstantiatePrefab(go);
            int fingerCount = 0;
            try
            {
                var a = probe.GetComponent<Animator>();
                fingerCount = fingers.Count(b => a.GetBoneTransform(b) != null);
            }
            finally { Object.DestroyImmediate(probe); }

            if (fingerCount < 15)
                problems.Add($"only {fingerCount}/15 right-hand finger bones - held props will not grip properly");

            // Blank placeholder colour maps: real rig, but the art never shipped.
            int blank = 0, missing = 0;
            var checkedTex = new HashSet<Texture>();
            foreach (var r in renderers)
                foreach (var m in r.sharedMaterials)
                {
                    if (m == null) continue;
                    var t = m.HasProperty("_BaseMap") ? m.GetTexture("_BaseMap") : null;
                    if (t == null) { missing++; continue; }
                    if (!checkedTex.Add(t)) continue;
                    if (IsPlaceholder(t)) blank++;
                }
            if (missing > 0) problems.Add($"{missing} material slot(s) with no colour texture");
            if (blank > 0) problems.Add($"{blank} colour texture(s) are flat placeholders, not real art");

            if (problems.Count == 0)
            {
                report.AppendLine($"OK     {name}: humanoid, {fingerCount}/15 fingers, textures bound");
                return "OK";
            }

            report.AppendLine($"WARN   {name}: " + string.Join("; ", problems));
            return "WARN";
        }

        /// A tiny, single-colour image is a stand-in the author exported
        /// instead of the real map - the model can never look right from it.
        private static bool IsPlaceholder(Texture t)
        {
            string p = AssetDatabase.GetAssetPath(t);
            if (string.IsNullOrEmpty(p) || !File.Exists(p)) return false;
            var info = new FileInfo(p);
            return info.Length < 5000 && t.width <= 256 && t.height <= 256;
        }
    }
}
