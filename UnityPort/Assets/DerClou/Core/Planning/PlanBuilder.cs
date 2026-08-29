namespace DerClou.Core.Planning
{
    using System;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;

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

            // A portal is a smart traversal, not an ordinary path segment.
            // Compile its approach/action/exit slots now so Execute never
            // discovers a closed door and replans in the middle of a retry.
            if (state.Topology?.rooms != null
                && state.Topology.rooms.TryFindRoute(
                    cursor.Position, destination, state.Doors, true, out var roomRoute)
                && roomRoute.portalIds != null && roomRoute.portalIds.Length > 0)
                return QueuePortalRoute(plan, state, actorId, actor, ref cursor, destination, roomRoute, true);

            return QueueMoveSegment(plan, state, actorId, actor, ref cursor, destination);
        }

        private static bool QueueMoveSegment(MissionPlan plan, MissionState state, int actorId,
            ActorState actor, ref PlanCursor cursor, WorldPoint destination)
        {
            float initialFacing = cursor.HasFacing
                ? cursor.FacingYawDegrees
                : actor.FacingYawDegrees;
            var path = ActorMovementSystem.BuildFrozenTrajectory(
                state, actorId, cursor.Position, initialFacing, destination);
            if (path.Length == 0) return false;

            float distance = PathLength(path, cursor.Position);
            float duration = actor.Profile.walkSpeed > 0f ? distance / actor.Profile.walkSpeed : 0f;

            plan.GetOrCreate(actorId).AddAction(new PlanAction
            {
                type = PlanActionType.MoveTo,
                actorId = actorId,
                targetPos = destination,
                frozenTrajectory = path,
                duration = duration,
                earliestStart = cursor.Time,
                parameters = null
            });
            plan.RecalculateDuration();

            cursor = new PlanCursor
            {
                Position = destination,
                Time = cursor.Time + duration,
                FacingYawDegrees = FinalFacing(cursor.Position, path, initialFacing),
                HasFacing = true
            };
            return true;
        }

        private static bool QueuePortalRoute(
            MissionPlan plan,
            MissionState state,
            int actorId,
            ActorState actor,
            ref PlanCursor cursor,
            WorldPoint destination,
            RoomRoute route,
            bool closeAfterTraversal)
        {
            var actorPlan = plan.GetOrCreate(actorId);
            int originalCount = actorPlan.actions.Count;
            var originalCursor = cursor;
            string currentRoom = route.roomIds[0];

            for (int i = 0; i < route.portalIds.Length; i++)
            {
                if (!state.Topology.rooms.TryGetPortal(route.portalIds[i], out var portal))
                    return Rollback(actorPlan, originalCount, ref cursor, originalCursor);

                bool fromA = portal.roomAId == currentRoom;
                string nextRoom = fromA ? portal.roomBId : portal.roomAId;
                var fromRoom = FindRoom(state.Topology.rooms, currentRoom);
                var toRoom = FindRoom(state.Topology.rooms, nextRoom);
                if (fromRoom.id == null || toRoom.id == null)
                    return Rollback(actorPlan, originalCount, ref cursor, originalCursor);

                float dx = toRoom.bounds.centerX - fromRoom.bounds.centerX;
                float dz = toRoom.bounds.centerZ - fromRoom.bounds.centerZ;
                float length = MathF.Sqrt(dx * dx + dz * dz);
                if (length < 0.0001f || portal.width < actor.Profile.Radius * 2f + 0.1f)
                    return Rollback(actorPlan, originalCount, ref cursor, originalCursor);
                dx /= length;
                dz /= length;

                float slotOffset = MathF.Max(actor.Profile.Radius + 0.28f, 0.62f);
                var approach = new WorldPoint(portal.position.x - dx * slotOffset, 0f, portal.position.z - dz * slotOffset);
                var exit = new WorldPoint(portal.position.x + dx * slotOffset, 0f, portal.position.z + dz * slotOffset);
                if (!QueueMoveSegment(plan, state, actorId, actor, ref cursor, approach))
                    return Rollback(actorPlan, originalCount, ref cursor, originalCursor);

                float facing = MathF.Atan2(dx, dz) * 180f / MathF.PI;
                float turn = MathF.Abs(DeltaAngle(cursor.FacingYawDegrees, facing));
                float alignDuration = actor.Profile.maxTurnRateDegrees > 0f
                    ? turn / actor.Profile.maxTurnRateDegrees : 0f;
                AddAction(actorPlan, actorId, PlanActionType.Align, portal.id, approach,
                    alignDuration, cursor.Time,
                    new System.Collections.Generic.Dictionary<string, LevelValue>
                    {
                        ["facingYaw"] = LevelValue.Float(facing),
                        ["duration"] = LevelValue.Float(alignDuration)
                    });
                cursor.Time += alignDuration;
                cursor.FacingYawDegrees = facing;
                cursor.HasFacing = true;

                DoorState door = null;
                if (!string.IsNullOrEmpty(portal.doorId))
                    state.Doors.TryGetValue(portal.doorId, out door);
                bool wasClosed = door != null && !door.isOpen;
                if (wasClosed)
                {
                    if (door.isLocked)
                        return Rollback(actorPlan, originalCount, ref cursor, originalCursor);
                    float openDuration = door.openDurationSeconds;
                    AddAction(actorPlan, actorId, PlanActionType.OpenDoor, portal.doorId,
                        approach, openDuration, cursor.Time, null);
                    cursor.Time += openDuration;
                }

                float traverseDistance = slotOffset * 2f;
                float traverseDuration = actor.Profile.walkSpeed > 0f
                    ? traverseDistance / actor.Profile.walkSpeed : 0f;
                AddAction(actorPlan, actorId, PlanActionType.TraversePortal, portal.id, exit,
                    traverseDuration, cursor.Time, null, new[] { exit });
                cursor.Position = exit;
                cursor.Time += traverseDuration;
                cursor.FacingYawDegrees = facing;

                if (wasClosed && closeAfterTraversal)
                {
                    AddAction(actorPlan, actorId, PlanActionType.CloseDoor, portal.doorId,
                        exit, door.closeDurationSeconds, cursor.Time, null);
                    cursor.Time += door.closeDurationSeconds;
                }
                currentRoom = nextRoom;
            }

            if (!QueueMoveSegment(plan, state, actorId, actor, ref cursor, destination))
                return Rollback(actorPlan, originalCount, ref cursor, originalCursor);
            plan.RecalculateDuration();
            return true;
        }

        private static RoomSpec FindRoom(RoomPortalGraph graph, string id)
        {
            foreach (var room in graph.Rooms) if (room.id == id) return room;
            return default;
        }

        private static void AddAction(
            ActorPlan plan, int actorId, PlanActionType type, string targetId,
            WorldPoint targetPos, float duration, float earliestStart,
            System.Collections.Generic.Dictionary<string, LevelValue> parameters,
            WorldPoint[] trajectory = null)
        {
            plan.AddAction(new PlanAction
            {
                type = type,
                actorId = actorId,
                targetId = targetId,
                targetPos = targetPos,
                frozenTrajectory = trajectory,
                duration = duration,
                earliestStart = earliestStart,
                parameters = parameters
            });
        }

        private static bool Rollback(ActorPlan plan, int originalCount,
            ref PlanCursor cursor, PlanCursor originalCursor)
        {
            if (plan.actions.Count > originalCount)
                plan.actions.RemoveRange(originalCount, plan.actions.Count - originalCount);
            cursor = originalCursor;
            return false;
        }

        private static float DeltaAngle(float current, float target)
        {
            float delta = (target - current) % 360f;
            if (delta > 180f) delta -= 360f;
            if (delta < -180f) delta += 360f;
            return delta;
        }

        /// Queues a MoveTo to `targetPos` (reusing <see cref="QueueMove"/>)
        /// followed immediately by the interaction action itself —
        /// `actionType`/`targetId`/`parameters` are already fully resolved
        /// by the caller (Gameplay-side: which `*View` component the tapped
        /// `Interactable` carries, and its config) since this pure-C# method
        /// has no way to inspect a Unity component itself.
        public static void QueueInteract(MissionPlan plan, MissionState state, int actorId,
            ref PlanCursor cursor, WorldBox targetBounds, PlanActionType actionType, string targetId,
            System.Collections.Generic.Dictionary<string, LevelValue> parameters,
            IActionDurationProvider durationProvider)
        {
            if (!state.Actors.TryGetValue(actorId, out var actor)) return;
            if (!TryResolveInteractionSlot(state, actorId, actor, cursor, targetBounds,
                    out var slot, out var slotPath, out float facing)) return;

            float initialFacing = cursor.HasFacing ? cursor.FacingYawDegrees : actor.FacingYawDegrees;
            var moveStart = cursor.Position;
            float moveDuration = actor.Profile.DurationForDistance(PathLength(slotPath, cursor.Position));
            AddAction(plan.GetOrCreate(actorId), actorId, PlanActionType.MoveTo, null,
                slot, moveDuration, cursor.Time, null, slotPath);
            cursor.Position = slot;
            cursor.Time += moveDuration;
            cursor.FacingYawDegrees = FinalFacing(moveStart, slotPath, initialFacing);
            cursor.HasFacing = true;

            float turn = MathF.Abs(DeltaAngle(cursor.FacingYawDegrees, facing));
            float alignDuration = actor.Profile.maxTurnRateDegrees > 0f
                ? turn / actor.Profile.maxTurnRateDegrees : 0f;
            AddAction(plan.GetOrCreate(actorId), actorId, PlanActionType.Align, targetId,
                slot, alignDuration, cursor.Time,
                new System.Collections.Generic.Dictionary<string, LevelValue>
                {
                    ["facingYaw"] = LevelValue.Float(facing),
                    ["duration"] = LevelValue.Float(alignDuration)
                });
            cursor.Time += alignDuration;
            cursor.FacingYawDegrees = facing;

            float duration = durationProvider.GetDuration(actionType, actor.Profile, parameters);

            plan.GetOrCreate(actorId).AddAction(new PlanAction
            {
                type = actionType,
                actorId = actorId,
                targetId = targetId,
                targetPos = slot,
                duration = duration,
                earliestStart = cursor.Time,
                parameters = parameters
            });
            plan.RecalculateDuration();

            cursor.Time += duration;
        }

        private static bool TryResolveInteractionSlot(
            MissionState state,
            int actorId,
            ActorState actor,
            PlanCursor cursor,
            WorldBox bounds,
            out WorldPoint bestSlot,
            out WorldPoint[] bestPath,
            out float bestFacing)
        {
            bestSlot = default;
            bestPath = Array.Empty<WorldPoint>();
            bestFacing = 0f;
            float radians = bounds.yaw * MathF.PI / 180f;
            float c = MathF.Cos(radians), s = MathF.Sin(radians);
            // Owner feedback (2026-08-24): the actor should stop close
            // enough to read as "at" the object, not visibly short of it.
            // actor.Profile.Radius alone already keeps the body's own edge
            // from clipping into the object; the two terms after it used to
            // add a further 0.2m on top of that. Trimmed to a small
            // clip-safety margin only.
            float clearance = actor.Profile.Radius + 0.03f;
            var normals = new[]
            {
                (x:c, z:s, extent:bounds.width * 0.5f),
                (x:-c, z:-s, extent:bounds.width * 0.5f),
                (x:-s, z:c, extent:bounds.depth * 0.5f),
                (x:s, z:-c, extent:bounds.depth * 0.5f)
            };
            float bestCost = float.PositiveInfinity;
            float initialFacing = cursor.HasFacing ? cursor.FacingYawDegrees : actor.FacingYawDegrees;
            foreach (var normal in normals)
            {
                var candidate = new WorldPoint(
                    bounds.centerX + normal.x * (normal.extent + clearance), 0f,
                    bounds.centerZ + normal.z * (normal.extent + clearance));
                var path = ActorMovementSystem.BuildFrozenTrajectory(
                    state, actorId, cursor.Position, initialFacing, candidate);
                if (path.Length == 0) continue;
                float cost = PathLength(path, cursor.Position);
                if (cost >= bestCost - 0.0001f) continue;
                bestCost = cost;
                bestSlot = candidate;
                bestPath = path;
                bestFacing = MathF.Atan2(bounds.centerX - candidate.x, bounds.centerZ - candidate.z)
                    * 180f / MathF.PI;
            }
            return bestPath.Length > 0;
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

        private static float FinalFacing(
            WorldPoint start,
            WorldPoint[] path,
            float fallback)
        {
            var previous = start;
            float facing = fallback;
            foreach (var point in path)
            {
                float dx = point.x - previous.x, dz = point.z - previous.z;
                if (dx * dx + dz * dz > 0.000001f)
                    facing = MathF.Atan2(dx, dz) * 180f / MathF.PI;
                previous = point;
            }
            return facing;
        }
    }
}
