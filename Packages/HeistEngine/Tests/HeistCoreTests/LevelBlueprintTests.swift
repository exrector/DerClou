import Foundation
import Testing
@testable import HeistCore

@Suite("Level blueprint")
struct LevelBlueprintTests {
    @Test("Metric conversion round-trips")
    func metricRoundTrip() {
        let metrics = LevelMetrics(cellSize: 1.5)
        let point = CellPoint(3, 4)
        let world = metrics.worldPoint(point)

        #expect(world.x == 4.5)
        #expect(world.z == 6.0)
        #expect(metrics.cellPoint(world) == point)
    }

    @Test("office01 passes validation")
    func officeValidates() {
        let issues = LevelValidator.validate(.office01, catalog: .standard)
        #expect(!issues.hasErrors, "\(issues)")
    }

    @Test("An opening that runs past the end of its wall is an error")
    func openingOutOfBounds() {
        var level = LevelBlueprint.office01
        level.walls.append(
            WallSpec(
                id: "office01.wall.bad",
                start: CellPoint(0, 2),
                end: CellPoint(2, 2),
                openings: [WallOpening(kind: .doorway, center: 5, width: 1)]
            )
        )

        let issues = LevelValidator.validate(level, catalog: .standard)
        #expect(issues.errors.contains { $0.subject == "office01.wall.bad" })
    }

    @Test("Overlapping openings are an error")
    func overlappingOpenings() {
        var level = LevelBlueprint.office01
        level.walls.append(
            WallSpec(
                id: "office01.wall.overlap",
                start: CellPoint(0, 3),
                end: CellPoint(6, 3),
                openings: [
                    WallOpening(kind: .doorway, center: 2, width: 2),
                    WallOpening(kind: .doorway, center: 3, width: 2)
                ]
            )
        )

        let issues = LevelValidator.validate(level, catalog: .standard)
        #expect(issues.errors.contains { $0.subject == "office01.wall.overlap" })
    }

    @Test("An unknown prototype is an error")
    func unknownPrototype() {
        var level = LevelBlueprint.office01
        level.props.append(
            PropSpec(id: "office01.mystery", prototype: "prop.does.not.exist", position: CellPoint(2, 2))
        )

        let issues = LevelValidator.validate(level, catalog: .standard)
        #expect(issues.errors.contains { $0.subject == "office01.mystery" })
    }

    @Test("Duplicate IDs are an error")
    func duplicateIDs() {
        var level = LevelBlueprint.office01
        level.props.append(
            PropSpec(id: "office01.desk.a", prototype: "desk.office", position: CellPoint(3, 3))
        )

        let issues = LevelValidator.validate(level, catalog: .standard)
        #expect(issues.errors.contains { $0.subject == "office01.desk.a" })
    }

    @Test("A blueprint survives a JSON round-trip unchanged")
    func codableRoundTrip() throws {
        let level = LevelBlueprint.office01
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(level)
        let decoded = try JSONDecoder().decode(LevelBlueprint.self, from: data)

        #expect(decoded == level)
    }

    @Test("Per-instance config overrides prototype defaults")
    func configOverride() {
        let geometry = LevelGeometryBuilder.build(.office01)
        let lockedDoor = geometry.props.first { $0.id == "office01.door.b" }
        let openDoor = geometry.props.first { $0.id == "office01.door.a" }

        #expect(lockedDoor?.config["locked"]?.boolValue == true)
        #expect(lockedDoor?.config["lockDifficulty"]?.intValue == 2)
        // Untouched by the override, inherited from the prototype.
        #expect(lockedDoor?.config["openDuration"]?.doubleValue == 1.0)
        #expect(openDoor?.config["locked"]?.boolValue == false)
    }
}
