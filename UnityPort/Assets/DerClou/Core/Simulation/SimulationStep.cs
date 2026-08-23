namespace DerClou.Core.Simulation
{
    using DerClou.Core.Systems;
    using DerClou.Core.Time;

    /// <summary>
    /// The single fixed-step entry point. <c>GameController</c> calls this
    /// once per consumed step from <c>FixedStepAccumulator</c> instead of
    /// ticking <see cref="MissionClock"/> from a variable render-frame delta
    /// — that variable-dt tick was the actual reason the project wasn't
    /// deterministic yet despite already having a clock and an accumulator
    /// (`docs/U2_SIMULATION_DESIGN.md`).
    /// <para>
    /// Runs each system in a fixed order, never reordered ahead of
    /// <see cref="ActorMovementSystem"/> — every other system reads the
    /// actor position it just wrote (guard arrival checks in particular).
    /// </para>
    /// </summary>
    public static class SimulationStep
    {
        public static void Tick(MissionState state, MissionClock clock, float fixedDt)
        {
            clock.Tick(fixedDt);
            if (state == null) return;

            state.CurrentTime = clock.CurrentTime;

            // Actor movement stays live even while `clock.IsPaused` — the
            // old MonoBehaviour version never gated it on the clock either
            // (`GameController.SetPhase`'s own comment: "Keep the world live
            // for this minimum slice"). Guard patrol did check
            // `missionClock.IsPaused` before this step and is kept gated the
            // same way, or pausing during Planning would have silently
            // stopped freezing guards.
            ActorMovementSystem.Tick(state, fixedDt);
            if (!clock.IsPaused) GuardPatrolSystem.Tick(state, fixedDt);
            SecurityCameraSystem.Tick(state, fixedDt);
        }
    }
}
