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
    /// Runs each system in a fixed order. As of U2 step 2a there is exactly
    /// one system; steps 2b–2e append to this list, never reorder it ahead
    /// of <see cref="ActorMovementSystem"/> (guard arrival checks read the
    /// actor position this system just wrote).
    /// </para>
    /// </summary>
    public static class SimulationStep
    {
        public static void Tick(MissionState state, MissionClock clock, float fixedDt)
        {
            clock.Tick(fixedDt);
            if (state == null) return;

            ActorMovementSystem.Tick(state, fixedDt);
        }
    }
}
