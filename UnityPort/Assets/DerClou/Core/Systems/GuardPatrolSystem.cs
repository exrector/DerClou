namespace DerClou.Core.Systems
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;

    /// <summary>
    /// Pure C# port of the guard patrol state machine (Moving/Waiting/Acting/
    /// Alert) — U2 step 2b (`docs/U2_SIMULATION_DESIGN.md`). Same algorithm
    /// the old <c>GuardPatrolSystem</c> MonoBehaviour's <c>TickGuard</c> had,
    /// now reading/writing <see cref="GuardState"/> and <see cref="ActorState"/>
    /// through <see cref="MissionState"/> instead of an <c>ActorView</c>'s
    /// Transform — no method here ever touches a Transform or calls a
    /// presentation-side method. <c>GuardView</c> (the renamed MonoBehaviour)
    /// only reads the results back to drive an Animator.
    /// <para>
    /// Must run after <see cref="ActorMovementSystem"/> in the same fixed
    /// step — arrival is judged against the actor position that system just
    /// wrote (`SimulationStep`).
    /// </para>
    /// </summary>
    public static class GuardPatrolSystem
    {
        private const float ArrivalTolerance = 0.2f; // matches the old MonoBehaviour's arrivalTol
        private const float InvestigateLookDuration = 2f;

        public static void Tick(MissionState state, float dt)
        {
            var ids = state.GuardIdScratch;
            ids.Clear();
            foreach (var id in state.Guards.Keys) ids.Add(id);
            ids.Sort();
            foreach (var actorId in ids)
            {
                var guard = state.Guards[actorId];
                TickGuard(state, actorId, ref guard);
                state.Guards[actorId] = guard;
            }
        }

        /// <summary>
        /// Ends an investigation/alert and rejoins the authored patrol at the
        /// nearest reachable, currently unoccupied patrol node. This is an
        /// event operation, not a per-frame search: one A* comparison when
        /// the alert ends, followed by the ordinary patrol state machine.
        /// </summary>
        public static bool ResumeAtNearestPatrolNode(MissionState state, int actorId)
        {
            if (state == null || !state.Guards.TryGetValue(actorId, out var guard)) return false;
            bool resumed = ResumeAtNearestPatrolNode(state, actorId, ref guard);
            state.Guards[actorId] = guard;
            return resumed;
        }

        private static bool ResumeAtNearestPatrolNode(
            MissionState state, int actorId, ref GuardState guard)
        {
            if (state.Grid == null || guard.route == null || guard.route.NodeCount == 0
                || !state.Actors.TryGetValue(actorId, out var actor)) return false;

            int bestIndex = -1;
            float bestLength = float.PositiveInfinity;
            for (int i = 0; i < guard.route.NodeCount; i++)
            {
                var candidate = guard.route.GetNode(i).position;
                if (TryGetTargetBlocker(
                        state, actorId, candidate, actor.Profile.Radius,
                        out _, out _, out _)) continue;
                var path = PathFinder.FindPath(state.Grid, actor.Position, candidate);
                if (path.Length == 0) continue;
                float length = PathLength(actor.Position, path);
                if (length < bestLength - 0.0001f
                    || (System.MathF.Abs(length - bestLength) <= 0.0001f && i < bestIndex))
                {
                    bestIndex = i;
                    bestLength = length;
                }
            }

            if (bestIndex < 0) return false;
            guard.currentNodeIndex = bestIndex;
            guard.state = GuardState.State.Moving;
            guard.isAlerted = false;
            guard.alertLevel = 0f;
            ActorMovementSystem.RequestPath(
                state, actorId, guard.route.GetNode(bestIndex).position, true, false);
            return state.Actors[actorId].HasPath;
        }

        private static float PathLength(WorldPoint start, WorldPoint[] path)
        {
            float total = 0f;
            var previous = start;
            foreach (var point in path)
            {
                float dx = point.x - previous.x, dz = point.z - previous.z;
                total += System.MathF.Sqrt(dx * dx + dz * dz);
                previous = point;
            }
            return total;
        }

        private static void TickGuard(MissionState state, int actorId, ref GuardState guard)
        {
            if (guard.route == null || guard.route.nodes.Length == 0) return;
            if (!state.Actors.TryGetValue(actorId, out var actor)) return;
            if (actor.ManualControl) return;

            var node = guard.route.GetNode(guard.currentNodeIndex);
            var targetPos = node.position;

            // Planar distance, not full 3D: authored node positions carry
            // Y=0, and comparing 3D distance made "arrived" unreachable
            // whenever the actor's own Y diverged even slightly.
            float dx = actor.Position.x - targetPos.x, dz = actor.Position.z - targetPos.z;
            float dist = System.MathF.Sqrt(dx * dx + dz * dz);

            switch (guard.state)
            {
                case GuardState.State.Moving:
                    int skipped = 0;
                    bool hasSkippedBlocker = false;
                    int skippedBlockerId = 0;
                    WorldPoint skippedBlockerPosition = default;
                    float skippedBlockerRadius = 0f;
                    while (TryGetTargetBlocker(
                            state, actorId, targetPos, actor.Profile.Radius,
                            out int blockerId, out var blockerPosition, out float blockerRadius)
                        && skipped < guard.route.NodeCount)
                    {
                        // A patrol node is a routing landmark, not a parking
                        // reservation. If another guard owns it, continue to
                        // the next authored node instead of fighting forever
                        // for an unreachable exact coordinate.
                        if (!hasSkippedBlocker)
                        {
                            hasSkippedBlocker = true;
                            skippedBlockerId = blockerId;
                            skippedBlockerPosition = blockerPosition;
                            skippedBlockerRadius = blockerRadius;
                        }
                        guard.currentNodeIndex = (guard.currentNodeIndex + 1) % guard.route.nodes.Length;
                        skipped++;
                        node = guard.route.GetNode(guard.currentNodeIndex);
                        targetPos = node.position;
                    }
                    if (skipped >= guard.route.NodeCount) return;
                    dx = actor.Position.x - targetPos.x;
                    dz = actor.Position.z - targetPos.z;
                    dist = System.MathF.Sqrt(dx * dx + dz * dz);

                    // All patrol legs belong to the already-authored guard
                    // route. Skipping an occupied landmark or advancing to
                    // the next corner must not surrender its original right
                    // of way, stop its feet, or rejoin the obsolete segment.
                    if (hasSkippedBlocker)
                    {
                        ActorMovementSystem.RequestTangentPastOccupiedLandmark(
                            state, actorId, targetPos,
                            skippedBlockerId, skippedBlockerPosition, skippedBlockerRadius);
                    }
                    else
                    {
                        ActorMovementSystem.RequestPath(
                            state, actorId, targetPos, false,
                            preserveExistingCommitment: actor.HasRequestedDestination);
                    }

                    if (dist <= ArrivalTolerance)
                    {
                        ActorMovementSystem.Stop(state, actorId);
                        guard.state = GuardState.State.Waiting;
                        guard.nodeArrivalTime = state.CurrentTime;
                        if (node.facingYaw >= 0f)
                        {
                            var a = state.Actors[actorId];
                            a.FacingYawDegrees = node.facingYaw;
                            state.Actors[actorId] = a;
                        }
                    }
                    break;

                case GuardState.State.Waiting:
                    float waited = state.CurrentTime - guard.nodeArrivalTime;
                    if (waited >= node.waitDuration)
                    {
                        guard.currentNodeIndex = (guard.currentNodeIndex + 1) % guard.route.nodes.Length;
                        guard.state = GuardState.State.Moving;
                    }
                    break;

                case GuardState.State.Acting:
                    // TODO: handle interaction actions at nodes
                    break;

                case GuardState.State.Alert:
                    // Investigation/chase owns movement while isAlerted is
                    // true. The falling edge is the single deterministic
                    // rejoin event; never force the stale "next" node.
                    if (!guard.isAlerted)
                    {
                        ResumeAtNearestPatrolNode(state, actorId, ref guard);
                        break;
                    }

                    float idx = actor.Position.x - guard.investigateTarget.x;
                    float idz = actor.Position.z - guard.investigateTarget.z;
                    bool arrived = (idx * idx + idz * idz) <= ArrivalTolerance * ArrivalTolerance;

                    if (!arrived)
                    {
                        guard.investigateArrivedTime = 0f;
                        break;
                    }

                    if (guard.investigateArrivedTime <= 0f)
                    {
                        guard.investigateArrivedTime = state.CurrentTime;
                        break;
                    }

                    // Single deterministic "looked around long enough"
                    // event — not a per-frame decay — mirrors how
                    // ResumeAtNearestPatrolNode is only ever evaluated once
                    // on the falling edge, immediately below.
                    if (state.CurrentTime - guard.investigateArrivedTime >= InvestigateLookDuration)
                    {
                        guard.isAlerted = false;
                        guard.investigateArrivedTime = 0f;
                        ResumeAtNearestPatrolNode(state, actorId, ref guard);
                    }
                    break;
            }
        }

        private static bool TryGetTargetBlocker(
            MissionState state,
            int actorId,
            WorldPoint target,
            float radius,
            out int blockerId,
            out WorldPoint blockerPosition,
            out float blockerRadius)
        {
            foreach (var kv in state.Actors)
            {
                if (kv.Key == actorId) continue;
                float dx = kv.Value.Position.x - target.x;
                float dz = kv.Value.Position.z - target.z;
                float minimum = radius + kv.Value.Profile.Radius + 0.08f;
                if (dx * dx + dz * dz >= minimum * minimum) continue;
                blockerId = kv.Key;
                blockerPosition = kv.Value.Position;
                blockerRadius = kv.Value.Profile.Radius;
                return true;
            }
            blockerId = 0;
            blockerPosition = default;
            blockerRadius = 0f;
            return false;
        }
    }
}
