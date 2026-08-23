namespace DerClou.Gameplay.Level
{
    using DerClou.Core.Navigation;

    /// <summary>
    /// The one grid every actor's movement paths against for the currently
    /// built level. A single mutable static is enough for now: there is
    /// exactly one level loaded at a time (see `GameBootstrap`), and this
    /// avoids threading a `NavGrid` reference through every actor's
    /// constructor for a game that does not yet have more than one level in
    /// memory at once. Revisit if/when multiple levels can be loaded
    /// concurrently.
    /// </summary>
    public static class NavigationService
    {
        public static NavGrid Grid { get; set; }
    }
}
