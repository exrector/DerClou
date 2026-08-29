namespace DerClou.Editor
{
    using DerClou.Gameplay.Camera;
    using UnityEditor;
    using UnityEngine;

    /// <summary>
    /// Authoring bridge between Unity's Scene and Game tabs. It changes only
    /// the presentation camera and never touches level or MissionState data.
    /// </summary>
    [InitializeOnLoad]
    internal static class DioramaSceneViewSync
    {
        private const string LiveSyncPreference = "DerClou.Diorama.LiveSceneViewSync";
        private static Vector3 lastPosition;
        private static Quaternion lastRotation;
        private static float lastProjection;
        private static bool hasSample;

        static DioramaSceneViewSync() => EditorApplication.update += Update;

        [MenuItem("DerClou/Diorama/Apply Scene View to Game Camera")]
        private static void ApplyOnce() => Apply(logResult: true);

        [MenuItem("DerClou/Diorama/Live Sync Scene View to Game")]
        private static void ToggleLiveSync()
        {
            bool enabled = !EditorPrefs.GetBool(LiveSyncPreference, false);
            EditorPrefs.SetBool(LiveSyncPreference, enabled);
            Menu.SetChecked("DerClou/Diorama/Live Sync Scene View to Game", enabled);
            hasSample = false;
            if (enabled) Apply(logResult: true);
        }

        [MenuItem("DerClou/Diorama/Live Sync Scene View to Game", true)]
        private static bool ValidateLiveSync()
        {
            Menu.SetChecked(
                "DerClou/Diorama/Live Sync Scene View to Game",
                EditorPrefs.GetBool(LiveSyncPreference, false));
            return true;
        }

        private static void Update()
        {
            if (!EditorApplication.isPlaying
                || !EditorPrefs.GetBool(LiveSyncPreference, false)) return;
            Apply(logResult: false);
        }

        private static void Apply(bool logResult)
        {
            if (!EditorApplication.isPlaying) return;
            var sceneView = SceneView.lastActiveSceneView;
            var tactical = Object.FindFirstObjectByType<TacticalCamera>();
            if (sceneView == null || sceneView.camera == null || tactical == null) return;

            var source = sceneView.camera;
            float projection = source.orthographic ? source.orthographicSize : source.fieldOfView;
            if (!logResult && hasSample
                && Vector3.SqrMagnitude(source.transform.position - lastPosition) < 0.000001f
                && Quaternion.Angle(source.transform.rotation, lastRotation) < 0.001f
                && Mathf.Abs(projection - lastProjection) < 0.0001f) return;

            tactical.SetAuthoredView(
                source.transform.position,
                source.transform.rotation,
                source.orthographic,
                projection);
            lastPosition = source.transform.position;
            lastRotation = source.transform.rotation;
            lastProjection = projection;
            hasSample = true;
            if (logResult)
                Debug.Log("[Diorama] Game camera now matches the current Scene View. "
                    + "Use DerClou/Diorama; optional live sync is beside this command.");
        }
    }
}
