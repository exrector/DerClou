/// Converts variable render-frame time into deterministic mission-time steps.
///
/// Rendering may arrive at 60, 90 or 120 Hz and can occasionally hitch. Game
/// rules must still observe the same sequence of mission instants. The
/// accumulator therefore stores scaled mission time and releases only equal
/// steps. Presentation may interpolate separately; it never changes this clock.
public struct FixedStepAccumulator: Sendable, Equatable {
    public let stepDuration: Double
    public private(set) var accumulatedMissionTime: Double

    public init(
        stepDuration: Double = 1.0 / 60.0,
        accumulatedMissionTime: Double = 0
    ) {
        precondition(stepDuration > 0)
        self.stepDuration = stepDuration
        self.accumulatedMissionTime = max(0, accumulatedMissionTime)
    }

    /// Adds wall-clock time after applying the mission playback rate.
    public mutating func enqueue(realTimeDelta: Double, rate: Double) {
        guard realTimeDelta > 0, rate > 0 else { return }
        accumulatedMissionTime += realTimeDelta * rate
    }

    /// Returns one fixed mission step when enough time has accumulated.
    public mutating func popStep() -> Double? {
        // A small tolerance prevents binary floating-point residue from losing
        // a step when differently sized render frames sum to the same duration.
        guard accumulatedMissionTime + stepDuration * 1e-9 >= stepDuration else {
            return nil
        }
        accumulatedMissionTime = max(0, accumulatedMissionTime - stepDuration)
        return stepDuration
    }

    /// Fraction toward the next simulation state, for presentation only.
    public var interpolationAlpha: Double {
        min(1, accumulatedMissionTime / stepDuration)
    }

    public mutating func reset() {
        accumulatedMissionTime = 0
    }
}
