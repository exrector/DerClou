namespace DerClou.Gameplay.Simulation
{
    using DerClou.Core.Simulation;

    /// <summary>
    /// How Unity-side code reaches the current mission's simulation state.
    /// Deliberately copies the exact pattern
    /// `Gameplay/Level/NavigationService.cs` already uses for the current
    /// <c>NavGrid</c> — one mutable static property, no event bus, no
    /// dependency injection. This project already has one precedent for
    /// "how does Unity code reach shared simulation state"; U2 reuses it
    /// rather than adding a second pattern (`docs/U2_SIMULATION_DESIGN.md`).
    /// </summary>
    public static class SimulationService
    {
        public static MissionState Current { get; set; }
    }
}
