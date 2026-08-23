import Testing
@testable import HeistCore

@Suite("Continuous actor separation")
struct AgentSeparationTests {
    @Test("Crossing trajectories collide between safe endpoints")
    func detectsBetweenSamples() {
        let distance = AgentSeparation.minimumSweptDistance(
            firstStart: WorldPoint(x: -1, y: 0, z: 0),
            firstEnd: WorldPoint(x: 1, y: 0, z: 0),
            secondStart: WorldPoint(x: 1, y: 0, z: 0),
            secondEnd: WorldPoint(x: -1, y: 0, z: 0)
        )
        #expect(distance == 0)
    }

    @Test("Parallel trajectories retain their spacing")
    func parallelSpacing() {
        let distance = AgentSeparation.minimumSweptDistance(
            firstStart: WorldPoint(x: 0, y: 0, z: 0),
            firstEnd: WorldPoint(x: 2, y: 0, z: 0),
            secondStart: WorldPoint(x: 0, y: 0, z: 1),
            secondEnd: WorldPoint(x: 2, y: 0, z: 1)
        )
        #expect(abs(distance - 1) < 1e-12)
    }
}
