import Testing
@testable import HeistCore

@Suite("Door traversal gates")
struct DoorTraversalPlannerTests {
    @Test("The first closed portal on a route is selected in travel order")
    func firstGate() throws {
        let path = PathResult(waypoints: [
            WorldPoint(x: 0, y: 0, z: 2),
            WorldPoint(x: 0, y: 0, z: -4)
        ], length: 6)
        let near = DoorTraversalGate(
            id: "near",
            box: WorldBox(center: WorldPoint(x: 0, y: 1, z: 0), width: 1, height: 2, depth: 0.08, surface: .wood, sourceID: "near")
        )
        let far = DoorTraversalGate(
            id: "far",
            box: WorldBox(center: WorldPoint(x: 0, y: 1, z: -2), width: 1, height: 2, depth: 0.08, surface: .wood, sourceID: "far")
        )

        let crossing = try #require(DoorTraversalPlanner.firstCrossing(path: path, gates: [far, near]))
        #expect(crossing.gate.id == "near")
        #expect(crossing.approachSide == ApproachPointSolver.Side.front)
    }

    @Test("A route beside a door does not invent a traversal")
    func missesGate() {
        let path = PathResult(waypoints: [
            WorldPoint(x: 2, y: 0, z: 2), WorldPoint(x: 2, y: 0, z: -2)
        ], length: 4)
        let gate = DoorTraversalGate(
            id: "door",
            box: WorldBox(center: WorldPoint(x: 0, y: 1, z: 0), width: 1, height: 2, depth: 0.08, surface: .wood, sourceID: "door")
        )
        #expect(DoorTraversalPlanner.firstCrossing(path: path, gates: [gate]) == nil)
    }
}
