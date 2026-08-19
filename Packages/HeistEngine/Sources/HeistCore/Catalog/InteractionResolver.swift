import Foundation

/// The generic interaction framework's rulebook: given what a prop supports
/// and its current state, what does a tap actually do right now, how long
/// does that take, and what changes when it finishes.
///
/// Deliberately generic rather than one `switch` per prop type — the Phase 3
/// acceptance bar is "a new object type can be added without rewriting
/// input/navigation architecture," which means the rules have to be read out
/// of `interactions` + two boolean state keys (`locked`, `open`) that any
/// prototype may or may not use, not out of the prototype's identity.
/// Everything here is pure and runs in milliseconds with no RealityKit, the
/// same split the rest of `HeistCore` already keeps.
public enum InteractionResolver {
    /// Which of a prop's supported interactions a tap should trigger right
    /// now, or nil when there is nothing left to do.
    ///
    /// The rule, in order: a locked prop offers whatever unlocks it
    /// (`lockpick`, `crackSafe`, `hack` — the first of those it actually
    /// supports) ahead of anything else, since nothing past the lock is
    /// reachable yet. An unopened prop that supports `open` opens next.
    /// After that, whichever of `takeLoot` / `toggleSwitch` / `extract` the
    /// prop supports. A prop that has already been opened and offers nothing
    /// further (a plain door, once it is open) returns nil rather than
    /// re-triggering `open` forever.
    public static func primaryInteraction(
        for interactions: [InteractionKind],
        config: [String: LevelValue]
    ) -> InteractionKind? {
        guard !interactions.isEmpty else { return nil }

        let isLocked = config["locked"]?.boolValue ?? false
        let isOpen = config["open"]?.boolValue ?? false

        if isLocked {
            return [.lockpick, .crackSafe, .hack].first { interactions.contains($0) }
                ?? interactions.first
        }
        if !isOpen, interactions.contains(.open) {
            return .open
        }
        if interactions.contains(.takeLoot) {
            return .takeLoot
        }
        if interactions.contains(.toggleSwitch) {
            return .toggleSwitch
        }
        if interactions.contains(.extract) {
            return .extract
        }
        // Nothing left to offer — most commonly a door that only ever
        // supported `open` and now is.
        return isOpen ? nil : interactions.first
    }

    /// How long `interaction` takes on a prop with this resolved config, in
    /// mission seconds.
    ///
    /// Reads `"<verb>Duration"` from config first — `openDuration`,
    /// `lockpickDuration`, `crackSafeDuration`, `hackDuration`,
    /// `toggleSwitchDuration` — which is exactly the key each catalog entry
    /// already authors its own pacing under (see `PropCatalog.standard`).
    /// Falls back to `defaultDuration` for verbs no prototype has tuned yet
    /// (`takeLoot`, `extract`) — per `docs/DECISIONS.md`'s time model, exact
    /// formulas are not finalized, so this stays a plain, overridable number
    /// rather than something hard-coded into UI or session code.
    public static func duration(for interaction: InteractionKind, config: [String: LevelValue]) -> Double {
        config["\(interaction.rawValue)Duration"]?.doubleValue ?? defaultDuration
    }

    /// Fallback duration for a verb with no prototype-specific tuning.
    public static let defaultDuration = 1.0

    /// The config after `interaction` completes on a prop that had `before`.
    ///
    /// This is the entire "world-state puzzle primitive" Phase 3 asks for,
    /// expressed as data rather than per-prop code:
    ///
    /// - `open` / `lockpick` mark the prop open (`lockpick` also clears
    ///   `locked` — picking a lock and immediately swinging the door through
    ///   it is treated as one motion here, not two separate taps);
    /// - `crackSafe` / `hack` clear `locked` only, since what they gate is
    ///   usually followed by a *different* verb (`takeLoot` on a cracked
    ///   safe) rather than an `open` of their own;
    /// - `toggleSwitch` flips a generic `active` flag — what that flag
    ///   *does* (power a camera, arm a laser) is the security dependency
    ///   graph from a later phase, not this one;
    /// - `takeLoot` marks the prop `looted` so a container does not keep
    ///   offering loot it no longer has;
    /// - `extract` changes nothing here — ending the mission is its own
    ///   system, not a config flag.
    public static func applying(_ interaction: InteractionKind, to before: [String: LevelValue]) -> [String: LevelValue] {
        var after = before
        switch interaction {
        case .open:
            after["open"] = .bool(true)
        case .lockpick:
            after["open"] = .bool(true)
            after["locked"] = .bool(false)
        case .crackSafe, .hack:
            after["locked"] = .bool(false)
        case .toggleSwitch:
            let isActive = before["active"]?.boolValue ?? false
            after["active"] = .bool(!isActive)
        case .takeLoot:
            after["looted"] = .bool(true)
        case .extract:
            break
        }
        return after
    }
}
