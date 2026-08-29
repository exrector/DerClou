namespace DerClou.Core.Simulation
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Data;

    public enum VisionResultKind
    {
        Visible,
        OutOfRange,
        OutsideFieldOfView,
        Occluded
    }

    /// Exact, inspectable reason a target is or is not visible. Keeping this
    /// in Core makes a mission failure explainable instead of a physics-side
    /// Boolean that changes with render timing.
    public struct VisionResult
    {
        public VisionResultKind Kind;
        public float Distance;
        public float AngleDegrees;
        public string OccluderId;
        public bool IsVisible => Kind == VisionResultKind.Visible;
    }

    [Serializable]
    public class VisionSourceState
    {
        public int sourceId;
        public string sourceLabel;
        public int actorId;
        public VisionSourceKind kind;
        public VisionConfig config;
        public WorldPoint fixedPosition;
        public float eyeHeight = 1.55f;
        public float currentFacingYaw;
        public bool isEnabled = true;
    }

    [Serializable]
    public struct FailureEvent
    {
        public float time;
        public int actorId;
        public string source;
        public string reason;
        public WorldPoint position;
    }

    /// Pure deterministic floor-plane vision with footprint-only occlusion.
    /// No Physics.Raycast, Collider, Transform or frame delta participates.
    public static class VisionSolver
    {
        private const float Epsilon = 0.000001f;

        public static VisionResult Evaluate(
            WorldPoint observer,
            float facingDegrees,
            WorldPoint target,
            VisionConfig config,
            IReadOnlyList<WorldBox> occluders)
        {
            float dx = target.x - observer.x;
            float dz = target.z - observer.z;
            float distance = MathF.Sqrt(dx * dx + dz * dz);

            if (distance > MathF.Max(0f, config.range) + Epsilon)
            {
                return new VisionResult { Kind = VisionResultKind.OutOfRange, Distance = distance };
            }

            float angle = 0f;
            if (distance > Epsilon)
            {
                float yaw = facingDegrees * MathF.PI / 180f;
                float dot = (MathF.Sin(yaw) * dx + MathF.Cos(yaw) * dz) / distance;
                dot = MathF.Max(-1f, MathF.Min(1f, dot));
                angle = MathF.Acos(dot) * 180f / MathF.PI;
                if (angle > MathF.Max(0f, config.fieldOfViewDegrees) * 0.5f + Epsilon)
                {
                    return new VisionResult
                    {
                        Kind = VisionResultKind.OutsideFieldOfView,
                        Distance = distance,
                        AngleDegrees = angle
                    };
                }
            }

            if (occluders != null && occluders.Count > 0)
            {
                bool found = false;
                string stableId = null;
                for (int i = 0; i < occluders.Count; i++)
                {
                    var box = occluders[i];
                    if (!TryIntersectionEntry(observer, target, box, out _)) continue;
                    // Occluded is the gameplay fact. When several walls
                    // overlap the ray, expose a stable authored id for
                    // diagnostics regardless of input order, without sorting
                    // or allocating on every visibility check.
                    if (found && string.CompareOrdinal(box.sourceID, stableId) >= 0) continue;
                    found = true;
                    stableId = box.sourceID;
                }
                if (found)
                {
                    return new VisionResult
                    {
                        Kind = VisionResultKind.Occluded,
                        Distance = distance,
                        AngleDegrees = angle,
                        OccluderId = stableId
                    };
                }
            }

            return new VisionResult
            {
                Kind = VisionResultKind.Visible,
                Distance = distance,
                AngleDegrees = angle
            };
        }

        /// Distance a displayed cone ray reaches before the first simulation
        /// occluder. The presentation calls this same method, so the visible
        /// cone cannot disagree with detection geometry.
        public static float VisibleReach(
            WorldPoint observer,
            float targetHeight,
            float facingDegrees,
            float maxRange,
            IReadOnlyList<WorldBox> occluders)
        {
            float range = MathF.Max(0f, maxRange);
            if (range <= 0f) return 0f;

            float yaw = facingDegrees * MathF.PI / 180f;
            // Kept in the signature for source compatibility with existing
            // callers. Height is deliberately irrelevant to gameplay.
            _ = targetHeight;
            var end = new WorldPoint(
                observer.x + MathF.Sin(yaw) * range,
                0f,
                observer.z + MathF.Cos(yaw) * range);

            float firstEntry = 1f;
            if (occluders != null)
            {
                for (int i = 0; i < occluders.Count; i++)
                {
                    if (TryIntersectionEntry(observer, end, occluders[i], out float entry))
                        firstEntry = MathF.Min(firstEntry, entry);
                }
            }
            return range * MathF.Max(0f, MathF.Min(1f, firstEntry));
        }

        private static bool TryIntersectionEntry(
            WorldPoint start,
            WorldPoint end,
            WorldBox box,
            out float intersectionEntry)
        {
            float yaw = box.yaw * MathF.PI / 180f;
            float c = MathF.Cos(yaw), s = MathF.Sin(yaw);

            float startDx = start.x - box.centerX;
            float startDz = start.z - box.centerZ;
            float endDx = end.x - box.centerX;
            float endDz = end.z - box.centerZ;

            float ax = c * startDx - s * startDz;
            float az = s * startDx + c * startDz;
            float bx = c * endDx - s * endDz;
            float bz = s * endDx + c * endDz;

            float entry = 0f, exit = 1f;
            bool clipped = Clip(ax, bx - ax, box.width * 0.5f, ref entry, ref exit)
                && Clip(az, bz - az, box.depth * 0.5f, ref entry, ref exit);

            intersectionEntry = MathF.Max(0f, entry);
            return clipped && exit > Epsilon && entry < 1f - Epsilon;
        }

        private static bool Clip(float origin, float delta, float halfExtent, ref float entry, ref float exit)
        {
            if (MathF.Abs(delta) < Epsilon) return MathF.Abs(origin) <= halfExtent;
            float near = (-halfExtent - origin) / delta;
            float far = (halfExtent - origin) / delta;
            if (near > far) { float swap = near; near = far; far = swap; }
            entry = MathF.Max(entry, near);
            exit = MathF.Min(exit, far);
            return entry <= exit;
        }
    }
}
