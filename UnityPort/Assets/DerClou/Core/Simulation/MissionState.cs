namespace DerClou.Core.Simulation
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;

    /// <summary>
    /// Everything <see cref="Systems.ActorMovementSystem"/> (and, as later U2
    /// steps land, the guard/camera/door/safe systems) needs to know about
    /// one actor. This is the actor's real position and path — the
    /// presentation-side <c>ActorView</c>'s Transform is a read-only mirror
    /// of this, not the other way around (`docs/U2_SIMULATION_DESIGN.md`).
    /// </summary>
    public struct ActorState
    {
        public int ActorId;
        public ActorRole Role;
        public CharacterProfile Profile;
        public WorldPoint Position;
        public float FacingYawDegrees;
        public WorldPoint[] CurrentPath;
        public int PathIndex;
        public bool HasPath;

        // Dedup guard for `ActorMovementSystem.RequestPath` — without it,
        // a caller that re-requests the same destination every tick (guard
        // patrol in particular) would re-solve A* every single fixed step
        // for a destination that hasn't moved. Lived on `ActorView` itself
        // before step 2b; moved here because it's a fact about the
        // simulation's last routing decision, not a presentation concern.
        public WorldPoint LastRequestedDestination;
        public bool HasRequestedDestination;
    }

    /// <summary>
    /// The gameplay-authoritative state for the current mission. Grew
    /// <see cref="Guards"/>, <see cref="Grid"/> and <see cref="CurrentTime"/>
    /// in U2 step 2b — Doors/Cameras/Safes are added by their own migration
    /// steps (2c–2e), not pre-declared here as unused placeholders.
    /// </summary>
    public class MissionState
    {
        public Dictionary<int, ActorState> Actors = new();
        public Dictionary<int, GuardState> Guards = new();

        /// The grid every actor/guard paths against. Pure C# already
        /// (`NavGrid`), so it belongs on the simulation side rather than
        /// behind a separate Unity-side static accessor — one less place
        /// pure-C# systems would otherwise need to reach into `Gameplay.*`
        /// for. Replaces the old `Gameplay.Level.NavigationService`.
        public NavGrid Grid;

        /// Mirrors `MissionClock.CurrentTime`, set once per fixed step by
        /// `SimulationStep.Tick` before running any system — lets systems
        /// (`GuardPatrolSystem` in particular, for wait-duration checks)
        /// take only `MissionState`, not a separate clock reference.
        public float CurrentTime;

        /// Deep copy — the one primitive U2 owes U3's future snapshot/reset
        /// (`docs/U2_SIMULATION_DESIGN.md`). Nothing in U2 calls this yet.
        /// `Grid` and each `GuardState.route` are shared by reference, not
        /// deep-cloned — both are authored/static level data, never mutated
        /// at runtime, so cloning them would only cost memory for no benefit.
        public MissionState Clone()
        {
            var clone = new MissionState { Grid = Grid, CurrentTime = CurrentTime };
            foreach (var kv in Actors)
            {
                var copy = kv.Value;
                copy.CurrentPath = kv.Value.CurrentPath != null
                    ? (WorldPoint[])kv.Value.CurrentPath.Clone()
                    : null;
                clone.Actors[kv.Key] = copy;
            }
            foreach (var kv in Guards)
            {
                clone.Guards[kv.Key] = new GuardState
                {
                    actorId = kv.Value.actorId,
                    route = kv.Value.route,
                    currentNodeIndex = kv.Value.currentNodeIndex,
                    nodeArrivalTime = kv.Value.nodeArrivalTime,
                    state = kv.Value.state,
                    isAlerted = kv.Value.isAlerted,
                    alertLevel = kv.Value.alertLevel
                };
            }
            return clone;
        }
    }
}
