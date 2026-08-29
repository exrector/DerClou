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
            if (d.isOpen == open) return;
            d.isOpen = open;
            state.Doors[doorId] = d;
            SynchronizeNavigation(state, d);
            SynchronizeVisionOccluder(state, d);
            state.Topology?.PublishDoorChange(doorId);
        }

        /// One authoritative 2D mutation for every door transition. Unity's
        /// hinge/obstacle are presentation and spatial-query mirrors; actors,
        /// vision and deterministic retry all consume this state first.
        public static void SynchronizeNavigation(MissionState state, DoorState door)
        {
            if (state?.Grid == null || state.ImmutableBaseGrid == null || door == null) return;
            state.Grid.ApplyLocalBoxOccupancy(
                state.ImmutableBaseGrid,
                door.footprint,
                !door.isOpen,
                Data.CharacterProfile.Standard.Radius + 0.08f);
        }

        /// Closed doors are opaque gameplay geometry. Keeping this mutation
        /// beside the authoritative state transition prevents navigation,
        /// detection and the technical overlay from disagreeing.
        public static void SynchronizeVisionOccluder(MissionState state, DoorState door)
        {
            if (state == null || state.VisionOccluders == null || door == null) return;
            state.VisionOccluders.RemoveAll(box => box.sourceID == door.id);
            if (door.isOpen) return;
            var footprint = door.footprint;
            footprint.sourceID = door.id;
            state.VisionOccluders.Add(footprint);
        }

        private static float MoveTowards(float current, float target, float maxDelta)
        {
            if (MathF.Abs(target - current) <= maxDelta) return target;
            return current + MathF.Sign(target - current) * maxDelta;
        }
    }
}
