import Foundation

public enum DoorHingeSide: String, Codable, Sendable, Equatable {
    case left
    case right
}

public struct DoorTransition: Sendable, Equatable {
    public var startedAt: Double
    public var duration: Double
    public var fromFraction: Double
    public var toFraction: Double

    public init(startedAt: Double, duration: Double, fromFraction: Double, toFraction: Double) {
        self.startedAt = startedAt
        self.duration = duration
        self.fromFraction = fromFraction
        self.toFraction = toFraction
    }

    public func fraction(at time: Double) -> Double {
        guard duration > 0 else { return toFraction }
        let linear = max(0, min(1, (time - startedAt) / duration))
        let eased = linear * linear * (3 - 2 * linear)
        return fromFraction + (toFraction - fromFraction) * eased
    }

    public func isFinished(at time: Double) -> Bool {
        time >= startedAt + duration
    }
}

public enum DoorGeometry {
    /// Live leaf volume after rotating around its hinge, for vision and other
    /// world queries. The authored closed box remains immutable.
    public static func leafBox(
        closed: WorldBox,
        hingeSide: DoorHingeSide,
        openAngleDegrees: Double,
        openFraction: Double
    ) -> WorldBox {
        let side = hingeSide == .left ? -1.0 : 1.0
        let closedYaw = closed.yaw * .pi / 180
        let hingeLocalX = side * closed.width / 2
        let hinge = WorldPoint(
            x: closed.center.x + cos(closedYaw) * hingeLocalX,
            y: closed.center.y,
            z: closed.center.z - sin(closedYaw) * hingeLocalX
        )
        let angle = openAngleDegrees * max(0, min(1, openFraction))
        let liveYawDegrees = closed.yaw + angle
        let liveYaw = liveYawDegrees * .pi / 180
        let centerFromHinge = -side * closed.width / 2

        return WorldBox(
            center: WorldPoint(
                x: hinge.x + cos(liveYaw) * centerFromHinge,
                y: closed.center.y,
                z: hinge.z - sin(liveYaw) * centerFromHinge
            ),
            width: closed.width,
            height: closed.height,
            depth: closed.depth,
            yaw: liveYawDegrees,
            surface: closed.surface,
            sourceID: closed.sourceID
        )
    }
}
