import Foundation

/// Continuous planar separation for two linearly swept actor centres.
///
/// Local avoidance must inspect the whole fixed-step lookahead interval, not
/// only its endpoints: two capsules can exchange sides between samples while
/// both sampled distances appear safe.
public enum AgentSeparation {
    public static func minimumSweptDistance(
        firstStart: WorldPoint,
        firstEnd: WorldPoint,
        secondStart: WorldPoint,
        secondEnd: WorldPoint
    ) -> Double {
        let rx = firstStart.x - secondStart.x
        let rz = firstStart.z - secondStart.z
        let vx = (firstEnd.x - firstStart.x) - (secondEnd.x - secondStart.x)
        let vz = (firstEnd.z - firstStart.z) - (secondEnd.z - secondStart.z)
        let speedSquared = vx * vx + vz * vz
        let t = speedSquared > 1e-12
            ? min(1, max(0, -(rx * vx + rz * vz) / speedSquared))
            : 0
        return hypot(rx + vx * t, rz + vz * t)
    }
}
