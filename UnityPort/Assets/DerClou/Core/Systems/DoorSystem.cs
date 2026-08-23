namespace DerClou.Core.Systems
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Simulation;

    /// <summary>
    /// Advances every door's open/close animation by one fixed step. Pure C#
    /// port of the old <c>Door.Update()</c> — same
    /// <c>Mathf.MoveTowards</c>-style progress toward the target, same
    /// separate open/close durations — now against <see cref="DoorState"/>
    /// and a step size <see cref="SimulationStep"/> controls instead of
    /// <c>Time.deltaTime</c>. See `docs/U2_SIMULATION_DESIGN.md` step 2d.
    /// </summary>
    public static class DoorSystem
    {
        public static void Tick(MissionState state, float dt)
        {
            var ids = new List<string>(state.Doors.Keys);
            foreach (var id in ids)
            {
                var d = state.Doors[id];
                float target = d.isOpen ? 1f : 0f;
                float duration = d.isOpen ? d.openDurationSeconds : d.closeDurationSeconds;
                float speed = duration > 0f ? 1f / duration : float.PositiveInfinity;
                d.openProgress = MoveTowards(d.openProgress, target, speed * dt);
                state.Doors[id] = d;
            }
        }

        /// Requests the door open or closed. Unlike the old MonoBehaviour
        /// (which ignored a direction change while an opposite animation was
        /// still in progress), this lets a new request reverse the door
        /// mid-swing — simpler than reproducing the old blocking guard, and
        /// nothing in this project currently depends on that block existing.
        public static void SetOpen(MissionState state, string doorId, bool open)
        {
            if (!state.Doors.TryGetValue(doorId, out var d)) return;
            d.isOpen = open;
            state.Doors[doorId] = d;
        }

        private static float MoveTowards(float current, float target, float maxDelta)
        {
            if (MathF.Abs(target - current) <= maxDelta) return target;
            return current + MathF.Sign(target - current) * maxDelta;
        }
    }
}
