import Foundation
import Testing
@testable import HeistCore

@Suite("Autonomous navigation task")
struct AgentNavigationTaskTests {
    private let start = WorldPoint(x: 0, y: 0, z: 0)
    private let goalPoint = WorldPoint(x: 4, y: 0, z: 0)

    private func task(revision: Int = 0) -> AgentNavigationTask {
        AgentNavigationTask(
            goal: .investigate(stimulusID: "noise.1", location: goalPoint),
            start: start,
            path: PathResult(waypoints: [WorldPoint(x: 2, y: 0, z: 0), goalPoint], length: 4),
            startedAt: 10,
            speed: 2,
            initialFacing: 0,
            worldRevision: revision
        )
    }

    @Test("Pose is a pure function of mission time")
    func deterministicPose() {
        let route = task()
        #expect(route.state(at: 10).position == start)
        #expect(route.state(at: 11).position == WorldPoint(x: 2, y: 0, z: 0))
        #expect(route.state(at: 11.5).position == WorldPoint(x: 3, y: 0, z: 0))
        #expect(route.state(at: 12).activity == .arrived)
        #expect(route.state(at: 200).position == goalPoint)
    }

    @Test("Blocked task preserves its semantic goal")
    func blockedTaskKeepsGoal() {
        let goal = AgentGoal.secure(objectID: "safe", location: goalPoint)
        let route = AgentNavigationTask.blocked(
            goal: goal,
            at: start,
            facing: 90,
            startedAt: 3,
            worldRevision: 7
        )
        #expect(route.goal == goal)
        #expect(route.worldRevision == 7)
        #expect(route.state(at: 100).activity == .blocked)
        #expect(route.state(at: 100).position == start)
    }

    @Test("Production locomotion turns, accelerates, cruises and brakes on mission time")
    func timedMotionEnvelope() {
        let route = AgentNavigationTask(
            goal: .move(destination: goalPoint),
            start: start,
            path: PathResult(waypoints: [goalPoint], length: 4),
            startedAt: 0,
            speed: 1.4,
            initialFacing: 0,
            worldRevision: 0,
            acceleration: 2.8,
            deceleration: 2.8,
            maximumTurnRateDegrees: 90
        )

        #expect(route.state(at: 0).activity == .turningRight)
        #expect(abs(route.state(at: 0.5).facing - 45) < 1e-9)
        #expect(route.state(at: 0.5).position == start)
        #expect(route.state(at: 1.25).activity == .starting)
        #expect(route.state(at: 2).activity == .walking)
        #expect(route.state(at: 4).activity == .braking)
        #expect(route.state(at: route.duration).activity == .arrived)
        #expect(route.state(at: route.duration).position == goalPoint)
    }

    @Test("A short displacement is a short step rather than a full walk cycle")
    func shortStep() {
        let nearby = WorldPoint(x: 0.4, y: 0, z: 0)
        let route = AgentNavigationTask(
            goal: .move(destination: nearby),
            start: start,
            path: PathResult(waypoints: [nearby], length: 0.4),
            startedAt: 0,
            speed: 1.4,
            initialFacing: 90,
            worldRevision: 0,
            acceleration: 2.8,
            deceleration: 3.2,
            maximumTurnRateDegrees: 240
        )
        #expect(route.state(at: route.duration * 0.5).activity == .shortStep)
        #expect(route.state(at: route.duration).activity == .arrived)
    }

    @Test("A replacement trajectory preserves incoming walking speed")
    func preservesIncomingSpeed() {
        let route = AgentNavigationTask(
            goal: .move(destination: goalPoint),
            start: start,
            path: PathResult(waypoints: [goalPoint], length: 4),
            startedAt: 0,
            speed: 1.4,
            initialFacing: 90,
            initialSpeed: 1.1,
            worldRevision: 0,
            acceleration: 2.8,
            deceleration: 3.2,
            maximumTurnRateDegrees: 240
        )

        #expect(abs(route.state(at: 0).speed - 1.1) < 1e-9)
        #expect(route.state(at: 0).activity == .walking)
        #expect(route.state(at: 0.1).position.x > 0.1)
        #expect(route.state(at: route.duration).activity == .arrived)
    }

    @Test("Remaining corridor excludes links the actor has already consumed")
    func remainingCorridor() {
        let route = task()

        #expect(route.remainingWaypoints(at: 10) == route.waypoints)
        #expect(route.remainingWaypoints(at: 11).first == WorldPoint(x: 2, y: 0, z: 0))
        #expect(!route.remainingWaypoints(at: 11.5).contains(start))
        #expect(route.remainingWaypoints(at: 11.5).last == goalPoint)
        #expect(route.remainingWaypoints(at: 20) == [goalPoint])
    }

    @Test("A near-180-degree pivot is a turnaround, not an arbitrary left turn")
    func turnaround() {
        let behind = WorldPoint(x: 0, y: 0, z: -2)
        let route = AgentNavigationTask(
            goal: .move(destination: behind),
            start: start,
            path: PathResult(waypoints: [behind], length: 2),
            startedAt: 0,
            speed: 1.4,
            initialFacing: 0,
            worldRevision: 0,
            maximumTurnRateDegrees: 180
        )
        #expect(route.state(at: 0.25).activity == .turningAround)
        #expect(route.state(at: 0.25).position == start)
    }

    @Test("Movement equivalence matrix covers speed, distance and every turn class")
    func movementEquivalenceMatrix() {
        let headings: [Double] = [-180, -150, -120, -90, -45, 0, 45, 90, 120, 150, 180]
        let distances: [Double] = [0.3, 2, 6]
        let incomingSpeeds: [Double] = [0, 0.7, 1.4]

        for heading in headings {
            for distance in distances {
                for incomingSpeed in incomingSpeeds {
                    let radians = heading * .pi / 180
                    let destination = WorldPoint(
                        x: sin(radians) * distance,
                        y: 0,
                        z: cos(radians) * distance
                    )
                    let route = AgentNavigationTask(
                        goal: .move(destination: destination),
                        start: start,
                        path: PathResult(waypoints: [destination], length: distance),
                        startedAt: 7,
                        speed: 1.4,
                        initialFacing: 0,
                        initialSpeed: incomingSpeed,
                        worldRevision: 3,
                        acceleration: 2.8,
                        deceleration: 3.2,
                        maximumTurnRateDegrees: 240
                    )

                    var previousDistance = 0.0
                    let sampleCount = max(2, Int((route.duration * 60).rounded(.up)))
                    for sample in 0...sampleCount {
                        let time = 7 + min(route.duration, Double(sample) / 60)
                        let state = route.state(at: time)
                        #expect(state.position.x.isFinite)
                        #expect(state.position.z.isFinite)
                        #expect(state.facing.isFinite)
                        #expect(state.speed.isFinite && state.speed >= 0)
                        let progress = start.planarDistance(to: state.position)
                        #expect(progress + 1e-8 >= previousDistance)
                        #expect(progress <= distance + 1e-8)
                        previousDistance = progress
                    }

                    let final = route.state(at: 7 + route.duration)
                    #expect(final.activity == .arrived)
                    #expect(final.position.planarDistance(to: destination) < 1e-7)

                    if abs(heading) >= 150, route.duration > 0.1 {
                        let pivot = route.state(at: 7 + 0.05)
                        #expect(pivot.activity == .turningAround)
                        #expect(pivot.position == start)
                        #expect(pivot.speed == 0)
                    }
                }
            }
        }
    }

    @Test("Interaction approach brakes, aligns in place, then arrives")
    func finalInteractionAlignment() {
        let point = WorldPoint(x: 2, y: 0, z: 0)
        let route = AgentNavigationTask(
            goal: .interact(objectID: "door", location: point),
            start: start,
            path: PathResult(waypoints: [point], length: 2),
            startedAt: 0,
            speed: 1.4,
            initialFacing: 90,
            finalFacing: 0,
            worldRevision: 0,
            acceleration: 2.8,
            deceleration: 3.2,
            maximumTurnRateDegrees: 180
        )
        let motionEnd = route.duration - 0.5
        #expect(route.state(at: motionEnd - 0.01).activity == .braking)
        #expect(route.state(at: motionEnd + 0.1).activity == .turningLeft)
        #expect(route.state(at: motionEnd + 0.1).isAlignment)
        #expect(route.state(at: motionEnd + 0.1).position == point)
        #expect(route.state(at: route.duration).activity == .arrived)
        #expect(abs(route.state(at: route.duration).facing) < 1e-9)
    }
}
