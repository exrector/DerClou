import Testing
@testable import HeistCore

/// `InteractionResolver` is the whole rulebook for Phase 3's generic
/// interaction framework, expressed as three pure functions rather than a
/// switch per prop type — these tests are what "a new object type can be
/// added without rewriting input/navigation architecture" actually rests on:
/// every current catalog prototype's behaviour is derived, not hand-cased.
@Suite("Interaction resolving")
struct InteractionResolverTests {
    // MARK: - primaryInteraction: doors

    @Test("A locked door offers lockpick, not open")
    func lockedDoorOffersLockpick() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.open, .lockpick], config: ["locked": .bool(true)]
        )
        #expect(interaction == .lockpick)
    }

    @Test("An unlocked, unopened door offers open")
    func unlockedDoorOffersOpen() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.open, .lockpick], config: ["locked": .bool(false)]
        )
        #expect(interaction == .open)
    }

    @Test("An already-open door with nothing else to offer has nothing left to do")
    func openDoorOffersNothingFurther() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.open, .lockpick], config: ["locked": .bool(false), "open": .bool(true)]
        )
        #expect(interaction == nil)
    }

    // MARK: - primaryInteraction: containers

    @Test("An unopened container offers open before loot")
    func unopenedContainerOffersOpen() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.open, .takeLoot], config: [:]
        )
        #expect(interaction == .open)
    }

    @Test("An opened container offers loot next")
    func openedContainerOffersLoot() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.open, .takeLoot], config: ["open": .bool(true)]
        )
        #expect(interaction == .takeLoot)
    }

    @Test("A locked safe offers crackSafe, not loot it cannot reach yet")
    func lockedSafeOffersCracking() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.crackSafe, .takeLoot], config: ["locked": .bool(true)]
        )
        #expect(interaction == .crackSafe)
    }

    @Test("A cracked safe offers loot — crackSafe alone does not need an explicit open")
    func crackedSafeOffersLoot() {
        // safe.wall has no `.open` in its interaction list; cracking it
        // clears `locked` only (see InteractionResolver.applying), so the
        // very next resolve has to fall through the (absent) open branch
        // straight to takeLoot.
        let interaction = InteractionResolver.primaryInteraction(
            for: [.crackSafe, .takeLoot], config: ["locked": .bool(false)]
        )
        #expect(interaction == .takeLoot)
    }

    // MARK: - primaryInteraction: everything else in the standard catalog

    @Test("A security panel with no lock state offers its switch")
    func panelOffersToggle() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.hack, .toggleSwitch], config: [:]
        )
        #expect(interaction == .toggleSwitch)
    }

    @Test("A standalone loot pickup offers loot with no open step")
    func lootPickupOffersLootDirectly() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.takeLoot], config: [:]
        )
        #expect(interaction == .takeLoot)
    }

    @Test("An extraction marker offers extract")
    func extractionMarkerOffersExtract() {
        let interaction = InteractionResolver.primaryInteraction(
            for: [.extract], config: [:]
        )
        #expect(interaction == .extract)
    }

    @Test("A prop with no interactions at all offers nothing")
    func noInteractionsOffersNothing() {
        #expect(InteractionResolver.primaryInteraction(for: [], config: [:]) == nil)
    }

    // MARK: - duration

    @Test("Duration reads the prototype's own per-verb key")
    func durationReadsCatalogKey() {
        let duration = InteractionResolver.duration(
            for: .crackSafe, config: ["crackSafeDuration": .double(20)]
        )
        #expect(duration == 20)
    }

    @Test("Duration falls back to the default when a verb has no tuned key yet")
    func durationFallsBackWhenUntuned() {
        let duration = InteractionResolver.duration(for: .takeLoot, config: [:])
        #expect(duration == InteractionResolver.defaultDuration)
    }

    // MARK: - applying

    @Test("Opening sets open, and nothing else")
    func openingSetsOpen() {
        let after = InteractionResolver.applying(.open, to: [:])
        #expect(after["open"] == .bool(true))
        #expect(after["locked"] == nil)
    }

    @Test("Lockpicking both unlocks and opens in one motion")
    func lockpickingUnlocksAndOpens() {
        let after = InteractionResolver.applying(.lockpick, to: ["locked": .bool(true)])
        #expect(after["locked"] == .bool(false))
        #expect(after["open"] == .bool(true))
    }

    @Test("Cracking a safe clears locked without implying open")
    func crackingClearsLockedOnly() {
        let after = InteractionResolver.applying(.crackSafe, to: ["locked": .bool(true)])
        #expect(after["locked"] == .bool(false))
        #expect(after["open"] == nil)
    }

    @Test("Toggling a switch flips whatever it currently is")
    func togglingFlipsActive() {
        let firstFlip = InteractionResolver.applying(.toggleSwitch, to: [:])
        #expect(firstFlip["active"] == .bool(true))

        let secondFlip = InteractionResolver.applying(.toggleSwitch, to: firstFlip)
        #expect(secondFlip["active"] == .bool(false))
    }

    @Test("Taking loot marks the prop looted")
    func takingLootMarksLooted() {
        let after = InteractionResolver.applying(.takeLoot, to: [:])
        #expect(after["looted"] == .bool(true))
    }

    @Test("Extracting changes nothing in the prop's own config")
    func extractingChangesNothingLocally() {
        let before: [String: LevelValue] = ["locked": .bool(false)]
        #expect(InteractionResolver.applying(.extract, to: before) == before)
    }

    // MARK: - The standard catalog, end to end

    @Test("Every interactive prototype in the standard catalog resolves to something on first tap")
    func everyInteractivePrototypeHasAPrimaryInteraction() {
        for prototype in PropCatalog.standard.ids.compactMap({ PropCatalog.standard[$0] })
        where !prototype.interactions.isEmpty {
            let interaction = InteractionResolver.primaryInteraction(
                for: prototype.interactions, config: prototype.defaults
            )
            #expect(
                interaction != nil,
                "\(prototype.id) with \(prototype.interactions) resolved to nothing on a fresh instance"
            )
        }
    }
}
