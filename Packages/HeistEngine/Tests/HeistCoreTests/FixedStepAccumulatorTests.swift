import Testing
@testable import HeistCore

@Suite("Fixed simulation step")
struct FixedStepAccumulatorTests {
    @Test("Different render-frame chunks produce the same mission steps")
    func frameChunkingDoesNotChangeSimulation() {
        var fine = FixedStepAccumulator(stepDuration: 0.1)
        var coarse = FixedStepAccumulator(stepDuration: 0.1)

        for _ in 0..<10 {
            fine.enqueue(realTimeDelta: 0.03, rate: 1)
        }
        for _ in 0..<3 {
            coarse.enqueue(realTimeDelta: 0.1, rate: 1)
        }

        #expect(drain(&fine) == drain(&coarse))
        #expect(fine.accumulatedMissionTime < 1e-9)
        #expect(coarse.accumulatedMissionTime < 1e-9)
    }

    @Test("Playback rate scales queued mission time, not step size")
    func playbackRateKeepsFixedStep() {
        var accumulator = FixedStepAccumulator(stepDuration: 0.05)
        accumulator.enqueue(realTimeDelta: 0.1, rate: 2)

        let steps = drain(&accumulator)
        #expect(steps == [0.05, 0.05, 0.05, 0.05])
    }

    @Test("Paused or invalid time never enters the simulation")
    func invalidTimeIsIgnored() {
        var accumulator = FixedStepAccumulator(stepDuration: 0.1)
        accumulator.enqueue(realTimeDelta: 1, rate: 0)
        accumulator.enqueue(realTimeDelta: -1, rate: 1)

        #expect(accumulator.popStep() == nil)
        #expect(accumulator.interpolationAlpha == 0)
    }

    private func drain(_ accumulator: inout FixedStepAccumulator) -> [Double] {
        var result: [Double] = []
        while let step = accumulator.popStep() {
            result.append(step)
        }
        return result
    }
}
