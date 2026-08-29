namespace DerClou.Core.Systems
{
    using System;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;

    /// <summary>
    /// Advances every actor's position along its current path by one fixed
    /// step. Pure C# port of what <c>ActorEntity.Update()</c> used to do
    /// directly on a Transform every render frame — same algorithm, same
    /// arrival tolerance, same turn-rate clamp, just against
    /// <see cref="ActorState"/> and a step size <see cref="Simulation.SimulationStep"/>
    /// controls instead of <c>Time.deltaTime</c>. See
    /// `docs/U2_SIMULATION_DESIGN.md` step 2a.
    /// </summary>
    public static class ActorMovementSystem
    {
        private const float ArrivalTolerance = 0.05f;
        private const float RequestDedupSqr = 0.01f; // 0.1m — matches the old ActorEntity check

        /// Pathfinds to `goal` and installs the result as the actor's
        /// current path — the shared implementation behind both
        /// `ActorView.SetDestination` (player taps) and
        /// `Systems.GuardPatrolSystem` (patrol routing), so there is exactly
        /// one place that decides how an actor gets from A to B. Idempotent
        /// against repeated identical requests (see `ActorState.HasRequestedDestination`).
        public static void RequestPath(MissionState state, int actorId, WorldPoint goal)
            => RequestPath(state, actorId, goal, false);

        public static void RequestPath(MissionState state, int actorId, WorldPoint goal, bool force)
            => RequestPath(state, actorId, goal, force, false);

        public static void RequestPath(
            MissionState state,
            int actorId,
            WorldPoint goal,
            bool force,
            bool preserveExistingCommitment)
        {
            if (state == null || !state.Actors.TryGetValue(actorId, out var a)) return;

            if (!force && a.HasPath && a.HasRequestedDestination && SqrDistance(goal, a.LastRequestedDestination) < RequestDedupSqr)
                return;

            bool preserveCommitment = preserveExistingCommitment && a.HasRequestedDestination
                || (force && a.HasRequestedDestination
                    && SqrDistance(goal, a.LastRequestedDestination) < RequestDedupSqr);
            a.LastRequestedDestination = goal;
            a.HasRequestedDestination = true;
            if (SqrDistance(goal, a.LastAvoidanceDestination) >= RequestDedupSqr)
                a.HasAvoidanceRecord = false;
            // The request being solved owns a new immutable trajectory from
            // this simulation timestamp. Existing committed routes therefore
            // keep right of way over this one.
            if (!preserveCommitment) a.TrajectoryCommittedAt = state.CurrentTime;

            if (state.Grid == null) { a.HasPath = false; state.Actors[actorId] = a; return; }

            // Coarse room/portal feasibility before the local grid solve.
            // Raw movement may cross only currently open portals; U6 will
            // request the same route with operable closed doors included and
            // compile the required open/unlock actions.
            RoomRoute coarseRoute = default;
            bool hasRoomGraph = state.Topology?.rooms != null
                && state.Topology.rooms.Rooms.Count > 0;
            if (hasRoomGraph
                && !state.Topology.rooms.TryFindRoute(
                    a.Position, goal, state.Doors, false, out coarseRoute))
            {
                a.HasPath = false;
                a.CurrentPath = null;
                a.CurrentSpeed = 0f;
                a.PortalDependencies = null;
                a.PortalDependencyRevisions = null;
                state.Actors[actorId] = a;
                return;
            }

            var planningGrid = BuildAvoidanceGrid(state, actorId, a, goal);
            var path = FindSpatialCorridor(state, planningGrid, a.Position, goal);
            if (path.Length == 0) { a.HasPath = false; state.Actors[actorId] = a; return; }

            a.CurrentPath = TrajectoryBuilder.Continuous(a.Position, path, a.FacingYawDegrees, planningGrid, a.Profile);
            a.PathIndex = 0;
            a.HasPath = true;
            if (hasRoomGraph)
            {
                a.PortalDependencies = coarseRoute.portalIds;
                a.PortalDependencyRevisions = new uint[coarseRoute.portalIds.Length];
                for (int i = 0; i < coarseRoute.portalIds.Length; i++)
                    a.PortalDependencyRevisions[i] = state.Topology.rooms.GetPortalRevision(coarseRoute.portalIds[i]);
            }
            else
            {
                a.PortalDependencies = null;
                a.PortalDependencyRevisions = null;
            }
            if (!preserveCommitment) a.TrajectoryCommittedAt = state.CurrentTime;
            a.RouteRevision++;
            state.Actors[actorId] = a;
        }

        /// Compiles an engine-provided or grid-fallback corridor into the
        /// exact smooth trajectory stored by PlanAction. No actor state is
        /// mutated while Planning.
        public static WorldPoint[] BuildFrozenTrajectory(
            MissionState state,
            int actorId,
            WorldPoint start,
            float initialFacing,
            WorldPoint goal)
        {
            if (state == null || state.Grid == null
                || !state.Actors.TryGetValue(actorId, out var actor))
                return Array.Empty<WorldPoint>();

            if (state.Topology?.rooms != null && state.Topology.rooms.Rooms.Count > 0
                && !state.Topology.rooms.TryFindRoute(
                    start, goal, state.Doors, false, out _))
                return Array.Empty<WorldPoint>();

            actor.Position = start;
            actor.FacingYawDegrees = initialFacing;
            var planningGrid = BuildAvoidanceGrid(state, actorId, actor, goal);
            var corridor = FindSpatialCorridor(state, planningGrid, start, goal);
            if (corridor.Length == 0) return corridor;
            return TrajectoryBuilder.Continuous(
                start, corridor, initialFacing, planningGrid, actor.Profile);
        }

        /// Installs a copy of an already compiled trajectory. This is the
        /// deterministic Execute path: no NavMesh/A* query occurs here.
        public static void InstallFrozenTrajectory(
            MissionState state,
            int actorId,
            WorldPoint goal,
            WorldPoint[] trajectory)
        {
            if (state == null || trajectory == null || trajectory.Length == 0
                || !state.Actors.TryGetValue(actorId, out var actor)) return;
            actor.LastRequestedDestination = goal;
            actor.HasRequestedDestination = true;
            actor.HasAvoidanceRecord = false;
            actor.CurrentPath = (WorldPoint[])trajectory.Clone();
            actor.PathIndex = 0;
            actor.HasPath = true;
            actor.ManualControl = false;
            actor.TrajectoryCommittedAt = state.CurrentTime;
            actor.PortalDependencies = null;
            actor.PortalDependencyRevisions = null;
            actor.RouteRevision++;
            state.Actors[actorId] = actor;
        }

        private static WorldPoint[] FindSpatialCorridor(
            MissionState state,
            NavGrid planningGrid,
            WorldPoint start,
            WorldPoint goal)
        {
            if (state.SpatialCorridors != null
                && state.SpatialCorridors.TryFindCorridor(start, goal, out var standard)
                && standard != null && standard.Length > 0
                && IsCorridorLegal(planningGrid, start, standard))
                return standard;
            return PathFinder.FindPath(planningGrid, start, goal);
        }

        private static bool IsCorridorLegal(
            NavGrid grid,
            WorldPoint start,
            WorldPoint[] corridor)
        {
            var previous = start;
            foreach (var point in corridor)
            {
                if (!PathFinder.HasLineOfSight(grid, previous, point)) return false;
                previous = point;
            }
            return true;
        }

        public static void Stop(MissionState state, int actorId)
        {
            if (state == null || !state.Actors.TryGetValue(actorId, out var a)) return;
            a.HasPath = false;
            a.CurrentPath = null;
            a.CurrentSpeed = 0f;
            a.PortalDependencies = null;
            a.PortalDependencyRevisions = null;
            state.Actors[actorId] = a;
        }

        /// Replaces an unreachable authored landmark with one
        /// smooth inner-sector maneuver around its occupied footprint and
        /// continues directly to the following landmark. The blocked node
        /// still shapes the route; only the impossible requirement to stand
        /// on its exact coordinate is removed.
        public static void RequestTangentPastOccupiedLandmark(
            MissionState state,
            int actorId,
            WorldPoint destination,
            int blockerId,
            WorldPoint blockerPosition,
            float blockerRadius)
        {
            if (state == null || state.Grid == null
                || !state.Actors.TryGetValue(actorId, out var actor)) return;

            float clearance = actor.Profile.Radius + blockerRadius + 0.08f;
            if (TangentDetourPlanner.TryBuildInsideCorner(
                    actor.Position, destination, actor.FacingYawDegrees,
                    blockerPosition, clearance, state.Grid, actor.Profile,
                    out var detour))
            {
                actor.LastRequestedDestination = destination;
                actor.HasRequestedDestination = true;
                actor.HasAvoidanceRecord = true;
                actor.LastAvoidedActorId = blockerId;
                actor.LastAvoidedActorPosition = blockerPosition;
                actor.LastAvoidanceDestination = destination;
                actor.CurrentPath = detour;
                actor.PathIndex = 0;
                actor.HasPath = true;
                actor.RouteRevision++;
                state.Actors[actorId] = actor;
                return;
            }

            // Geometry such as a nearby wall can invalidate the analytic
            // tangent. The universal grid planner is the deterministic
            // fallback, still preserving the patrol's original commitment.
            RequestPath(state, actorId, destination, true, true);
        }

        private static float SqrDistance(WorldPoint a, WorldPoint b)
        {
            float dx = a.x - b.x, dz = a.z - b.z;
            return dx * dx + dz * dz;
        }

        public static void Tick(MissionState state, float dt)
        {
            // Dictionary<TKey, TValue> with a struct TValue: iterate keys,
            // mutate through indexer — `foreach (var kv in ...)` yields a
            // copy that can't be written back in place.
            var ids = state.ActorIdScratch;
            ids.Clear();
            foreach (var id in state.Actors.Keys) ids.Add(id);
            SortByRightOfWay(state, ids);
            foreach (var id in ids)
            {
                var a = state.Actors[id];
                TickActor(state, id, ref a, dt);
                state.Actors[id] = a;
            }
        }

        private static void TickActor(MissionState state, int actorId, ref ActorState a, float dt)
        {
            if (!a.HasPath || a.CurrentPath == null || a.PathIndex >= a.CurrentPath.Length)
            {
                a.CurrentSpeed = MoveTowards(a.CurrentSpeed, 0f, a.Profile.deceleration * dt);
                return;
            }

            TryInstallUpcomingStationaryDetour(state, actorId, ref a);

            var wp = a.CurrentPath[a.PathIndex];
            float dx = wp.x - a.Position.x;
            float dz = wp.z - a.Position.z;
            float distance = MathF.Sqrt(dx * dx + dz * dz);

            if (distance <= ArrivalTolerance)
            {
                a.PathIndex++;
                if (a.PathIndex >= a.CurrentPath.Length)
                {
                    a.HasPath = false;
                    a.CurrentPath = null;
                    a.CurrentSpeed = 0f;
                    a.ManualControl = false;
                }
                return;
            }

            float dirX = dx / distance, dirZ = dz / distance;
            float targetYaw = MathF.Atan2(dirX, dirZ) * (180f / MathF.PI);
            float turn = MathF.Abs(DeltaAngle(a.FacingYawDegrees, targetYaw));
            a.FacingYawDegrees = a.Profile.maxTurnRateDegrees > 0f
                ? MoveTowardsAngle(a.FacingYawDegrees, targetYaw, a.Profile.maxTurnRateDegrees * dt)
                : targetYaw;

            // A near reversal is an explicit in-place turn. Ordinary changes
            // are already curved by TrajectoryBuilder and continue moving.
            if (turn > 110f)
            {
                a.CurrentSpeed = MoveTowards(a.CurrentSpeed, 0f, a.Profile.deceleration * dt);
                return;
            }

            float remaining = RemainingDistance(a);
            // Maximum speed from which the actor can still stop exactly at
            // the arrival tolerance. Unlike a boolean braking zone this
            // approaches zero continuously and cannot strand the actor a few
            // centimetres before its target.
            float desired = a.Profile.deceleration > 0f
                ? MathF.Min(a.Profile.walkSpeed,
                    MathF.Sqrt(2f * a.Profile.deceleration * MathF.Max(remaining - ArrivalTolerance, 0f)))
                : a.Profile.walkSpeed;
            float rate = desired > a.CurrentSpeed ? a.Profile.acceleration : a.Profile.deceleration;
            a.CurrentSpeed = MoveTowards(a.CurrentSpeed, desired, rate * dt);
            float step = MathF.Min(a.CurrentSpeed * dt, distance);
            var proposed = new WorldPoint(a.Position.x + dirX * step, a.Position.y, a.Position.z + dirZ * step);
            if (WouldOverlap(state, actorId, a.Profile.Radius, proposed, out int blockerId, out var blockerPosition))
            {
                a.CurrentSpeed = 0f;
                var destination = a.LastRequestedDestination;
                bool alreadyHandled = a.HasAvoidanceRecord
                    && a.LastAvoidedActorId == blockerId
                    && SqrDistance(a.LastAvoidedActorPosition, blockerPosition) < 0.0625f
                    && SqrDistance(a.LastAvoidanceDestination, destination) < RequestDedupSqr;
                if (!alreadyHandled)
                {
                    a.HasAvoidanceRecord = true;
                    a.LastAvoidedActorId = blockerId;
                    a.LastAvoidedActorPosition = blockerPosition;
                    a.LastAvoidanceDestination = destination;
                    a.HasPath = false;
                    a.CurrentPath = null;
                    state.Actors[actorId] = a;
                    RequestPath(state, actorId, destination, true);
                    a = state.Actors[actorId];
                }
                return;
            }
            a.Position = proposed;
        }

        private static void TryInstallUpcomingStationaryDetour(
            MissionState state,
            int actorId,
            ref ActorState actor)
        {
            const float lookAheadDistance = 4f;
            if (!TryFindUpcomingStationaryBlocker(
                    state, actorId, actor, lookAheadDistance,
                    out int blockerId, out var blocker)) return;

            var destination = actor.LastRequestedDestination;
            float clearance = actor.Profile.Radius + blocker.Profile.Radius + 0.08f;
            // A body occupying the requested patrol landmark is not a local
            // obstacle around which we should orbit toward an impossible
            // destination. GuardPatrolSystem advances to the following
            // authored node later in this same fixed step, without a throwaway
            // A* solve or a stop.
            if (SqrDistance(blocker.Position, destination) < clearance * clearance) return;
            bool alreadyHandled = actor.HasAvoidanceRecord
                && actor.LastAvoidedActorId == blockerId
                && SqrDistance(actor.LastAvoidedActorPosition, blocker.Position) < 0.0625f
                && SqrDistance(actor.LastAvoidanceDestination, destination) < RequestDedupSqr;
            if (alreadyHandled) return;

            actor.HasAvoidanceRecord = true;
            actor.LastAvoidedActorId = blockerId;
            actor.LastAvoidedActorPosition = blocker.Position;
            actor.LastAvoidanceDestination = destination;
            if (TangentDetourPlanner.TryBuild(
                    actor.Position,
                    destination,
                    actor.FacingYawDegrees,
                    blocker.Position,
                    clearance,
                    state.Grid,
                    actor.Profile,
                    out var detour))
            {
                actor.CurrentPath = detour;
                actor.PathIndex = 0;
                actor.HasPath = true;
                actor.RouteRevision++;
                return;
            }

            // Walls or another obstacle can make the analytic tangent illegal.
            // Fall back once to the global planner while keeping the original
            // corridor ownership and current speed.
            state.Actors[actorId] = actor;
            RequestPath(state, actorId, destination, true, true);
            actor = state.Actors[actorId];
        }

        private static bool TryFindUpcomingStationaryBlocker(
            MissionState state,
            int actorId,
            ActorState actor,
            float lookAheadDistance,
            out int blockerId,
            out ActorState blocker)
        {
            blockerId = 0;
            blocker = default;
            float closestAlong = float.PositiveInfinity;
            foreach (var kv in state.Actors)
            {
                if (kv.Key == actorId) continue;
                var other = kv.Value;
                if (other.HasPath && other.CurrentSpeed > 0.05f) continue;
                float clearance = actor.Profile.Radius + other.Profile.Radius + 0.08f;
                if (!TryClosestDistanceOnRemainingPath(
                        actor, other.Position, out float distance, out float along)) continue;
                if (along < 0.15f || along > lookAheadDistance || distance >= clearance) continue;
                if (along >= closestAlong) continue;
                closestAlong = along;
                blockerId = kv.Key;
                blocker = other;
            }
            return blockerId != 0;
        }

        private static bool TryClosestDistanceOnRemainingPath(
            ActorState actor,
            WorldPoint point,
            out float closestDistance,
            out float distanceAlong)
        {
            closestDistance = float.PositiveInfinity;
            distanceAlong = 0f;
            if (actor.CurrentPath == null || actor.PathIndex >= actor.CurrentPath.Length) return false;
            var from = actor.Position;
            float accumulated = 0f;
            for (int i = actor.PathIndex; i < actor.CurrentPath.Length; i++)
            {
                var to = actor.CurrentPath[i];
                float dx = to.x - from.x, dz = to.z - from.z;
                float lengthSquared = dx * dx + dz * dz;
                float length = MathF.Sqrt(lengthSquared);
                if (length <= 0.000001f) { from = to; continue; }
                float t = ((point.x - from.x) * dx + (point.z - from.z) * dz) / lengthSquared;
                t = MathF.Max(0, MathF.Min(1, t));
                float px = from.x + dx * t - point.x;
                float pz = from.z + dz * t - point.z;
                float distance = MathF.Sqrt(px * px + pz * pz);
                if (distance < closestDistance)
                {
                    closestDistance = distance;
                    distanceAlong = accumulated + length * t;
                }
                accumulated += length;
                from = to;
                if (accumulated > 4.5f && closestDistance < float.PositiveInfinity) break;
            }
            return closestDistance < float.PositiveInfinity;
        }

        private static NavGrid BuildAvoidanceGrid(MissionState state, int actorId, ActorState actor, WorldPoint goal)
        {
            var grid = state.Grid.Clone();
            foreach (var kv in state.Actors)
            {
                if (kv.Key == actorId) continue;
                var other = kv.Value;
                float clearance = actor.Profile.Radius + other.Profile.Radius + 0.08f;
                if (!other.HasPath || other.CurrentPath == null)
                {
                    grid.BlockDisc(other.Position, clearance);
                    continue;
                }

                if (!OwnsRightOfWay(other, actor)) continue;
                if (TryFindPredictedConflict(actor, goal, other, out var meeting))
                    grid.BlockDisc(meeting, clearance);
            }
            return grid;
        }

        private static bool TryFindPredictedConflict(ActorState actor, WorldPoint goal, ActorState other, out WorldPoint meeting)
        {
            const float horizon = 3f;
            const float interval = 0.15f;
            float actorDistance = MathF.Sqrt(SqrDistance(actor.Position, goal));
            for (float t = 0f; t <= horizon; t += interval)
            {
                float actorProgress = actorDistance > 0.0001f ? MathF.Min(1f, actor.Profile.walkSpeed * t / actorDistance) : 1f;
                var candidate = Lerp(actor.Position, goal, actorProgress);
                var reserved = PredictAlongPath(other, t);
                float radius = actor.Profile.Radius + other.Profile.Radius + 0.08f;
                if (SqrDistance(candidate, reserved) < radius * radius) { meeting = reserved; return true; }
            }
            meeting = default; return false;
        }

        private static WorldPoint PredictAlongPath(ActorState actor, float seconds)
        {
            var position = actor.Position;
            float remaining = actor.Profile.walkSpeed * seconds;
            if (actor.CurrentPath == null) return position;
            for (int i = actor.PathIndex; i < actor.CurrentPath.Length && remaining > 0f; i++)
            {
                var target = actor.CurrentPath[i];
                float distance = MathF.Sqrt(SqrDistance(position, target));
                if (distance <= remaining) { position = target; remaining -= distance; }
                else { position = Lerp(position, target, remaining / MathF.Max(distance, 0.0001f)); remaining = 0f; }
            }
            return position;
        }

        private static bool OwnsRightOfWay(ActorState reserved, ActorState requester)
        {
            if (reserved.TrajectoryCommittedAt != requester.TrajectoryCommittedAt)
                return reserved.TrajectoryCommittedAt < requester.TrajectoryCommittedAt;
            if (reserved.AvoidancePriority != requester.AvoidancePriority)
                return reserved.AvoidancePriority < requester.AvoidancePriority;
            return reserved.ActorId < requester.ActorId;
        }

        private static int CompareRightOfWay(ActorState a, ActorState b)
        {
            int time = a.TrajectoryCommittedAt.CompareTo(b.TrajectoryCommittedAt);
            if (time != 0) return time;
            int priority = a.AvoidancePriority.CompareTo(b.AvoidancePriority);
            return priority != 0 ? priority : a.ActorId.CompareTo(b.ActorId);
        }

        // Actor counts are small and this stable insertion sort needs no
        // captured comparison delegate. List.Sort(lambda) allocated a closure
        // every fixed step merely to read MissionState.
        private static void SortByRightOfWay(
            MissionState state,
            System.Collections.Generic.List<int> ids)
        {
            for (int i = 1; i < ids.Count; i++)
            {
                int value = ids[i];
                int cursor = i - 1;
                while (cursor >= 0
                    && CompareRightOfWay(state.Actors[value], state.Actors[ids[cursor]]) < 0)
                {
                    ids[cursor + 1] = ids[cursor];
                    cursor--;
                }
                ids[cursor + 1] = value;
            }
        }

        private static bool WouldOverlap(
            MissionState state,
            int actorId,
            float radius,
            WorldPoint proposed,
            out int blockerId,
            out WorldPoint blockerPosition)
        {
            foreach (var kv in state.Actors)
            {
                if (kv.Key == actorId) continue;
                float minimum = radius + kv.Value.Profile.Radius + 0.02f;
                if (SqrDistance(proposed, kv.Value.Position) < minimum * minimum)
                {
                    blockerId = kv.Key;
                    blockerPosition = kv.Value.Position;
                    return true;
                }
            }
            blockerId = 0;
            blockerPosition = default;
            return false;
        }

        private static float RemainingDistance(ActorState a)
        {
            if (a.CurrentPath == null || a.PathIndex >= a.CurrentPath.Length) return 0f;
            float total = MathF.Sqrt(SqrDistance(a.Position, a.CurrentPath[a.PathIndex]));
            for (int i = a.PathIndex + 1; i < a.CurrentPath.Length; i++) total += MathF.Sqrt(SqrDistance(a.CurrentPath[i - 1], a.CurrentPath[i]));
            return total;
        }

        private static WorldPoint Lerp(WorldPoint a, WorldPoint b, float t) => new WorldPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
        private static float MoveTowards(float current, float target, float maxDelta) => MathF.Abs(target - current) <= maxDelta ? target : current + MathF.Sign(target - current) * maxDelta;

        private static float MoveTowardsAngle(float current, float target, float maxDelta)
        {
            float delta = DeltaAngle(current, target);
            if (-maxDelta < delta && delta < maxDelta) return target;
            return current + MathF.Sign(delta) * maxDelta;
        }

        private static float DeltaAngle(float current, float target)
        {
            float delta = (target - current) % 360f;
            if (delta > 180f) delta -= 360f;
            if (delta < -180f) delta += 360f;
            return delta;
        }
    }
}
