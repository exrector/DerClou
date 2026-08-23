import Testing
@testable import HeistCore

@Suite("Modular placement contract")
struct PlacementContractTests {
    @Test("Grid snapping is deterministic and independent of world cell size")
    func snapping() {
        let contract = PlacementContract(positionSnapCells: 0.25, rotationSnapDegrees: 15)
        #expect(contract.snapped(CellPoint(1.13, 2.62)) == CellPoint(1.25, 2.5))
        #expect(contract.snappedRotation(44) == 45)
        #expect(contract.isAligned(CellPoint(1.25, 2.5)))
        #expect(!contract.isAligned(CellPoint(1.2, 2.5)))
    }

    @Test("A canonical metric footprint converts into any authoring grid")
    func gridFootprint() throws {
        let desk = try #require(PropCatalog.standard["desk.office"])
        let footprint = desk.gridFootprint(metrics: LevelMetrics(cellSize: 0.5))
        #expect(footprint.width == desk.footprint.width * 2)
        #expect(footprint.depth == desk.footprint.depth * 2)
    }

    @Test("Imported art can fit canonical bounds without distorting proportions")
    func uniformNormalization() throws {
        let scale = try #require(AssetNormalizer.scale(
            source: MetricSize3D(width: 200, height: 100, depth: 50),
            target: MetricSize3D(width: 2, height: 2, depth: 1),
            policy: .uniformFit
        ))
        #expect(scale == MetricSize3D(width: 0.01, height: 0.01, depth: 0.01))
    }

    @Test("Door and actor boundaries remain separate typed values")
    func independentBoundaries() throws {
        let door = try #require(PropCatalog.standard["door.single"])
        let boundaries = door.placementContract.clearances
        #expect(boundaries.doorSweepMargin > 0)
        #expect(boundaries.actorSeparation > 0)
        #expect(boundaries.interactionStandoff > boundaries.collisionMargin)
    }

    @Test("Generated levels fail validation when an object ignores its snap contract")
    func validatorRejectsOffGridPlacement() {
        var level = LevelBlueprint.office01
        level.props[0].position = CellPoint(3.013, 6)
        level.props[0].rotation = 17
        let build = LevelBuild.make(level)
        #expect(build.issues.contains {
            $0.subject == level.props[0].id && $0.message.contains("placement grid")
        })
        #expect(build.issues.contains {
            $0.subject == level.props[0].id && $0.message.contains("degree increment")
        })
    }
}
