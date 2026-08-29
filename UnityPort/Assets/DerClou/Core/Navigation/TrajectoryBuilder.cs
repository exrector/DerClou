namespace DerClou.Core.Navigation
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Data;

    /// Deterministic port of the validated Swift TrajectoryBuilder. It rounds
    /// legal corners and joins an ordinary retarget to the actor's current
    /// heading with a cubic curve. Every inserted chord is checked against
    /// the same authoritative grid, so smoothness can never cut a wall.
    public static class TrajectoryBuilder
    {
        public static WorldPoint[] Continuous(
            WorldPoint start,
            WorldPoint[] path,
            float initialFacing,
            NavGrid grid,
            CharacterProfile character)
        {
            var rounded = Rounded(start, path, grid, character);
            var points = WithStart(start, rounded);
            if (points.Count <= 1) return rounded;

            float routeFacing = Yaw(points[0], points[1]);
            float headingChange = MathF.Abs(DeltaAngle(initialFacing, routeFacing));
            if (headingChange < 4f || headingChange > 110f) return rounded;

            float totalLength = PolylineLength(points);
            if (totalLength <= MathF.Max(grid.cellSize * 4f, 0.35f)) return rounded;

            float preferredBlend = MathF.Max(character.preferredCornerRadius * 2.4f, character.walkSpeed * 0.65f);
            float maximumBlend = MathF.Min(preferredBlend, totalLength * 0.55f);
            float minimumBlend = MathF.Max(grid.cellSize * 4f, character.preferredCornerRadius);
            if (maximumBlend < minimumBlend) return rounded;

            float radians = initialFacing * MathF.PI / 180f;
            var startDirection = new WorldPoint(MathF.Sin(radians), 0, MathF.Cos(radians));
            float[] scales = { 1f, 0.82f, 0.66f, 0.5f };
            foreach (float scale in scales)
            {
                float blendDistance = maximumBlend * scale;
                if (blendDistance < minimumBlend || !TrySplit(points, blendDistance, out var split)) continue;
                var joinDirection = Normalized(Subtract(split.SegmentEnd, split.SegmentStart));
                float handle = blendDistance * 0.38f;
                var control1 = Add(start, Multiply(startDirection, handle));
                var control2 = Subtract(split.Point, Multiply(joinDirection, handle));
                int sampleCount = Math.Max(16, (int)MathF.Ceiling(blendDistance / MathF.Max(grid.cellSize * 0.3f, 0.025f)));
                var curve = new List<WorldPoint>();
                var previous = start;
                bool legal = true;
                for (int sample = 1; sample <= sampleCount; sample++)
                {
                    float t = (float)sample / sampleCount, inv = 1f - t;
                    var point = Add(
                        Add(Multiply(start, inv * inv * inv), Multiply(control1, 3f * inv * inv * t)),
                        Add(Multiply(control2, 3f * inv * t * t), Multiply(split.Point, t * t * t)));
                    point.y = 0;
                    if (!PathFinder.HasLineOfSight(grid, previous, point)) { legal = false; break; }
                    curve.Add(point);
                    previous = point;
                }
                if (!legal) continue;
                curve.AddRange(split.Remaining.GetRange(1, split.Remaining.Count - 1));
                return curve.ToArray();
            }
            return rounded;
        }

        public static WorldPoint[] Rounded(WorldPoint start, WorldPoint[] path, NavGrid grid, CharacterProfile character)
        {
            var source = WithStart(start, path);
            if (source.Count <= 2 || character.preferredCornerRadius <= 0f) return WithoutStart(source);
            var output = new List<WorldPoint> { source[0] };
            for (int i = 1; i < source.Count - 1; i++)
            {
                var a = source[i - 1]; var corner = source[i]; var c = source[i + 1];
                var incoming = Subtract(a, corner); var outgoing = Subtract(c, corner);
                float inLength = Length(incoming), outLength = Length(outgoing);
                if (inLength <= 0.000001f || outLength <= 0.000001f) continue;
                incoming = Normalized(incoming); outgoing = Normalized(outgoing);
                float dot = Clamp(incoming.x * outgoing.x + incoming.z * outgoing.z, -1f, 1f);
                if (dot < -0.995f) { output.Add(corner); continue; }

                float radius = MathF.Min(character.preferredCornerRadius, MathF.Min(inLength * 0.42f, outLength * 0.42f));
                List<WorldPoint> accepted = null;
                for (int attempt = 0; attempt < 5 && radius >= grid.cellSize; attempt++, radius *= 0.5f)
                {
                    var entry = Add(corner, Multiply(incoming, radius));
                    var exit = Add(corner, Multiply(outgoing, radius));
                    int samples = Math.Max(4, (int)MathF.Ceiling(radius * 2f / MathF.Max(grid.cellSize, 0.01f)));
                    var candidate = new List<WorldPoint> { entry };
                    for (int sample = 1; sample <= samples; sample++)
                    {
                        float t = (float)sample / samples, inv = 1f - t;
                        var point = Add(Add(Multiply(entry, inv * inv), Multiply(corner, 2f * inv * t)), Multiply(exit, t * t));
                        point.y = 0; candidate.Add(point);
                    }
                    var previous = output[output.Count - 1]; bool legal = true;
                    foreach (var point in candidate)
                    {
                        if (!PathFinder.HasLineOfSight(grid, previous, point)) { legal = false; break; }
                        previous = point;
                    }
                    if (legal) accepted = candidate;
                    if (accepted != null) break;
                }
                if (accepted != null) output.AddRange(accepted); else output.Add(corner);
            }
            output.Add(source[source.Count - 1]);
            return WithoutStart(output);
        }

        private struct Split { public WorldPoint Point, SegmentStart, SegmentEnd; public List<WorldPoint> Remaining; }
        private static bool TrySplit(List<WorldPoint> points, float requested, out Split result)
        {
            float remaining = MathF.Max(0, requested);
            for (int i = 0; i < points.Count - 1; i++)
            {
                float length = Distance(points[i], points[i + 1]);
                if (length <= 0.000001f) continue;
                if (remaining <= length)
                {
                    var point = Add(points[i], Multiply(Subtract(points[i + 1], points[i]), remaining / length));
                    var tail = new List<WorldPoint> { point };
                    for (int j = i + 1; j < points.Count; j++) tail.Add(points[j]);
                    result = new Split { Point = point, SegmentStart = points[i], SegmentEnd = points[i + 1], Remaining = tail };
                    return true;
                }
                remaining -= length;
            }
            result = default; return false;
        }

        private static List<WorldPoint> WithStart(WorldPoint start, WorldPoint[] path)
        {
            var result = new List<WorldPoint> { start };
            if (path != null) foreach (var p in path) if (Distance(result[result.Count - 1], p) > 0.000001f) result.Add(p);
            return result;
        }
        private static WorldPoint[] WithoutStart(List<WorldPoint> points) { if (points.Count <= 1) return Array.Empty<WorldPoint>(); points.RemoveAt(0); return points.ToArray(); }
        private static float PolylineLength(List<WorldPoint> p) { float v = 0; for (int i = 1; i < p.Count; i++) v += Distance(p[i - 1], p[i]); return v; }
        private static float Yaw(WorldPoint a, WorldPoint b) => MathF.Atan2(b.x - a.x, b.z - a.z) * 180f / MathF.PI;
        public static float DeltaAngle(float current, float target) { float d = (target - current) % 360f; if (d > 180f) d -= 360f; if (d < -180f) d += 360f; return d; }
        private static float Distance(WorldPoint a, WorldPoint b) => Length(Subtract(a, b));
        private static float Length(WorldPoint p) => MathF.Sqrt(p.x * p.x + p.z * p.z);
        private static WorldPoint Normalized(WorldPoint p) { float l = Length(p); return l > 0.000001f ? Multiply(p, 1f / l) : default; }
        private static WorldPoint Add(WorldPoint a, WorldPoint b) => new WorldPoint(a.x + b.x, a.y + b.y, a.z + b.z);
        private static WorldPoint Subtract(WorldPoint a, WorldPoint b) => new WorldPoint(a.x - b.x, a.y - b.y, a.z - b.z);
        private static WorldPoint Multiply(WorldPoint p, float s) => new WorldPoint(p.x * s, p.y * s, p.z * s);
        private static float Clamp(float v, float lo, float hi) => MathF.Max(lo, MathF.Min(hi, v));
    }
}
