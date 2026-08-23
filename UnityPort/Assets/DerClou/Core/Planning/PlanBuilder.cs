namespace DerClou.Core.Planning
{
    using System;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;

    /// <summary>
    /// What a Planning-phase tap actually calls, per U3
    /// (`docs/U3_PLANNING_LOOP_DESIGN.md`) — appends a <see cref="PlanAction"/>
    /// to the <see cref="MissionPlan"/> and advances the actor's
    /// <see cref="PlanCursor"/>. Never touches <see cref="MissionState"/>
    /// itself (no <c>ActorMovementSystem.RequestPath</c> call, nothing) —
    /// that is the entire point: the actor does not move until Execute
    /// replays the compiled plan.
    /// </summary>
    public static class PlanBuilder
    {
        /// Returns whether a MoveTo was actually queued — `QueueInteract`
        /// needs to know this before deciding whether to append the
        /// interaction action after it (no point queuing "hack the panel" if
        /// there is no route there at all).
        public static bool QueueMove(MissionPlan plan, MissionState state, int actorId,
            ref PlanCursor cursor, WorldPoint destination)
        {
            if (!state.Actors.TryGetValue(actorId, out var actor)) return false;
            if (state.Grid == null) return false;

            var path = PathFinder.FindPath(state.Grid, cursor.Position, destination);
            if (path.Length == 0) return false;

            float distance = PathLength(path, cursor.Position);
            float duration = actor.Profile.walkSpeed > 0f ? distance / actor.Profile.walkSpeed : 0f;

            plan.GetOrCreate(actorId).AddAction(new PlanAction
            {
                type = PlanActionType.MoveTo,
                actorId = actorId,
                targetPos = destination,
                duration = duration,
                earliestStart = cursor.Time,
                parameters = null
            });
            plan.RecalculateDuration();

            cursor = new PlanCursor { Position = destination, Time = cursor.Time + duration };
            return true;
        }

        /// Queues a MoveTo to `targetPos` (reusing <see cref="QueueMove"/>)
        /// followed immediately by the interaction action itself —
        /// `actionType`/`targetId`/`parameters` are already fully resolved
        /// by the caller (Gameplay-side: which `*View` component the tapped
        /// `Interactable` carries, and its config) since this pure-C# method
        /// has no way to inspect a Unity component itself.
        public static void QueueInteract(MissionPlan plan, MissionState state, int actorId,
            ref PlanCursor cursor, WorldPoint targetPos, PlanActionType actionType, string targetId,
            System.Collections.Generic.Dictionary<string, LevelValue> parameters,
            IActionDurationProvider durationProvider)
        {
            if (!state.Actors.TryGetValue(actorId, out var actor)) return;
            if (!QueueMove(plan, state, actorId, ref cursor, targetPos)) return;

            float duration = durationProvider.GetDuration(actionType, actor.Profile, parameters);

            plan.GetOrCreate(actorId).AddAction(new PlanAction
            {
                type = actionType,
                actorId = actorId,
                targetId = targetId,
                targetPos = targetPos,
                duration = duration,
                earliestStart = cursor.Time,
                parameters = parameters
            });
            plan.RecalculateDuration();

            cursor.Time += duration;
        }

        /// Sum of segment lengths through `path`, starting from `from` (the
        /// path itself doesn't include the starting point).
        private static float PathLength(WorldPoint[] path, WorldPoint from)
        {
            float total = 0f;
            var prev = from;
            foreach (var p in path)
            {
                float dx = p.x - prev.x, dz = p.z - prev.z;
                total += MathF.Sqrt(dx * dx + dz * dz);
                prev = p;
            }
            return total;
        }
    }
}
