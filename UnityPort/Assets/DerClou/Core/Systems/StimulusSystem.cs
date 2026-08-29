namespace DerClou.Core.Systems
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;

    /// U7 start: deterministic noise broadcast. A single authoritative
    /// mutation point, mirroring DoorSystem.SetOpen — an immediate one-shot
    /// call rather than a per-frame poll, since a noise event is a discrete
    /// moment, not a persisting field to evaluate every tick.
    public static class StimulusSystem
    {
        // Straight-line distance is an approximation of the true path
        // length through the portal a sound crossed; per-hop attenuation
        // keeps that approximation honest without computing an exact
        // corridor distance. A closed/locked door is not attenuated, it is
        // an outright block — RoomPortalGraph.TryFindRoute already excludes
        // that edge entirely.
        private const float PerPortalAttenuation = 3f;

        /// Every un-alerted guard whose room graph distance from the noise
        /// falls within its attenuated radius breaks patrol and walks to
        /// investigate. Same room = no attenuation. Unreachable (blocked by
        /// a closed door, or no level topology at all) = no propagation.
        /// GuardPatrolSystem's existing Alert-state handling (arrival, look
        /// duration, ResumeAtNearestPatrolNode) owns the rest of the
        /// behavior once isAlerted is set here.
        public static void EmitNoise(MissionState state, WorldPoint position, float radius)
        {
            if (state == null) return;
            var rooms = state.Topology?.rooms;

            var ids = state.GuardIdScratch;
            ids.Clear();
            foreach (var id in state.Guards.Keys) ids.Add(id);
            ids.Sort();

            foreach (var guardActorId in ids)
            {
                if (!state.Actors.TryGetValue(guardActorId, out var actor)) continue;
                var guard = state.Guards[guardActorId];
                if (guard.isAlerted) continue;

                float dx = actor.Position.x - position.x;
                float dz = actor.Position.z - position.z;
                float distance = System.MathF.Sqrt(dx * dx + dz * dz);

                float effectiveRadius = radius;
                if (rooms != null)
                {
                    if (!rooms.TryFindRoute(position, actor.Position, state.Doors, false, out var route))
                        continue; // no open path for sound to travel through
                    effectiveRadius = System.MathF.Max(0f, radius - route.portalIds.Length * PerPortalAttenuation);
                }

                if (distance > effectiveRadius) continue;

                TriggerInvestigate(state, guardActorId, position);
            }
        }

        /// Shared entry point for anything that should break an un-alerted
        /// guard's patrol and send it to look at a location — used by
        /// EmitNoise above and by EvidenceSystem's disabled-camera check.
        /// A no-op if the guard is already alerted, so a second stimulus
        /// never interrupts an investigation already in progress.
        public static void TriggerInvestigate(MissionState state, int guardActorId, WorldPoint position)
        {
            if (!state.Guards.TryGetValue(guardActorId, out var guard) || guard.isAlerted) return;

            guard.isAlerted = true;
            guard.state = GuardState.State.Alert;
            guard.investigateTarget = position;
            guard.investigateArrivedTime = 0f;
            state.Guards[guardActorId] = guard;

            ActorMovementSystem.RequestPath(state, guardActorId, position, true);
        }
    }
}
