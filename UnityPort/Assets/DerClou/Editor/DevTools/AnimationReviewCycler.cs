namespace DerClou.Editor.DevTools
{
    using System.Collections.Generic;
    using UnityEditor;
    using UnityEngine;

    /// Editor-only, Play-mode-free animation review tool. Puts exactly ONE
    /// character at a fixed stand position and cycles it through a list of
    /// AnimationClips in place using AnimationMode sampling, advanced every
    /// editor tick via EditorApplication.update. Deliberately never enters
    /// Play mode, so GameBootstrap/DeveloperSandboxLevelBuilder never run and
    /// gameplay pawns never spawn -- this is the only actor
    /// visible while reviewing. This is the permanent "CharacterTestStand"
    /// tool: swap the mounted character/clip list and call Begin() again to
    /// try the next candidate. Safe to leave in the project; Stop() cleans up
    /// AnimationMode state completely.
    [InitializeOnLoad]
    public static class AnimationReviewCycler
    {
        private static GameObject target;
        private static List<AnimationClip> clips = new List<AnimationClip>();
        private static int index;
        private static double clipStartTime;
        private static double holdSeconds = 3.0;
        private static bool running;
        private static string lastLoggedName;
        private static Vector3 standPosition;
        private static Quaternion standRotation;

        static AnimationReviewCycler()
        {
            EditorApplication.update -= Tick;
            EditorApplication.update += Tick;
        }

        public static void Begin(GameObject characterInstance, List<AnimationClip> clipList, double perClipSeconds)
        {
            Stop();
            target = characterInstance;
            standPosition = target != null ? target.transform.position : Vector3.zero;
            standRotation = target != null ? target.transform.rotation : Quaternion.identity;
            clips = clipList ?? new List<AnimationClip>();
            index = 0;
            holdSeconds = perClipSeconds;
            clipStartTime = EditorApplication.timeSinceStartup;
            lastLoggedName = null;
            running = clips.Count > 0 && target != null;

            if (running && !AnimationMode.InAnimationMode())
                AnimationMode.StartAnimationMode();
        }

        public static void Stop()
        {
            running = false;
            if (AnimationMode.InAnimationMode())
                AnimationMode.StopAnimationMode();
        }

        private static void Tick()
        {
            if (!running || target == null || clips.Count == 0) return;

            double elapsed = EditorApplication.timeSinceStartup - clipStartTime;
            var clip = clips[index];

            if (elapsed > holdSeconds)
            {
                index = (index + 1) % clips.Count;
                clipStartTime = EditorApplication.timeSinceStartup;
                elapsed = 0;
                clip = clips[index];
            }

            if (clip.name != lastLoggedName)
            {
                lastLoggedName = clip.name;
                Debug.Log($"[AnimationReviewCycler] {index + 1}/{clips.Count}: {clip.name}");
            }

            float t = clip.isLooping ? (float)(elapsed % Mathf.Max(clip.length, 0.01f)) : Mathf.Min((float)elapsed, clip.length);

            AnimationMode.BeginSampling();
            AnimationMode.SampleAnimationClip(target, clip, t);
            AnimationMode.EndSampling();

            // Root-motion clips (walk/jog/run etc.) bake position/rotation
            // curves onto the root transform; SampleAnimationClip applies
            // them like any other animated property, which drags the stand
            // away from its authored spot. Pin the root back every tick so
            // "review in place" actually stays in place regardless of what
            // the clip itself does with its root.
            target.transform.position = standPosition;
            target.transform.rotation = standRotation;

            if (SceneView.lastActiveSceneView != null)
                SceneView.RepaintAll();
        }
    }
}
