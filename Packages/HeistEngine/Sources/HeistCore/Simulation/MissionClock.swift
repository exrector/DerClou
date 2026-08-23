import Foundation

/// The mission's authoritative sense of time.
///
/// Everything that decides an outcome reads from here, never from render frames.
/// That separation is what lets the same plan be replayed, scrubbed, or
/// fast-forwarded and still produce the same result — and it is why a failure can
/// be reported as "seen at 00:31.4" rather than "seen at some point".
public struct MissionClock: Sendable, Equatable {
    /// Seconds since the mission started.
    public private(set) var elapsed: Double
    /// Multiplier applied to advancing time. 0 pauses; 2 runs double speed.
    public var rate: Double
    public private(set) var isRunning: Bool

    public init(elapsed: Double = 0, rate: Double = 1, isRunning: Bool = false) {
        self.elapsed = elapsed
        self.rate = rate
        self.isRunning = isRunning
    }

    public mutating func start() { isRunning = true }
    public mutating func pause() { isRunning = false }

    /// Returns to zero and stops. Used when a plan is reset for another attempt.
    public mutating func reset() {
        elapsed = 0
        isRunning = false
    }

    /// Advances by a frame's worth of real time, if running.
    public mutating func advance(byRealTime delta: Double) {
        guard isRunning, delta > 0 else { return }
        elapsed += delta * rate
    }

    /// Advances by an already-scaled deterministic simulation step.
    ///
    /// `FixedStepAccumulator` applies the playback rate before producing this
    /// value. Keeping the operation explicit prevents the rate being applied
    /// twice and makes replay/scrubbing independent from render-frame cadence.
    public mutating func advance(byMissionTime delta: Double) {
        guard isRunning, delta > 0 else { return }
        elapsed += delta
    }

    /// Moves directly to a moment. Used by timeline scrubbing and replay.
    public mutating func seek(to time: Double) {
        elapsed = max(0, time)
    }

    /// `mm:ss.t`, the format failures are reported in.
    public var formatted: String {
        let minutes = Int(elapsed) / 60
        let seconds = elapsed - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, seconds)
    }
}
