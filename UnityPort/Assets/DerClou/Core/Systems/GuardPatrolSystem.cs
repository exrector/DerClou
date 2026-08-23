namespace DerClou.Core.Systems
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
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

        public static void Tick(MissionState state, float dt)
        {
            var ids = new List<int>(state.Guards.Keys);
            foreach (var actorId in ids)
            {
                var guard = state.Guards[actorId];
                TickGuard(state, actorId, ref guard);
                state.Guards[actorId] = guard;
            }
        }

        private static void TickGuard(MissionState state, int actorId, ref GuardState guard)
        {
            if (guard.route == null || guard.route.nodes.Length == 0) return;
            if (!state.Actors.TryGetValue(actorId, out var actor)) return;

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
                    ActorMovementSystem.RequestPath(state, actorId, targetPos);

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
                    // TODO: alert behavior — U4
                    break;
            }
        }
    }
}
