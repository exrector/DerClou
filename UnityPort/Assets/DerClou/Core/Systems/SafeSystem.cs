namespace DerClou.Core.Systems
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;

    /// <summary>
    /// Advances safe-cracking progress by one fixed step, for whichever safe
    /// (if any) has <see cref="SafeState.isBeingCracked"/> set. Pure C# port
    /// of <c>Safe.StartCracking(dt)</c> plus the proximity-interrupt check
    /// that used to live in <c>InteractionSystem.Update()</c> comparing two
    /// Transforms directly — both now against <see cref="SafeState"/> and a
    /// step size <see cref="SimulationStep"/> controls. See
    /// `docs/U2_SIMULATION_DESIGN.md` step 2e, the last of U2's five slices.
    /// </summary>
    public static class SafeSystem
    {
        // Matches `InteractionSystem.InteractRange` — the same "close enough
        // to interact" distance governs both starting and continuing to
        // crack a safe. Not read from there directly to avoid a pure-C#
        // system depending on a Gameplay-side MonoBehaviour constant.
        public const float InteractRange = 1.6f;

        // U7: the mechanical clunk of the bolt disengaging, not the quiet
        // work leading up to it — the moment worth a guard's attention.
        // Loud enough to carry through one open doorway to a guard on
        // patrol nearby, not loud enough to reach the far side of the map.
        private const float SafeOpenNoiseRadius = 16f;

        public static void Tick(MissionState state, float dt)
        {
            var ids = new List<string>(state.Safes.Keys);
            foreach (var id in ids)
            {
                var s = state.Safes[id];
                if (!s.isBeingCracked) continue;

                bool actorGone = !state.Actors.TryGetValue(s.crackingActorId, out var actor);
                if (actorGone || PlanarDistance(actor.Position, s.position) > InteractRange)
                {
                    s.isBeingCracked = false;
                    s.crackingActorId = -1;
                    state.Safes[id] = s;
                    continue;
                }

                s.crackProgress = MathF.Min(1f, s.crackProgress + dt / s.crackDurationSeconds);
                bool justOpened = s.crackProgress >= 1f && !s.isOpen;
                if (s.crackProgress >= 1f)
                {
                    s.isLocked = false;
                    s.isOpen = true;
                    s.isBeingCracked = false;
                    s.crackingActorId = -1;
                }
                state.Safes[id] = s;
                if (justOpened) StimulusSystem.EmitNoise(state, s.position, SafeOpenNoiseRadius);
            }
        }

        public static void StartCracking(MissionState state, string safeId, int actorId)
        {
            if (!state.Safes.TryGetValue(safeId, out var s) || s.isOpen) return;
            s.isBeingCracked = true;
            s.crackingActorId = actorId;
            state.Safes[safeId] = s;
        }

        /// Developer-sandbox test entry point: skips the walk-there/wait
        /// duration and proximity requirement that `Tick` enforces for a
        /// real crack, but fires through the exact same "just opened"
        /// noise event a real crack does — for verifying guard reaction
        /// without waiting out crackDurationSeconds.
        public static void ForceOpenForTest(MissionState state, string safeId)
        {
            if (state == null || !state.Safes.TryGetValue(safeId, out var s) || s.isOpen) return;
            s.isLocked = false;
            s.isOpen = true;
            s.isBeingCracked = false;
            s.crackingActorId = -1;
            s.crackProgress = 1f;
            state.Safes[safeId] = s;
            StimulusSystem.EmitNoise(state, s.position, SafeOpenNoiseRadius);
        }

        private static float PlanarDistance(WorldPoint a, WorldPoint b)
        {
            float dx = a.x - b.x, dz = a.z - b.z;
            return MathF.Sqrt(dx * dx + dz * dz);
        }
    }
}
