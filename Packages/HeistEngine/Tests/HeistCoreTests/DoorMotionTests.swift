import Testing
@testable import HeistCore

@Suite("Door motion")
struct DoorMotionTests {
    let closed = WorldBox(
        center: WorldPoint(x: 0, y: 1, z: 0),
        width: 1, height: 2, depth: 0.08,
        surface: .wood, sourceID: "door"
    )

    @Test("Transition is deterministic and eased between exact endpoints")
    func transition() {
        let transition = DoorTransition(
            startedAt: 10, duration: 2, fromFraction: 0, toFraction: 1
        )
        #expect(transition.fraction(at: 9) == 0)
        #expect(transition.fraction(at: 11) == 0.5)
        #expect(transition.fraction(at: 12) == 1)
        #expect(transition.fraction(at: 11) == transition.fraction(at: 11))
    }

    @Test("Leaf centre rotates around the hinge rather than around itself")
    func hingeGeometry() {
        let opened = DoorGeometry.leafBox(
            closed: closed,
            hingeSide: .left,
            openAngleDegrees: 90,
            openFraction: 1
        )
        #expect(abs(opened.center.x + 0.5) < 0.001)
        #expect(abs(opened.center.z + 0.5) < 0.001)
        #expect(abs(opened.yaw - 90) < 0.001)
    }
}
