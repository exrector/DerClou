import Foundation

public enum VisionSourceKind: String, Sendable, Codable, Equatable {
    case guardActor
    case securityCamera
}

/// The authored numbers that define a watcher. Kept in HeistCore so planning,
/// playback and the RealityKit visualization all consume the same values.
public struct VisionConfig: Sendable, Equatable {
    public var range: Double
    public var fieldOfViewDegrees: Double

    public init(range: Double, fieldOfViewDegrees: Double) {
        self.range = range
        self.fieldOfViewDegrees = fieldOfViewDegrees
    }
}

public enum VisionProfiles {
    /// Guards read farther but have a deliberately narrower human cone.
    public static let guardActor = VisionConfig(range: 10, fieldOfViewDegrees: 70)
    /// Cameras cover a short, broad slice of space.
    public static let securityCamera = VisionConfig(range: 6, fieldOfViewDegrees: 120)
}

/// Pure deterministic scan motion used by security cameras.
public enum VisionScan {
    public static func facing(
        baseDegrees: Double,
        arcDegrees: Double,
        period: Double,
        time: Double
    ) -> Double {
        guard arcDegrees != 0, period > 0 else {
            return PatrolRoute.normalizedYaw(baseDegrees)
        }
        let phase = (time / period) * 2 * Double.pi
        return PatrolRoute.normalizedYaw(baseDegrees + sin(phase) * arcDegrees / 2)
    }
}

/// Exact reason a target is or is not seen. Mission failure can therefore be
/// explained to the player instead of being reduced to an opaque Boolean.
public enum VisionResult: Sendable, Equatable {
    case visible(distance: Double)
    case outOfRange(distance: Double)
    case outsideFieldOfView(angleDegrees: Double)
    case occluded(by: String)

    public var isVisible: Bool {
        if case .visible = self { return true }
        return false
    }
}

public struct DetectionEvent: Sendable, Equatable {
    public var sourceID: String
    public var sourceKind: VisionSourceKind
    public var targetID: String
    public var missionTime: Double

    public init(
        sourceID: String,
        sourceKind: VisionSourceKind,
        targetID: String,
        missionTime: Double
    ) {
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.targetID = targetID
        self.missionTime = missionTime
    }
}

/// Deterministic line of sight for guards and cameras. Range and facing are
/// measured on the floor plane; occlusion uses the full wall volume so a
/// doorway lintel does not behave like a solid wall at eye height.
public enum VisionSolver {
    public static func evaluate(
        observer: WorldPoint,
        facingDegrees: Double,
        target: WorldPoint,
        config: VisionConfig,
        occluders: [WorldBox]
    ) -> VisionResult {
        let offset = (target - observer).onFloorPlane
        let distance = offset.planarLength

        guard distance <= max(0, config.range) else {
            return .outOfRange(distance: distance)
        }

        if distance > 1e-9 {
            let yaw = facingDegrees * .pi / 180
            let forward = WorldPoint(x: sin(yaw), y: 0, z: cos(yaw))
            let cosine = max(-1, min(1, forward.dot(offset) / distance))
            let angle = acos(cosine) * 180 / .pi
            guard angle <= max(0, config.fieldOfViewDegrees) / 2 + 1e-9 else {
                return .outsideFieldOfView(angleDegrees: angle)
            }
        }

        // Stable source order makes the reported blocker deterministic even
        // when a ray crosses two wall segments at the same point.
        for wall in occluders.sorted(by: { $0.sourceID < $1.sourceID }) {
            if intersectionEntry(observer, target, box: wall) != nil {
                return .occluded(by: wall.sourceID)
            }
        }

        return .visible(distance: distance)
    }

    /// Distance a displayed sight ray may travel before the first occluder.
    /// The endpoint height lets a ceiling camera ray slope toward a person's
    /// eye height while a guard ray stays approximately horizontal.
    public static func visibleReach(
        observer: WorldPoint,
        targetHeight: Double,
        facingDegrees: Double,
        maxRange: Double,
        occluders: [WorldBox]
    ) -> Double {
        let range = max(0, maxRange)
        guard range > 0 else { return 0 }
        let yaw = facingDegrees * .pi / 180
        let end = WorldPoint(
            x: observer.x + sin(yaw) * range,
            y: targetHeight,
            z: observer.z + cos(yaw) * range
        )
        let firstEntry = occluders.compactMap {
            intersectionEntry(observer, end, box: $0)
        }.min() ?? 1
        return range * max(0, min(1, firstEntry))
    }

    private static func intersectionEntry(
        _ start: WorldPoint,
        _ end: WorldPoint,
        box: WorldBox
    ) -> Double? {
        let yaw = box.yaw * .pi / 180
        let c = cos(yaw), s = sin(yaw)

        func local(_ point: WorldPoint) -> (x: Double, z: Double) {
            let dx = point.x - box.center.x
            let dz = point.z - box.center.z
            return (x: c * dx - s * dz, z: s * dx + c * dz)
        }

        let a = local(start)
        let b = local(end)
        let direction = (x: b.x - a.x, z: b.z - a.z)
        let startY = start.y - box.center.y
        let deltaY = end.y - start.y
        var entry = 0.0
        var exit = 1.0

        func clip(origin: Double, delta: Double, halfExtent: Double) -> Bool {
            if abs(delta) < 1e-12 {
                return abs(origin) <= halfExtent
            }
            var near = (-halfExtent - origin) / delta
            var far = (halfExtent - origin) / delta
            if near > far { swap(&near, &far) }
            entry = max(entry, near)
            exit = min(exit, far)
            return entry <= exit
        }

        guard clip(origin: a.x, delta: direction.x, halfExtent: box.width / 2),
              clip(origin: a.z, delta: direction.z, halfExtent: box.depth / 2),
              clip(origin: startY, delta: deltaY, halfExtent: box.height / 2) else {
            return nil
        }

        // Contact exactly at either actor is not an intervening wall.
        return exit > 1e-9 && entry < 1 - 1e-9 ? max(0, entry) : nil
    }
}
