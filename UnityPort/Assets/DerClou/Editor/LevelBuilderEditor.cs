namespace DerClou.Editor
{
    using DerClou.Core.Data;
    using DerClou.Gameplay.Level;
    using UnityEditor;
    using UnityEngine;

    [CustomEditor(typeof(LevelBuilder))]
    public class LevelBuilderEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            base.OnInspectorGUI();

            var builder = (LevelBuilder)target;
            if (GUILayout.Button("Build Level"))
            {
                var blueprintObj = FindObjectOfType<Level01Builder>();
                if (blueprintObj != null && blueprintObj.blueprint != null)
                {
                    var catalog = PropCatalog.Standard;
                    builder.Build(blueprintObj.blueprint, catalog);
                }
                else
                {
                    Debug.LogWarning("No Level01Builder with blueprint found in scene.");
                }
            }

            if (GUILayout.Button("Clear Level"))
            {
                var spawned = builder.GetType().GetField("spawnedObjects", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
                if (spawned != null)
                {
                    var list = spawned.GetValue(builder) as System.Collections.Generic.List<GameObject>;
                    if (list != null)
                    {
                        foreach (var obj in list) if (obj != null) DestroyImmediate(obj);
                        list.Clear();
                    }
                }
            }
        }
    }

    [CustomEditor(typeof(Level01Builder))]
    public class Level01BuilderEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            base.OnInspectorGUI();
            if (GUILayout.Button("Generate Level01"))
            {
                ((Level01Builder)target).Generate();
                EditorUtility.SetDirty(target);
            }
        }
    }
}