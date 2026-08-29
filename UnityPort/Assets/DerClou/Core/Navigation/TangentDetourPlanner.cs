namespace DerClou.Core.Navigation
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Data;

    /// Builds one stable tangent-arc-tangent maneuver around a stationary
    /// circular body. The result goes directly to the committed destination;
    /// it never rejoins an obsolete segment of the original polyline.
    public static class TangentDetourPlanner
    {
        public static bool TryBuild(
            WorldPoint start,
            WorldPoint destination,
            float initialFacing,
            WorldPoint blocker,
            float requiredClearance,
            NavGrid grid,
            CharacterProfile profile,
            out WorldPoint[] path)
            => TryBuildGeneric(start, destination, initialFacing, blocker, requiredClearance,
                grid, profile, out path);

        /// Builds a bypass for an occupied authored corner. Unlike a generic
        /// stationary-body detour, this maneuver is constrained to the short
        /// inner sector between corner-to-start and corner-to-destination.
        public static bool TryBuildInsideCorner(
            WorldPoint start,
            WorldPoint destination,
            float initialFacing,
            WorldPoint blocker,
            float requiredClearance,
            NavGrid grid,
            CharacterProfile profile,
            out WorldPoint[] path)
        {
            path = null;
            if (grid == null) return false;

            float startX = start.x - blocker.x, startZ = start.z - blocker.z;
            float goalX = destination.x - blocker.x, goalZ = destination.z - blocker.z;
            float startRadius = MathF.Sqrt(startX * startX + startZ * startZ);
            float goalRadius = MathF.Sqrt(goalX * goalX + goalZ * goalZ);
            float radius = requiredClearance + MathF.Max(0.025f, grid.cellSize * 0.12f);
            if (startRadius <= radius || goalRadius <= radius) return false;

            float startAngle = MathF.Atan2(startZ, startX);
            float goalAngle = MathF.Atan2(goalZ, goalX);
            float signedAngle = ShortestSignedAngle(goalAngle - startAngle);
            // A reversal has no unique inside. Let the generic local detour
            // choose a side in that special case.
            if (MathF.Abs(MathF.Abs(signedAngle) - MathF.PI) < 0.001f)
                return TryBuild(start, destination, initialFacing, blocker,
                    requiredClearance, grid, profile, out path);

            // A blocked patrol corner is replaced by one broad cubic turn,
            // not a straight approach followed by a tiny orbit around the
            // body. Both handles lie on the authored route legs: the curve
            // is tangent to the incoming leg at the live actor position and
            // tangent to the outgoing leg at the following patrol node.
            int samples = Math.Max(24, Math.Min(96,
                (int)MathF.Ceiling((startRadius + goalRadius)
                    / MathF.Max(0.12f, grid.cellSize * 0.8f))));
            float[] handleFractions = { 0.72f, 0.66f, 0.58f, 0.50f, 0.42f };
            foreach (float handleFraction in handleFractions)
            {
                var control1 = new WorldPoint(
                    start.x + (blocker.x - start.x) * handleFraction,
                    0,
                    start.z + (blocker.z - start.z) * handleFraction);
                var control2 = new WorldPoint(
                    destination.x + (blocker.x - destination.x) * handleFraction,
                    0,
                    destination.z + (blocker.z - destination.z) * handleFraction);
                var candidate = new WorldPoint[samples];
                for (int sample = 1; sample <= samples; sample++)
                {
                    float t = (float)sample / samples;
                    float inv = 1f - t;
                    candidate[sample - 1] = new WorldPoint(
                        start.x * inv * inv * inv
                            + 3f * control1.x * inv * inv * t
                            + 3f * control2.x * inv * t * t
                            + destination.x * t * t * t,
                        0,
                        start.z * inv * inv * inv
                            + 3f * control1.z * inv * inv * t
                            + 3f * control2.z * inv * t * t
                            + destination.z * t * t * t);
                }
                candidate[candidate.Length - 1] = destination;

                if (!StaysInsideShortCornerSector(candidate, blocker, start, destination)
                    || !IsLegal(start, candidate, blocker, requiredClearance, grid)) continue;
                path = candidate;
                return true;
            }
            return false;
        }

        private static bool TryBuildGeneric(
            WorldPoint start,
            WorldPoint destination,
            float initialFacing,
            WorldPoint blocker,
            float requiredClearance,
            NavGrid grid,
            CharacterProfile profile,
            out WorldPoint[] path)
        {
            path = null;
            if (grid == null) return false;

            // Arc chords lie slightly inside their mathematical circle. A
            // small deterministic margin keeps every chord outside the hard
            // body clearance, not only the sampled points.
            float radius = requiredClearance + MathF.Max(0.025f, grid.cellSize * 0.12f);
            if (!TryTangents(start, blocker, radius, out var startTangents)
                || !TryTangents(destination, blocker, radius, out var goalTangents))
                return false;

            WorldPoint[] best = null;
            float bestLength = float.PositiveInfinity;
            for (int startIndex = 0; startIndex < 2; startIndex++)
            for (int goalIndex = 0; goalIndex < 2; goalIndex++)
            {
                var tangentStart = startTangents[startIndex];
                var tangentGoal = goalTangents[goalIndex];
                int startDirection = TangentDirection(
                    Subtract(tangentStart, blocker),
                    Subtract(tangentStart, start));
                int goalDirection = TangentDirection(
                    Subtract(tangentGoal, blocker),
                    Subtract(destination, tangentGoal));
                if (startDirection == 0 || startDirection != goalDirection) continue;

                float startAngle = MathF.Atan2(tangentStart.z - blocker.z, tangentStart.x - blocker.x);
                float goalAngle = MathF.Atan2(tangentGoal.z - blocker.z, tangentGoal.x - blocker.x);
                float arcAngle = startDirection > 0
                    ? PositiveAngle(goalAngle - startAngle)
                    : PositiveAngle(startAngle - goalAngle);
                // The useful local bypass is never a near-full orbit.
                if (arcAngle > MathF.PI * 1.15f) continue;

                float arcLength = radius * arcAngle;
                int samples = Math.Max(8,
                    (int)MathF.Ceiling(arcLength / MathF.Max(0.04f, grid.cellSize * 0.35f)));
                var candidate = new List<WorldPoint> { tangentStart };
                for (int sample = 1; sample <= samples; sample++)
                {
                    float t = (float)sample / samples;
                    float angle = startAngle + startDirection * arcAngle * t;
                    candidate.Add(new WorldPoint(
                        blocker.x + MathF.Cos(angle) * radius,
                        0,
                        blocker.z + MathF.Sin(angle) * radius));
                }
                candidate.Add(destination);

                var raw = candidate.ToArray();
                if (!IsLegal(start, raw, blocker, requiredClearance, grid)) continue;

                // Join the replacement maneuver to the actor's current
                // heading. Accept it only when the heading blend preserves
                // the same body clearance around the blocker.
                var continuous = TrajectoryBuilder.Continuous(
                    start, raw, initialFacing, grid, profile);
                var accepted = IsLegal(start, continuous, blocker, requiredClearance, grid)
                    ? continuous : raw;
                float length = Length(start, accepted);
                if (length >= bestLength) continue;
                bestLength = length;
                best = accepted;
            }

            path = best;
            return best != null;
        }

        private static bool StaysInsideShortCornerSector(
            WorldPoint[] path,
            WorldPoint corner,
            WorldPoint incomingPoint,
            WorldPoint outgoingPoint)
        {
            float inX = incomingPoint.x - corner.x, inZ = incomingPoint.z - corner.z;
            float outX = outgoingPoint.x - corner.x, outZ = outgoingPoint.z - corner.z;
            float inLength = MathF.Sqrt(inX * inX + inZ * inZ);
            float outLength = MathF.Sqrt(outX * outX + outZ * outZ);
            if (inLength <= 0.000001f || outLength <= 0.000001f) return false;
            inX /= inLength; inZ /= inLength;
            outX /= outLength; outZ /= outLength;

            // The normalized sum is the bisector of the shorter sector. A
            // point belongs to that sector when its direction is no farther
            // from the bisector than either boundary ray.
            float bisectorX = inX + outX, bisectorZ = inZ + outZ;
            float bisectorLength = MathF.Sqrt(bisectorX * bisectorX + bisectorZ * bisectorZ);
            if (bisectorLength <= 0.000001f) return true; // straight reversal has no unique inside
            bisectorX /= bisectorLength; bisectorZ /= bisectorLength;
            float boundaryDot = bisectorX * inX + bisectorZ * inZ;

            foreach (var point in path)
            {
                float radialX = point.x - corner.x, radialZ = point.z - corner.z;
                float radialLength = MathF.Sqrt(radialX * radialX + radialZ * radialZ);
                if (radialLength <= 0.000001f) return false;
                float sideDot = (radialX * bisectorX + radialZ * bisectorZ) / radialLength;
                if (sideDot + 0.0001f < boundaryDot) return false;
            }
            return true;
        }

        private static bool TryTangents(
            WorldPoint point,
            WorldPoint center,
            float radius,
            out WorldPoint[] tangents)
        {
            float vx = point.x - center.x, vz = point.z - center.z;
            float distanceSquared = vx * vx + vz * vz;
            if (distanceSquared <= radius * radius + 0.000001f)
            {
                tangents = null;
                return false;
            }
            float baseScale = radius * radius / distanceSquared;
            float offsetScale = radius * MathF.Sqrt(distanceSquared - radius * radius)
                / distanceSquared;
            var basePoint = new WorldPoint(
                center.x + vx * baseScale, 0,
                center.z + vz * baseScale);
            var offset = new WorldPoint(-vz * offsetScale, 0, vx * offsetScale);
            tangents = new[] { Add(basePoint, offset), Subtract(basePoint, offset) };
            return true;
        }

        // +1 = counter-clockwise, -1 = clockwise.
        private static int TangentDirection(WorldPoint radial, WorldPoint travel)
        {
            float length = MathF.Sqrt(travel.x * travel.x + travel.z * travel.z);
            if (length <= 0.000001f) return 0;
            float dotCounterClockwise = (-radial.z * travel.x + radial.x * travel.z) / length;
            return dotCounterClockwise >= 0 ? 1 : -1;
        }

        private static bool IsLegal(
            WorldPoint start,
            WorldPoint[] candidate,
            WorldPoint blocker,
            float clearance,
            NavGrid grid)
        {
            var previous = start;
            foreach (var point in candidate)
            {
                if (!PathFinder.HasLineOfSight(grid, previous, point)) return false;
                if (SegmentDistanceSquared(previous, point, blocker)
                    < clearance * clearance - 0.000001f) return false;
                previous = point;
            }
            return true;
        }

        private static float SegmentDistanceSquared(WorldPoint a, WorldPoint b, WorldPoint point)
        {
            float dx = b.x - a.x, dz = b.z - a.z;
            float lengthSquared = dx * dx + dz * dz;
            float t = lengthSquared > 0.000001f
                ? ((point.x - a.x) * dx + (point.z - a.z) * dz) / lengthSquared : 0f;
            t = MathF.Max(0, MathF.Min(1, t));
            float px = a.x + dx * t - point.x;
            float pz = a.z + dz * t - point.z;
            return px * px + pz * pz;
        }

        private static float Length(WorldPoint start, WorldPoint[] path)
        {
            float length = 0; var previous = start;
            foreach (var point in path)
            {
                float dx = point.x - previous.x, dz = point.z - previous.z;
                length += MathF.Sqrt(dx * dx + dz * dz);
                previous = point;
            }
            return length;
        }

        private static float PositiveAngle(float angle)
        {
            float full = MathF.PI * 2f;
            angle %= full;
            return angle < 0 ? angle + full : angle;
        }

        private static float ShortestSignedAngle(float angle)
        {
            float full = MathF.PI * 2f;
            angle %= full;
            if (angle > MathF.PI) angle -= full;
            if (angle < -MathF.PI) angle += full;
            return angle;
        }

        private static WorldPoint Add(WorldPoint a, WorldPoint b)
            => new WorldPoint(a.x + b.x, a.y + b.y, a.z + b.z);
        private static WorldPoint Subtract(WorldPoint a, WorldPoint b)
            => new WorldPoint(a.x - b.x, a.y - b.y, a.z - b.z);
    }
}
