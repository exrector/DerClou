import Testing
@testable import HeistCore

@Suite("Alert and autonomous goals")
struct AlertModelTests {
    let location = WorldPoint(x: 8, y: 0, z: 3)

    @Test("A quiet sound can be ignored while a loud sound creates an investigation goal")
    func soundIntensityChangesReaction() {
        let quiet = PerceptionStimulus(
            id: "sound.quiet", kind: .sound, sourceID: "keys",
            location: location, missionTime: 2, intensity: 0.1
        )
        let loud = PerceptionStimulus(
            id: "sound.loud", kind: .sound, sourceID: "grinder",
            location: location, missionTime: 2, intensity: 1
        )

        #expect(GuardDecisionPolicy.goal(for: quiet, currentPatrolID: "patrol.a") == .patrol(routeID: "patrol.a"))
        #expect(GuardDecisionPolicy.goal(for: loud, currentPatrolID: "patrol.a") == .investigate(
            stimulusID: "sound.loud", location: location
        ))
    }

    @Test("Direct visual contact escalates and pursues without pausing anything")
    func visualContact() {
        let stimulus = PerceptionStimulus(
            id: "vision.1", kind: .guardVisualContact, sourceID: "guard.1",
            targetID: "thief.1", location: location, missionTime: 5, intensity: 1
        )
        var alert = AlertState()
        alert.observe(stimulus)

        #expect(alert.level() == .lockdown)
        #expect(GuardDecisionPolicy.goal(for: stimulus, currentPatrolID: "patrol.a") == .pursue(
            targetID: "thief.1", lastKnownLocation: location
        ))
    }

    @Test("An unexpectedly open secured door is evidence")
    func worldStateAnomaly() {
        let stimulus = PerceptionStimulus(
            id: "door.open", kind: .unexpectedWorldState, sourceID: "door.secure",
            location: location, missionTime: 10, intensity: 1
        )
        var alert = AlertState()
        alert.observe(stimulus)

        #expect(alert.level() == .investigating)
        #expect(GuardDecisionPolicy.goal(for: stimulus, currentPatrolID: "patrol.a") == .investigate(
            stimulusID: "door.open", location: location
        ))
    }

    @Test("Alert decay is deterministic mission time")
    func deterministicDecay() {
        var oneStep = AlertState(value: 0.8)
        var manySteps = AlertState(value: 0.8)
        oneStep.decay(to: 10)
        for second in 1...10 { manySteps.decay(to: Double(second)) }
        #expect(abs(oneStep.value - manySteps.value) < 1e-12)
    }
}
