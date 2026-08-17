import Testing
@testable import HeistCore

@Suite("Character profile")
struct CharacterProfileTests {
    @Test("The profile is derived from the catalog prototype")
    func derivedFromPrototype() throws {
        let prototype = try #require(PropCatalog.standard["actor.thief"])
        let profile = CharacterProfile(prototype: prototype)

        #expect(profile.width == 0.6)
        #expect(profile.height == 1.75)
        #expect(profile.radius == 0.3)
        #expect(profile.walkSpeed == 1.4)
    }

    @Test("Changing the prototype changes navigation, with nothing left behind")
    func navigationFollowsTheCatalog() throws {
        // The failure this guards against: character size written down separately
        // in the catalog and in the navigation settings, so a broader character
        // silently keeps routing through gaps it no longer fits.
        var prototypes = PropCatalog.standard.prototypes
        var wide = try #require(prototypes["actor.thief"])
        wide.footprint = CellSize(width: 1.2, depth: 1.2)
        prototypes["actor.thief"] = wide

        let catalog = PropCatalog(prototypes: Array(prototypes.values))
        let budget = NavigationBudget.forLevel(.office01, catalog: catalog)

        #expect(budget.characterRadius == 0.6)
        // A 1.2 m doorway no longer admits a 1.2 m-wide character.
        #expect(budget.minimumOpeningWidth > 1.2)

        let issues = LevelBuild.make(.office01, catalog: catalog).issues
        #expect(issues.contains { $0.subject == "office01.wall.corridor" })
    }

    @Test("Navigation is built for the largest actor in the level")
    func usesLargestActor() {
        let profile = CharacterProfile.navigationProfile(for: [
            PropCatalog.standard["actor.thief"]!,
            PropCatalog.standard["actor.guard"]!
        ])

        // The guard is the taller of the two; walkable space has to suit both.
        #expect(profile.height == 1.8)
        #expect(profile.width == 0.6)
    }

    @Test("Walk duration is a pure function of distance and speed")
    func duration() {
        let profile = CharacterProfile(width: 0.6, height: 1.75, walkSpeed: 1.4)
        #expect(profile.duration(forDistance: 14) == 10)
        #expect(profile.duration(forDistance: 0) == 0)
    }
}
