namespace DerClou.Core.Systems
{
    using System;
    using DerClou.Core.Data;
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

        public static void Tick(MissionState state, float dt)
        {
            // Dictionary<TKey, TValue> with a struct TValue: iterate keys,
            // mutate through indexer — `foreach (var kv in ...)` yields a
            // copy that can't be written back in place.
            var ids = new System.Collections.Generic.List<int>(state.Actors.Keys);
            foreach (var id in ids)
            {
                var a = state.Actors[id];
                TickActor(ref a, dt);
                state.Actors[id] = a;
            }
        }

        private static void TickActor(ref ActorState a, float dt)
        {
            if (!a.HasPath || a.CurrentPath == null || a.PathIndex >= a.CurrentPath.Length) return;

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
                }
                return;
            }

            float dirX = dx / distance, dirZ = dz / distance;
            float step = MathF.Min(a.Profile.walkSpeed * dt, distance);
            a.Position = new WorldPoint(a.Position.x + dirX * step, a.Position.y, a.Position.z + dirZ * step);

            float targetYaw = MathF.Atan2(dirX, dirZ) * (180f / MathF.PI);
            a.FacingYawDegrees = a.Profile.maxTurnRateDegrees > 0f
                ? MoveTowardsAngle(a.FacingYawDegrees, targetYaw, a.Profile.maxTurnRateDegrees * dt)
                : targetYaw;
        }

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
