namespace DerClou.Gameplay.Actors
{
    using System.Collections.Generic;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;

    /// <summary>
    /// Renamed from the <c>GuardPatrolSystem</c> MonoBehaviour as part of U2
    /// step 2b (`docs/U2_SIMULATION_DESIGN.md`). The Moving/Waiting/Acting/
    /// Alert state machine that used to live in this class's <c>TickGuard</c>
    /// now lives in the pure-C# <c>DerClou.Core.Systems.GuardPatrolSystem</c>,
    /// ticked from <see cref="Core.Simulation.SimulationStep"/>. This class
    /// only reads the result back each frame to drive each guard's Animator
    /// — it never decides where a guard is or where it's going.
    /// </summary>
    public class GuardView : MonoBehaviour
    {
        private readonly Dictionary<int, ActorView> views = new();

        public void RegisterView(int actorId, ActorView view) => views[actorId] = view;

        private void Update()
        {
            var state = SimulationService.Current;
            if (state == null) return;

            foreach (var kv in views)
            {
                int actorId = kv.Key;
                var view = kv.Value;
                if (view == null || !state.Actors.TryGetValue(actorId, out var actor)) continue;
                view.UpdateAnimation(actor.CurrentSpeed);
            }
        }
    }
}
