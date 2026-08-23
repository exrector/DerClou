import Foundation

/// Deterministic floor-plane segment query against a rotated world box.
/// Shared by navigation gates and other gameplay systems; presentation rays
/// must not own this geometry decision.
public enum WorldSegmentIntersection {
    public static func entryFraction(
        from start: WorldPoint,
        to end: WorldPoint,
        box: WorldBox,
        expansion: Double = 0
    ) -> Double? {
        let yaw = box.yaw * .pi / 180
        let c = cos(yaw), s = sin(yaw)
        func local(_ point: WorldPoint) -> (Double, Double) {
            let dx = point.x - box.center.x
            let dz = point.z - box.center.z
            return (c * dx - s * dz, s * dx + c * dz)
        }
        let a = local(start), b = local(end)
        let delta = (b.0 - a.0, b.1 - a.1)
        var entry = 0.0
        var exit = 1.0
        func clip(_ origin: Double, _ direction: Double, _ extent: Double) -> Bool {
            if abs(direction) < 1e-12 { return abs(origin) <= extent }
            var near = (-extent - origin) / direction
            var far = (extent - origin) / direction
            if near > far { swap(&near, &far) }
            entry = max(entry, near)
            exit = min(exit, far)
            return entry <= exit
        }
        guard clip(a.0, delta.0, box.width / 2 + expansion),
              clip(a.1, delta.1, box.depth / 2 + expansion),
              exit > 1e-9, entry < 1 - 1e-9 else { return nil }
        return max(0, entry)
    }
}
