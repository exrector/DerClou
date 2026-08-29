using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using System;
using System.Collections.Generic;
using System.Linq;

public static class NativeStandRebuilder
{
    [MenuItem("DerClou/Character Review/Rebuild Native Package Stand")]
    public static void Build()
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var root = new GameObject("NativePackageCharacterStand");
        var packages = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var guid in AssetDatabase.FindAssets("t:Prefab"))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid);
            var parts = path.Split('/');
            if (parts.Length < 3 || parts[1] == "DerClou" || parts[1] == "Flashlight") continue;
            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (!prefab || !prefab.GetComponentsInChildren<Animator>(true).Any()) continue;
            var meshes = prefab.GetComponentsInChildren<SkinnedMeshRenderer>(true)
                .Where(r => r.sharedMesh && r.sharedMesh.vertexCount > 1000).ToArray();
            if (meshes.Length == 0) continue;
            var score = meshes.Sum(r => r.sharedMesh.vertexCount);
            if (!packages.ContainsKey(parts[1])) packages[parts[1]] = path;
            else
            {
                var old = AssetDatabase.LoadAssetAtPath<GameObject>(packages[parts[1]]);
                var oldScore = old ? old.GetComponentsInChildren<SkinnedMeshRenderer>(true).Where(r => r.sharedMesh).Sum(r => r.sharedMesh.vertexCount) : 0;
                if (score > oldScore) packages[parts[1]] = path;
            }
        }
        int index = 0;
        foreach (var item in packages.OrderBy(x => x.Key))
        {
            var go = PrefabUtility.InstantiatePrefab(AssetDatabase.LoadAssetAtPath<GameObject>(item.Value)) as GameObject;
            if (!go) continue;
            go.name = "Package_" + item.Key.Replace(" ", "_");
            go.transform.SetParent(root.transform);
            foreach (var behaviour in go.GetComponentsInChildren<MonoBehaviour>(true)) behaviour.enabled = false;
            var renderers = go.GetComponentsInChildren<Renderer>(true);
            var bounds = new Bounds(go.transform.position, Vector3.zero);
            foreach (var r in renderers) bounds.Encapsulate(r.bounds);
            if (bounds.size.y < 1f) { UnityEngine.Object.DestroyImmediate(go); continue; }
            go.transform.localScale = Vector3.one * (1.8f / Mathf.Max(.01f, bounds.size.y));
            bounds = new Bounds(go.transform.position, Vector3.zero);
            foreach (var r in renderers) bounds.Encapsulate(r.bounds);
            int col = index % 4, row = index / 4;
            go.transform.position = new Vector3((col - 1.5f) * 3.2f, -bounds.min.y, -row * 3.4f);
            var label = new GameObject("Label_" + index);
            label.transform.position = go.transform.position + Vector3.up * 2f;
            var text = label.AddComponent<TextMesh>();
            text.text = item.Key;
            text.characterSize = .16f; text.anchor = TextAnchor.MiddleCenter; text.alignment = TextAlignment.Center; text.color = Color.white;
            index++;
        }
        var floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
        int rows = Mathf.Max(1, (index + 3) / 4);
        floor.transform.position = new Vector3(0, -.05f, -(rows - 1) * 1.7f);
        floor.transform.localScale = new Vector3(14, .1f, rows * 3.4f + 2);
        var camera = new GameObject("NativePackageStandCamera").AddComponent<Camera>();
        camera.transform.position = new Vector3(0, 3f, 11f); camera.transform.LookAt(new Vector3(0, .9f, -(rows - 1) * 1.7f));
        camera.orthographic = true; camera.orthographicSize = Mathf.Max(3.2f, rows * 2.1f);
        var light = new GameObject("NativePackageStandLight").AddComponent<Light>(); light.type = LightType.Directional; light.intensity = 1.5f; light.transform.rotation = Quaternion.Euler(35, -25, 0);
        RenderSettings.ambientLight = Color.gray;
        EditorSceneManager.SaveScene(scene, "Assets/DerClou/CharacterReview/NativePackageCharacterStand.unity");
        AssetDatabase.SaveAssets(); AssetDatabase.Refresh(); Debug.Log("Native package stand rebuilt: " + index);
    }
}
