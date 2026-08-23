import Testing
@testable import HeistCore

@Suite("Guard vision")
struct VisionTests {
    let config = VisionConfig(range: 10, fieldOfViewDegrees: 90)
    let observer = WorldPoint(x: 0, y: 0, z: 0)

    @Test("Guard and camera perception profiles are intentionally different")
    func sourceProfiles() {
        #expect(VisionProfiles.guardActor.range > VisionProfiles.securityCamera.range)
        #expect(
            VisionProfiles.guardActor.fieldOfViewDegrees
                < VisionProfiles.securityCamera.fieldOfViewDegrees
        )
    }

    @Test("Camera scan is a pure repeating function of mission time")
    func cameraScan() {
        let first = VisionScan.facing(baseDegrees: 20, arcDegrees: 80, period: 8, time: 1.25)
        let repeated = VisionScan.facing(baseDegrees: 20, arcDegrees: 80, period: 8, time: 9.25)
        #expect(abs(first - repeated) < 0.000_001)
    }

    @Test("Displayed ray stops at the same wall used for detection")
    func clippedDisplayedRay() {
        let reach = VisionSolver.visibleReach(
            observer: WorldPoint(x: 0, y: 1.5, z: 0),
            targetHeight: 1.5,
            facingDegrees: 0,
            maxRange: 10,
            occluders: [wall(x: 0, z: 4)]
        )
        #expect(reach > 3.8 && reach < 4)
    }

    func wall(id: String = "wall", x: Double, z: Double, yaw: Double = 0) -> WorldBox {
        WorldBox(
            center: WorldPoint(x: x, y: 1.5, z: z),
            width: 4, height: 3, depth: 0.2, yaw: yaw,
            surface: .plaster, sourceID: id
        )
    }

    @Test("A clear target inside range and cone is visible")
    func clearTarget() {
        let result = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0,
            target: WorldPoint(x: 2, y: 0, z: 5),
            config: config, occluders: []
        )
        #expect(result.isVisible)
    }

    @Test("Range and cone boundaries use the authored numbers")
    func boundaries() {
        let edgeOfRange = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0,
            target: WorldPoint(x: 0, y: 0, z: 10), config: config, occluders: []
        )
        let edgeOfCone = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0,
            target: WorldPoint(x: 5, y: 0, z: 5), config: config, occluders: []
        )
        #expect(edgeOfRange.isVisible)
        #expect(edgeOfCone.isVisible)
    }

    @Test("Targets outside range or behind the guard are rejected")
    func rangeAndFacing() {
        let far = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0,
            target: WorldPoint(x: 0, y: 0, z: 10.01), config: config, occluders: []
        )
        let behind = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0,
            target: WorldPoint(x: 0, y: 0, z: -2), config: config, occluders: []
        )
        if case .outOfRange = far {} else { Issue.record("Expected out of range, got \(far)") }
        if case .outsideFieldOfView = behind {} else { Issue.record("Expected outside FOV, got \(behind)") }
    }

    @Test("A wall blocks sight but a nearby wall that misses the ray does not")
    func wallOcclusion() {
        let target = WorldPoint(x: 0, y: 0, z: 8)
        let blocked = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0, target: target,
            config: config, occluders: [wall(x: 0, z: 4)]
        )
        let clear = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0, target: target,
            config: config, occluders: [wall(x: 4, z: 4)]
        )
        #expect(blocked == .occluded(by: "wall"))
        #expect(clear.isVisible)
    }

    @Test("Rotated wall footprints occlude correctly")
    func rotatedWall() {
        let result = VisionSolver.evaluate(
            observer: observer, facingDegrees: 90,
            target: WorldPoint(x: 8, y: 0, z: 0),
            config: config, occluders: [wall(x: 4, z: 0, yaw: 90)]
        )
        #expect(result == .occluded(by: "wall"))
    }

    @Test("A doorway lintel above eye height does not block sight")
    func lintelDoesNotBlock() {
        let lintel = WorldBox(
            center: WorldPoint(x: 0, y: 2.55, z: 4),
            width: 2, height: 0.9, depth: 0.2,
            surface: .plaster, sourceID: "door.lintel"
        )
        let result = VisionSolver.evaluate(
            observer: WorldPoint(x: 0, y: 1.55, z: 0), facingDegrees: 0,
            target: WorldPoint(x: 0, y: 1.5, z: 8),
            config: config, occluders: [lintel]
        )
        #expect(result.isVisible)
    }

    @Test("The reported blocker is stable regardless of input order")
    func deterministicBlocker() {
        let target = WorldPoint(x: 0, y: 0, z: 8)
        let a = wall(id: "a", x: 0, z: 5)
        let b = wall(id: "b", x: 0, z: 3)
        let first = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0, target: target,
            config: config, occluders: [b, a]
        )
        let second = VisionSolver.evaluate(
            observer: observer, facingDegrees: 0, target: target,
            config: config, occluders: [a, b]
        )
        #expect(first == .occluded(by: "a"))
        #expect(first == second)
    }
}
