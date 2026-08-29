namespace DerClou.Core.Navigation
{
    using DerClou.Core.Data;

    /// Engine-neutral boundary for a standard spatial path query. Gameplay
    /// can supply Unity AI Navigation; pure Core tests and unsupported scenes
    /// retain deterministic grid A* as the fallback.
    public interface ISpatialCorridorProvider
    {
        bool TryFindCorridor(
            WorldPoint start,
            WorldPoint destination,
            out WorldPoint[] corridor);
    }
}
