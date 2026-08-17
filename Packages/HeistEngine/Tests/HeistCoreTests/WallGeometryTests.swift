import Testing
@testable import HeistCore

@Suite("Wall segmentation")
struct WallGeometryTests {
    let metrics = LevelMetrics.standard

    @Test("A wall with no openings is one full-height segment")
    func solidWall() {
        let wall = WallSpec(id: "w", start: CellPoint(0, 0), end: CellPoint(5, 0))
        let segments = wall.segments(metrics: metrics)

        #expect(segments.count == 1)
        #expect(segments[0].span == 0...5)
        #expect(segments[0].bottom == 0)
        #expect(segments[0].top == metrics.wallHeight)
    }

    @Test("A doorway splits the wall and leaves a lintel above it")
    func doorway() {
        let wall = WallSpec(
            id: "w",
            start: CellPoint(0, 0),
            end: CellPoint(6, 0),
            openings: [WallOpening(kind: .doorway, center: 3, width: 1)]
        )
        let segments = wall.segments(metrics: metrics)

        #expect(segments.count == 3)
        #expect(segments[0].span == 0...2.5)
        #expect(segments[1].span == 2.5...3.5)
        #expect(segments[1].bottom == metrics.doorwayHeight)
        #expect(segments[1].top == metrics.wallHeight)
        #expect(segments[2].span == 3.5...6)
    }

    @Test("A passage leaves no lintel")
    func passage() {
        let wall = WallSpec(
            id: "w",
            start: CellPoint(0, 0),
            end: CellPoint(6, 0),
            openings: [WallOpening(kind: .passage, center: 3, width: 2)]
        )
        let segments = wall.segments(metrics: metrics)

        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.bottom == 0 && $0.top == metrics.wallHeight })
    }

    @Test("A window leaves a sill below and a lintel above")
    func window() {
        let wall = WallSpec(
            id: "w",
            start: CellPoint(0, 0),
            end: CellPoint(4, 0),
            openings: [WallOpening(kind: .window, center: 2, width: 1.2, headHeight: 2.0, sillHeight: 0.9)]
        )
        let segments = wall.segments(metrics: metrics)

        #expect(segments.count == 4)
        let inOpening = segments.filter { $0.span.lowerBound >= 1.39 && $0.span.upperBound <= 2.61 }
        #expect(inOpening.count == 2)
        #expect(inOpening.contains { $0.bottom == 0 && $0.top == 0.9 })
        #expect(inOpening.contains { $0.bottom == 2.0 && $0.top == metrics.wallHeight })
    }

    @Test("Two openings in one wall produce four solid pieces")
    func twoDoorways() {
        let wall = WallSpec(
            id: "w",
            start: CellPoint(0, 0),
            end: CellPoint(14, 0),
            openings: [
                WallOpening(kind: .doorway, center: 10, width: 1),
                WallOpening(kind: .doorway, center: 3, width: 1)
            ]
        )
        let segments = wall.segments(metrics: metrics)

        // 3 full-height runs + 2 lintels
        #expect(segments.count == 5)
        // Openings are processed in order along the wall regardless of input order.
        #expect(segments.map(\.span.lowerBound) == [0, 2.5, 3.5, 9.5, 10.5])
    }

    @Test("Segmentation is deterministic")
    func deterministic() {
        let wall = LevelBlueprint.office01.walls.first { $0.id == "office01.wall.corridor" }!
        #expect(wall.segments(metrics: metrics) == wall.segments(metrics: metrics))
    }
}
