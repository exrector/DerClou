import Testing
@testable import HeistCore

@Suite("Safe gameplay bounds")
struct SafeGameplayBoundsTests {
    let level = LevelBlueprint.office01
    /// Measured on an iPhone 16 simulator in landscape. Note that the system
    /// reserves space on *both* sides, not just the physical housing side — an
    /// earlier one-sided fixture here missed a real placement bug.
    let viewport = (width: 852.0, height: 393.0)
    let insets = ScreenInsets(top: 0, leading: 59, bottom: 21, trailing: 59)

    var framing: CameraFraming {
        CameraFramingSolver.solve(
            bounds: level.bounds,
            metrics: level.metrics,
            aspectRatio: viewport.width / viewport.height,
            tiltDegrees: 24
        )
    }

    func bounds(_ insets: ScreenInsets) -> SafeGameplayBounds? {
        SafeAreaSolver.gameplayBounds(viewportSize: viewport, insets: insets, framing: framing)
    }

    @Test("With no insets the safe area is the whole view")
    func noInsets() throws {
        let full = try #require(bounds(.zero))
        let inset = try #require(bounds(insets))

        #expect(full.width > inset.width)
        #expect(full.depth > inset.depth)
    }

    @Test("Insets shrink the world region from the correct sides")
    func insetsShrinkTheRegion() throws {
        let full = try #require(bounds(.zero))

        // One side at a time, so each inset is attributed to the right edge.
        let leading = try #require(bounds(ScreenInsets(leading: 59)))
        #expect(leading.minX > full.minX)
        #expect(abs(leading.maxX - full.maxX) < 0.001)

        let trailing = try #require(bounds(ScreenInsets(trailing: 59)))
        #expect(trailing.maxX < full.maxX)
        #expect(abs(trailing.minX - full.minX) < 0.001)

        let bottom = try #require(bounds(ScreenInsets(bottom: 21)))
        #expect(bottom.maxZ < full.maxZ)
        #expect(abs(bottom.minZ - full.minZ) < 0.001)

        let top = try #require(bounds(ScreenInsets(top: 21)))
        #expect(top.minZ > full.minZ)
        #expect(abs(top.maxZ - full.maxZ) < 0.001)
    }

    @Test("Landscape insets are not assumed symmetric")
    func asymmetricInsets() throws {
        // The housing appears on different physical sides depending on which way
        // the device is rotated, so the rule must not assume a side.
        let left = try #require(bounds(ScreenInsets(leading: 59)))
        let right = try #require(bounds(ScreenInsets(trailing: 59)))

        #expect(left.minX > right.minX)
        #expect(left.maxX > right.maxX)
        #expect(abs(left.width - right.width) < 0.001)
    }

    @Test("office01 keeps every critical object inside the safe area")
    func officeIsSafe() throws {
        let safe = try #require(bounds(insets))
        let issues = SafeAreaSolver.placementIssues(for: level, catalog: .standard, bounds: safe)

        #expect(issues.isEmpty, "\(issues)")
    }

    @Test("An objective pushed under the sensor housing is reported")
    func criticalObjectOutsideIsReported() throws {
        let safe = try #require(bounds(insets))

        var broken = level
        // Far left edge of the building, where a leading inset bites.
        broken.props.append(
            PropSpec(id: "office01.loot.edge", prototype: "loot.cash", position: CellPoint(0.4, 0.4))
        )

        let issues = SafeAreaSolver.placementIssues(for: broken, catalog: .standard, bounds: safe)
        #expect(issues.contains { $0.subject == "office01.loot.edge" })
    }

    @Test("Scenery is allowed to run off the edge")
    func sceneryIsExempt() throws {
        let safe = try #require(bounds(insets))

        var level = self.level
        // A plant in the same spot that failed for loot: decoration may sit
        // behind a cutout, because nobody has to interact with it.
        level.props.append(
            PropSpec(id: "office01.plant.edge", prototype: "plant.potted", position: CellPoint(0.4, 0.4))
        )

        let issues = SafeAreaSolver.placementIssues(for: level, catalog: .standard, bounds: safe)
        #expect(!issues.contains { $0.subject == "office01.plant.edge" })
    }

    @Test("A degenerate viewport yields no bounds instead of nonsense")
    func degenerate() {
        #expect(SafeAreaSolver.gameplayBounds(
            viewportSize: (width: 0, height: 0),
            insets: .zero,
            framing: framing
        ) == nil)

        // Insets larger than the view itself.
        #expect(SafeAreaSolver.gameplayBounds(
            viewportSize: viewport,
            insets: ScreenInsets(leading: 900, trailing: 900),
            framing: framing
        ) == nil)
    }
}
