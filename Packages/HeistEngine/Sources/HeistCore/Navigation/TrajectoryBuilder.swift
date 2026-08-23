import Foundation

/// Converts a legal path polyline into a denser, rounded locomotion trajectory.
/// Every inserted segment is checked against the same walkability grid, so
/// visual smoothness can never cut a corner the character body cannot clear.
public enum TrajectoryBuilder {
    /// Rounds authored/pathfinder corners and, when there is enough legal
    /// floor, joins the replacement route to the actor's current heading with
    /// a cubic curve. This is the navigation equivalent of steering into a
    /// bend: a replan does not first rotate the body to the new first link.
    ///
    /// Near reversals deliberately remain pivots. A forward-moving curve for a
    /// 180-degree change would need an arbitrary side and a large amount of
    /// floor, so the explicit turnaround locomotion block is more truthful.
    public static func continuous(
        start: WorldPoint,
        path: PathResult,
        initialFacing: Double,
        in grid: NavGrid,
        character: CharacterProfile
    ) -> PathResult {
        let roundedPath = rounded(start: start, path: path, in: grid, character: character)
        let points = [start] + roundedPath.waypoints
        guard points.count > 1 else { return roundedPath }

        let routeFacing = PatrolRoute.yaw(from: points[0], to: points[1])
        let headingChange = abs(PatrolRoute.shortestTurn(from: initialFacing, to: routeFacing))
        guard headingChange >= 4, headingChange <= 110 else { return roundedPath }

        let totalLength = polylineLength(points)
        guard totalLength > max(grid.cellSize * 4, 0.35) else { return roundedPath }

        // Roughly two thirds of one second at the authored walking pace, but
        // never consume most of a short route. The character's comfort radius
        // keeps this scale consistent when profiles change.
        let preferredBlend = max(
            character.preferredCornerRadius * 2.4,
            character.walkSpeed * 0.65
        )
        let maximumBlend = min(preferredBlend, totalLength * 0.55)
        let minimumBlend = max(grid.cellSize * 4, character.preferredCornerRadius)
        guard maximumBlend >= minimumBlend else { return roundedPath }

        let radians = initialFacing * .pi / 180
        let startDirection = WorldPoint(x: sin(radians), y: 0, z: cos(radians))

        // A curve may bulge into a nearby wall. Try progressively shorter
        // joins, accepting one only after every chord passes the same eroded
        // navigation grid as the original route.
        for scale in [1.0, 0.82, 0.66, 0.5] {
            let blendDistance = maximumBlend * scale
            guard blendDistance >= minimumBlend,
                  let join = split(points: points, atDistance: blendDistance) else { continue }

            let joinDirection = (join.segmentEnd - join.segmentStart).normalized
            let handle = blendDistance * 0.38
            let control1 = start + startDirection * handle
            let control2 = join.point - joinDirection * handle
            let sampleCount = max(
                16,
                Int((blendDistance / max(grid.cellSize * 0.3, 0.025)).rounded(.up))
            )
            var curve: [WorldPoint] = []
            for sample in 1...sampleCount {
                let t = Double(sample) / Double(sampleCount)
                let inverse = 1 - t
                curve.append((
                    start * (inverse * inverse * inverse)
                        + control1 * (3 * inverse * inverse * t)
                        + control2 * (3 * inverse * t * t)
                        + join.point * (t * t * t)
                ).onFloorPlane)
            }

            var previous = start
            let legal = curve.allSatisfy { point in
                defer { previous = point }
                return PathFinder.hasLineOfSight(from: previous, to: point, in: grid)
            }
            guard legal else { continue }

            let stitched = [start] + curve + join.remaining.dropFirst()
            return result(for: stitched, excludingStart: true)
        }
        return roundedPath
    }

    public static func rounded(
        start: WorldPoint,
        path: PathResult,
        in grid: NavGrid,
        character: CharacterProfile
    ) -> PathResult {
        var source = [start] + path.waypoints
        source = source.reduce(into: []) { result, point in
            if result.last?.planarDistance(to: point) ?? .greatestFiniteMagnitude > 1e-6 {
                result.append(point.onFloorPlane)
            }
        }
        guard source.count > 2, character.preferredCornerRadius > 0 else {
            return result(for: source, excludingStart: true)
        }

        var output = [source[0]]
        for index in 1..<(source.count - 1) {
            let a = source[index - 1]
            let corner = source[index]
            let c = source[index + 1]
            let incoming = a - corner
            let outgoing = c - corner
            let incomingLength = incoming.planarLength
            let outgoingLength = outgoing.planarLength
            guard incomingLength > 1e-6, outgoingLength > 1e-6 else { continue }

            let dot = max(-1, min(1,
                incoming.normalized.x * outgoing.normalized.x
                    + incoming.normalized.z * outgoing.normalized.z
            ))
            // Direction vectors both point away from the corner. -1 is a
            // straight continuation and needs no arc.
            if dot < -0.995 {
                output.append(corner)
                continue
            }

            var radius = min(
                character.preferredCornerRadius,
                incomingLength * 0.42,
                outgoingLength * 0.42
            )
            var accepted: [WorldPoint]?
            for _ in 0..<5 where radius >= grid.cellSize {
                let entry = corner + incoming.normalized * radius
                let exit = corner + outgoing.normalized * radius
                let samples = max(4, Int((radius * 2 / max(grid.cellSize, 0.01)).rounded(.up)))
                var candidate: [WorldPoint] = [entry]
                for sample in 1...samples {
                    let t = Double(sample) / Double(samples)
                    let inverse = 1 - t
                    candidate.append(
                        (entry * (inverse * inverse)
                            + corner * (2 * inverse * t)
                            + exit * (t * t)).onFloorPlane
                    )
                }

                var previous = output.last ?? a
                let legal = candidate.allSatisfy { point in
                    defer { previous = point }
                    return PathFinder.hasLineOfSight(from: previous, to: point, in: grid)
                }
                if legal {
                    accepted = candidate
                    break
                }
                radius *= 0.5
            }

            if let accepted {
                output.append(contentsOf: accepted)
            } else {
                output.append(corner)
            }
        }
        output.append(source[source.count - 1])
        return result(for: output, excludingStart: true)
    }

    private static func result(for points: [WorldPoint], excludingStart: Bool) -> PathResult {
        let waypoints = excludingStart ? Array(points.dropFirst()) : points
        let length = zip(points, points.dropFirst()).reduce(0) {
            $0 + $1.0.planarDistance(to: $1.1)
        }
        return PathResult(waypoints: waypoints, length: length)
    }

    private struct PolylineSplit {
        var point: WorldPoint
        var segmentStart: WorldPoint
        var segmentEnd: WorldPoint
        var remaining: [WorldPoint]
    }

    private static func split(points: [WorldPoint], atDistance requested: Double) -> PolylineSplit? {
        var remainingDistance = max(0, requested)
        for index in 0..<(points.count - 1) {
            let from = points[index]
            let to = points[index + 1]
            let length = from.planarDistance(to: to)
            guard length > 1e-9 else { continue }
            if remainingDistance <= length {
                let point = (from + (to - from) * (remainingDistance / length)).onFloorPlane
                return PolylineSplit(
                    point: point,
                    segmentStart: from,
                    segmentEnd: to,
                    remaining: [point] + Array(points.dropFirst(index + 1))
                )
            }
            remainingDistance -= length
        }
        return nil
    }

    private static func polylineLength(_ points: [WorldPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) {
            $0 + $1.0.planarDistance(to: $1.1)
        }
    }
}
