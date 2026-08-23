namespace DerClou.Core.Simulation
{
    using System.Collections.Generic;
    using DerClou.Core.Data;

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
    }

    /// <summary>
    /// The gameplay-authoritative state for the current mission. Deliberately
    /// only carries <see cref="Actors"/> as of U2 step 2a — Guards/Doors/
    /// Cameras/Safes are added by their own migration steps (2b–2e), not
    /// pre-declared here as unused placeholders.
    /// </summary>
    public class MissionState
    {
        public Dictionary<int, ActorState> Actors = new();

        /// Deep copy — the one primitive U2 owes U3's future snapshot/reset
        /// (`docs/U2_SIMULATION_DESIGN.md`). Nothing in U2 calls this yet.
        public MissionState Clone()
        {
            var clone = new MissionState();
            foreach (var kv in Actors)
            {
                var copy = kv.Value;
                copy.CurrentPath = kv.Value.CurrentPath != null
                    ? (WorldPoint[])kv.Value.CurrentPath.Clone()
                    : null;
                clone.Actors[kv.Key] = copy;
            }
            return clone;
        }
    }
}
