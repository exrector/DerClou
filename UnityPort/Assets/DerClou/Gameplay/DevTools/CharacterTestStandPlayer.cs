namespace DerClou.Gameplay.DevTools
{
    using System.Collections;
    using UnityEngine;
    using UnityEngine.Animations;
    using UnityEngine.Playables;

    /// Runtime half of the character test stand. The editor-side cycler runs
    /// on AnimationMode, which Unity tears down the moment Play starts -- so
    /// pressing Play used to silently kill the review. This component plays
    /// the same clip list through a PlayableGraph during Play, keeping the
    /// stand alive in both modes. Review tool only; not part of the mission
    /// simulation (see CLAUDE.md Core/Presentation split).
    [RequireComponent(typeof(Animator))]
    public sealed class CharacterTestStandPlayer : MonoBehaviour
    {
        public AnimationClip[] clips;
        public float secondsPerClip = 3f;

        private PlayableGraph graph;
        private AnimationClipPlayable current;
        private AnimationPlayableOutput output;
        private Vector3 standPosition;
        private Quaternion standRotation;

        private void Start()
        {
            if (clips == null || clips.Length == 0) return;

            standPosition = transform.position;
            standRotation = transform.rotation;

            graph = PlayableGraph.Create("CharacterTestStandPlayer");
            graph.SetTimeUpdateMode(DirectorUpdateMode.GameTime);
            output = AnimationPlayableOutput.Create(graph, "Output", GetComponent<Animator>());
            graph.Play();

            StartCoroutine(CycleClips());
        }

        private IEnumerator CycleClips()
        {
            int index = 0;
            while (true)
            {
                var clip = clips[index % clips.Length];
                if (clip != null)
                {
                    if (current.IsValid()) current.Destroy();
                    current = AnimationClipPlayable.Create(graph, clip);
                    current.SetApplyFootIK(false);
                    output.SetSourcePlayable(current);
                    Debug.Log($"[CharacterTestStand] {(index % clips.Length) + 1}/{clips.Length}: {clip.name}");
                }
                index++;
                yield return new WaitForSeconds(secondsPerClip);
            }
        }

        private void LateUpdate()
        {
            // Locomotion clips carry root motion; pin the root so the stand
            // reviews animation in place instead of wandering off.
            transform.position = standPosition;
            transform.rotation = standRotation;
        }

        private void OnDestroy()
        {
            if (graph.IsValid()) graph.Destroy();
        }
    }
}
