import Testing
import RealityKit
import HeistCore
// Plain import, not @testable: the engine modules are linked into the host app,
// and a second copy inside the test bundle makes RealityKit trap when the same
// component type is registered twice.
import HeistKit

/// Runtime checks that need the real RealityKit stack, so they run on a
/// simulator or device rather than in the pure-Swift package tests.
@MainActor
@Suite("Runtime navigation", .serialized)
struct RuntimeNavigationTests {
    @Test("The level scene builds with no blueprint errors")
    func sceneBuilds() {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        #expect(!built.issues.hasErrors, "\(built.issues)")
        #expect(built.actors.count == 2)
        #expect(built.root.children.count > 10)
    }

    @Test("Every office actor resolves the Walk animation contract")
    func everyActorHasWalkAnimation() {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        #expect(built.actors.count == 2)
        for (actorID, actorEntity) in built.actors {
            let diagnostics = actorEntity.children.map { child in
                let library: AnimationLibraryComponent? =
                    child.components[AnimationLibraryComponent.self]
                let clips = child.availableAnimations.map {
                    "name=\($0.name ?? "nil")"
                }
                return "\(child.name): clips=\(clips), library=\(library != nil)"
            }
            let walk = CharacterAnimationLibrary.animation(
                named: WalkAnimationSync.clipName,
                on: actorEntity
            )
            #expect(
                walk != nil,
                "Actor \(actorID) does not satisfy the Walk animation contract: \(diagnostics)"
            )
            if let walk {
                #expect(
                    (1.0...1.3).contains(walk.definition.duration),
                    "Actor \(actorID) has the wrong Walk source: duration \(walk.definition.duration)s; expected the 36-frame Standard Walk"
                )
            }
            let extracted: [CharacterAnimationSemantic] = [
                .idle, .startWalking, .turnLeft, .turnRight, .turnAround,
                .openDoor, .pressButton, .pullLever, .look
            ]
            for semantic in extracted {
                #expect(
                    CharacterAnimationLibrary.animation(
                        named: semantic.rawValue,
                        on: actorEntity
                    ) != nil,
                    "Actor \(actorID) has no extracted \(semantic.rawValue) clip: \(diagnostics)"
                )
            }
        }
    }

    @Test("The walkability grid is built with the scene")
    func navigationGridIsBuilt() {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        #expect(built.navGrid.cellCount > 0)
        #expect(built.navGrid.walkable.contains(true))
    }

    @Test("A floor tap returns immediately and commits its worker plan")
    func tapPlanningDoesNotFreezeWorld() async throws {
        let session = GameSession()
        session.load(.office01)
        let target = LevelMetrics.standard.worldPoint(CellPoint(9.5, 8.6))

        let duration = ContinuousClock().measure {
            session.requestMoveSelectedActor(to: SIMD3<Float>(
                Float(target.x), 0, Float(target.z)
            ))
        }

        let actor = try #require(session.selectedActorEntity)
        for _ in 0..<200 where actor.components[AgentNavigationComponent.self]?.task == nil {
            await Task.yield()
        }
        #expect(actor.components[AgentNavigationComponent.self]?.task != nil)
        #expect(
            duration < .milliseconds(8),
            "Tap submission occupied the main actor for \(duration); path search must stay on its worker"
        )
    }

    @Test("Sequential taps atomically retarget a moving actor without an exposed stop")
    func sequentialTapsPreserveMotion() async throws {
        let session = GameSession()
        session.load(.office01)
        let thiefID = "office01.thief.01"
        let actor = try #require(session.level?.actors[thiefID])
        let start = WorldPoint(x: 10, y: 0, z: 8)
        let firstGoal = WorldPoint(x: 13.2, y: 0, z: 8)
        let secondGoal = WorldPoint(x: 13.2, y: 0, z: 9)
        #expect(session.placeActor(id: thiefID, at: start, facing: 90))

        var navigation = try #require(actor.components[AgentNavigationComponent.self])
        navigation.task = AgentNavigationTask(
            goal: .move(destination: firstGoal),
            start: start,
            path: PathResult(waypoints: [firstGoal], length: 3.2),
            startedAt: 0,
            speed: navigation.character.walkSpeed,
            initialFacing: 90,
            worldRevision: session.navigationWorld?.revision ?? 0,
            acceleration: navigation.character.acceleration,
            deceleration: navigation.character.deceleration,
            maximumTurnRateDegrees: navigation.character.maximumTurnRateDegrees
        )
        actor.components[AgentNavigationComponent.self] = navigation
        session.startClock()
        for _ in 0..<45 { session.tick(realTimeDelta: 1.0 / 60.0) }

        let beforeCommand = try #require(actor.components[AgentNavigationComponent.self]?.task)
        let commandTime = session.clock.elapsed
        let speedAtCommand = beforeCommand.state(at: commandTime).speed
        #expect(speedAtCommand > 0.2)

        session.requestMoveSelectedActor(to: SIMD3<Float>(
            Float(secondGoal.x), 0, Float(secondGoal.z)
        ))

        // Submission itself must not clear or replace the committed route.
        let whilePlanning = try #require(actor.components[AgentNavigationComponent.self]?.task)
        #expect(whilePlanning == beforeCommand)
        #expect(whilePlanning.state(at: commandTime).speed == speedAtCommand)

        for _ in 0..<400 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            if let task = actor.components[AgentNavigationComponent.self]?.task,
               case .move(let destination) = task.goal,
               destination.planarDistance(to: secondGoal) < 1e-5 { break }
            try await Task.sleep(for: .milliseconds(2))
        }

        let retargeted = try #require(actor.components[AgentNavigationComponent.self]?.task)
        if case .move(let destination) = retargeted.goal {
            #expect(destination.planarDistance(to: secondGoal) < 1e-5)
        } else {
            Issue.record("Retargeted task has the wrong semantic goal: \(retargeted.goal)")
        }
        #expect(retargeted.startedAt >= commandTime)
        #expect(retargeted.initialSpeed > 0.2)
        let oldLiveAtHandoff = beforeCommand.state(at: retargeted.startedAt)
        #expect(retargeted.waypoints.first?.planarDistance(to: oldLiveAtHandoff.position) ?? 99 < 0.08)
        #expect(retargeted.state(at: retargeted.startedAt).activity != .starting)
    }

    @Test("The shared action state distinguishes turnaround, alignment and interaction")
    func universalActionStateMachine() {
        let character = CharacterProfile.standard
        let point = WorldPoint(x: 1, y: 0, z: 1)
        let turnaround = CharacterActionIntentResolver.task(
            AgentNavigationTask.State(
                position: point,
                facing: 90,
                activity: .turningAround
            ),
            character: character
        )
        let alignment = CharacterActionIntentResolver.task(
            AgentNavigationTask.State(
                position: point,
                facing: 0,
                activity: .turningLeft,
                isAlignment: true
            ),
            character: character
        )
        let interaction = CharacterActionIntentResolver.interaction(.toggleSwitch)

        #expect(turnaround.phase == .turningAround)
        #expect(turnaround.animation == .turnAround)
        #expect(turnaround.fallbackAnimation == .walk)
        #expect(alignment.phase == .aligningLeft)
        #expect(interaction.phase == .interacting)
        #expect(interaction.animation == .pressButton)

        let entity = Entity()
        var machine = CharacterActionStateComponent()
        machine.synchronize(to: turnaround, on: entity, missionTime: 1)
        #expect(machine.phase == .turningAround)
        machine.synchronize(to: alignment, on: entity, missionTime: 2)
        #expect(machine.phase == .aligningLeft)
        machine.synchronize(to: interaction, on: entity, missionTime: 3)
        #expect(machine.phase == .interacting)
    }

    @Test("Guard vision uses catalog values and has a matching scene overlay")
    func guardVisionIsDataDriven() throws {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)
        let guardEntity = try #require(built.actors["office01.guard.01"])
        let guardVision = try #require(guardEntity.components[VisionSourceComponent.self])
        let cameraEntity = try #require(built.visionSources["office01.camera.corridor"])
        let cameraVision = try #require(cameraEntity.components[VisionSourceComponent.self])

        #expect(guardVision.config == VisionProfiles.guardActor)
        #expect(cameraVision.config == VisionProfiles.securityCamera)
        #expect(guardVision.config.range > cameraVision.config.range)
        #expect(guardVision.config.fieldOfViewDegrees < cameraVision.config.fieldOfViewDegrees)
        #expect(guardEntity.children.contains { $0.name == "vision.cone" })
        #expect(cameraEntity.children.contains { $0.name == "vision.cone" })
    }

    @Test("Doors use a hinge component instead of rotating around their centre")
    func doorsHaveUniversalHingeRuntime() throws {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)
        let door = try #require(built.interactableProps["office01.door.a"])
        let component = try #require(door.components[DoorComponent.self])

        #expect(component.hingeSide == .left)
        #expect(component.openAngleDegrees == 90)
        #expect(door.children.contains { $0.name == "door.hinge" })
    }

    @Test("A path between the two offices routes around the divider wall")
    func pathRoutesAroundWall() throws {
        HeistComponents.registerAll()
        let built = LevelSceneBuilder.build(.office01)

        let start = WorldPoint(x: 2.4, y: 0, z: 4.5)
        let goal = WorldPoint(x: 9.5, y: 0, z: 4.5)
        let path = try PathFinder.findPath(from: start, to: goal, in: built.navGrid).get()

        // Office A and office B are separated by a solid wall, so the route has
        // to detour through the corridor rather than cut across.
        #expect(path.length > 9.0, "length \(path.length)")
        #expect(path.waypoints.contains { $0.z > 6.4 })
    }

    @Test("Detection reports an event without stopping simulation")
    func detectionDoesNotPauseMission() throws {
        let session = GameSession()
        session.load(.office01)
        session.startClock()

        for _ in 0..<1_200 where session.detection == nil {
            session.tick(realTimeDelta: 1.0 / 120.0)
        }

        let detection = try #require(session.detection)
        let timeAtDetection = session.clock.elapsed
        #expect(session.clock.isRunning)
        #expect(session.stimuli.count == 1)
        #expect(session.alertState.level() >= .alerted)

        session.tick(realTimeDelta: 1.0)

        #expect(session.clock.isRunning)
        #expect(session.clock.elapsed > timeAtDetection)
        #expect(session.detection == detection)
    }

    @Test("Detection time is independent of render-frame cadence")
    func detectionUsesFixedSimulationSteps() throws {
        let fine = GameSession()
        fine.load(.office01)
        fine.startClock()
        for _ in 0..<1_200 where fine.detection == nil {
            fine.tick(realTimeDelta: 1.0 / 120.0)
        }

        let coarse = GameSession()
        coarse.load(.office01)
        coarse.startClock()
        for _ in 0..<300 where coarse.detection == nil {
            coarse.tick(realTimeDelta: 1.0 / 30.0)
        }

        let fineDetection = try #require(fine.detection)
        let coarseDetection = try #require(coarse.detection)
        #expect(fineDetection.missionTime == coarseDetection.missionTime)
        #expect(fineDetection.sourceID == coarseDetection.sourceID)
        #expect(fine.clock.isRunning)
        #expect(coarse.clock.isRunning)
    }

    @Test("Tapping searchable furniture starts its affordance, not a floor move")
    func furnitureTapIsSemantic() async throws {
        let session = GameSession()
        session.load(.office01)
        let desk = try #require(session.level?.root.findEntity(named: "office01.desk.a"))

        session.handleTap(at: .zero, entity: desk)

        let actor = try #require(session.selectedActorEntity)
        for _ in 0..<200 where actor.components[PendingInteractionComponent.self] == nil {
            await Task.yield()
        }
        let pending = try #require(actor.components[PendingInteractionComponent.self])
        #expect(pending.propID == "office01.desk.a")
        #expect(pending.interaction == .search)
    }

    @Test("Tapping non-interactive furniture never falls through to floor movement")
    func furnitureWithoutAffordanceStillConsumesTap() throws {
        let session = GameSession()
        session.load(.office01)
        let plant = try #require(session.level?.root.findEntity(named: "office01.plant.a"))

        session.handleTap(at: SIMD3<Float>(20, 0, 8), entity: plant)

        let actor = try #require(session.selectedActorEntity)
        #expect(actor.components[AgentNavigationComponent.self]?.task == nil)
        #expect(session.destination == nil)
        #expect(session.status == "No available action for office01.plant.a")
    }

    @Test("A patrolling guard with no active task still detours around a sudden obstacle")
    func patrollingGuardReactsToSuddenCube() async throws {
        // Companion to `guardReplansAroundSuddenCube`, which only ever
        // exercises a guard already mid-`AgentNavigationTask` (given an
        // `.investigate` goal first). Plain patrol — the guard's normal
        // state between authored waypoints, driven straight from
        // `GuardComponent.route` with no task at all — was invisible to
        // `replanAgentTasksIfNeeded` (it requires `navigation.task != nil`)
        // until `reactToObstaclesOnPatrolLegs` was added specifically to
        // cover it. This is the owner's own follow-up question, answered as
        // a test: "как сделать так, чтобы охранник... автоматически
        // рассчитал обход" when something appears on the leg to the next
        // authored node.
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let guardEntity = try #require(session.level?.actors[guardID])

        session.startClock()
        // Past the authored opening turn/pause, matching sibling tests.
        for _ in 0..<240 { session.tick(realTimeDelta: 1.0 / 60.0) }
        #expect(guardEntity.components[AgentNavigationComponent.self]?.task == nil)

        let guardComponent = try #require(guardEntity.components[GuardComponent.self])
        let phase = guardComponent.patrolTime(at: session.clock.elapsed)
        let anchor = try #require(guardComponent.route.nextAnchor(after: phase))
        // Two seconds ahead, comfortably short of the next authored node, so
        // the cube sits on the *current* leg rather than past its end.
        let cubeCenter = guardComponent.route.state(at: phase + 2.0).position

        let originalRevision = session.navigationWorld?.revision ?? 0
        session.placeDebugCube(center: cubeCenter, size: 0.9)
        // The obstacle overlay itself rebuilds on a detached worker (see
        // `guardReplansAroundSuddenCube`, the sibling test this mirrors) —
        // wait for it in real time, not by ticking. Ticking here would
        // advance mission time while the grid the cube belongs to does not
        // exist yet, walking the guard's phase straight past the point the
        // cube was aimed at before there was anything to react to.
        for _ in 0..<200 where session.navigationWorld?.revision == originalRevision {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(session.navigationWorld?.revision == originalRevision + 1)

        var statusLog: [String] = []
        // The guard deliberately keeps its authored patrol while the detached
        // worker plans. Wait for the atomic handoff to a real non-blocked task,
        // not merely for one render/simulation tick.
        for _ in 0..<200 where guardEntity.components[AgentNavigationComponent.self]?.task?.isBlocked != false {
            session.tick(realTimeDelta: 1.0 / 60.0)
            statusLog.append(
                "t=\(session.clock.elapsed) status=\(session.status) task=\(String(describing: guardEntity.components[AgentNavigationComponent.self]?.task))"
            )
            try await Task.sleep(for: .milliseconds(1))
        }

        let detouring = try #require(
            guardEntity.components[AgentNavigationComponent.self]?.task,
            "\(statusLog.joined(separator: "\n"))"
        )
        #expect(!detouring.isBlocked, "Guard never received a real detour path around the cube")
        if case .resumePatrol(_, let routeTime, let location) = detouring.goal {
            #expect(location.planarDistance(to: anchor.position) < 0.1)
            #expect(routeTime == anchor.routeTime)
        } else {
            Issue.record("Detour goal was \(detouring.goal), expected .resumePatrol to the next authored anchor")
        }

        let replannedGrid = try #require(session.navigationWorld?.grid)
        for (from, to) in zip(detouring.waypoints, detouring.waypoints.dropFirst()) {
            #expect(
                PathFinder.hasLineOfSight(from: from, to: to, in: replannedGrid),
                "Detour segment \(from) -> \(to) still crosses the new cube"
            )
        }

        // Unlike `guardReplansAroundSuddenCube`'s `.investigate` goal, this
        // detour's goal is `.resumePatrol`, so `completePatrolDetours` clears
        // the task to nil the instant a tick observes `.arrived` — there is
        // no tick where the task exists AND already reads `.arrived`. Break
        // on either signal instead of requiring the task to still be there.
        for _ in 0..<3_600 {
            guard let task = guardEntity.components[AgentNavigationComponent.self]?.task else { break }
            if task.state(at: session.clock.elapsed).activity == .arrived { break }
            session.tick(realTimeDelta: 1.0 / 60.0)
        }
        for _ in 0..<60 where guardEntity.components[GuardComponent.self]?.isPatrolPaused == true {
            session.tick(realTimeDelta: 1.0 / 60.0)
        }
        #expect(
            guardEntity.components[AgentNavigationComponent.self]?.task == nil,
            "Guard never resumed plain patrol after clearing the detour"
        )
        #expect(guardEntity.components[GuardComponent.self]?.isPatrolPaused == false)
    }

    @Test("A guard replans around a cube added after movement starts")
    func guardReplansAroundSuddenCube() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let original = try #require(guardEntity.components[GuardComponent.self])
        let goalPoint = try #require(original.route.waypoints.dropFirst().first)

        #expect(session.commandGuard(
            id: guardID,
            goal: .investigate(stimulusID: "test.noise", location: goalPoint)
        ))
        session.startClock()
        session.tick(realTimeDelta: 1.0)

        let movingComponent = try #require(guardEntity.components[AgentNavigationComponent.self])
        let moving = try #require(movingComponent.task)
        let positionBeforeCube = moving.state(at: session.clock.elapsed).position
        let cubeCenter = moving.state(at: session.clock.elapsed + 2.0).position
        let originalRevision = moving.worldRevision
        let submissionDuration = ContinuousClock().measure {
            session.placeDebugCube(center: cubeCenter, size: 0.9)
        }
        for _ in 0..<200 where session.navigationWorld?.revision == originalRevision {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(
            submissionDuration < .milliseconds(8),
            "Obstacle submission blocked the main actor for \(submissionDuration)"
        )
        #expect(session.navigationWorld?.revision == originalRevision + 1)

        // One fixed step notices the spatially relevant revision and submits a
        // worker plan. The old immutable route keeps moving until the atomic
        // response arrives; a world edit never performs path search on the
        // main actor and never exposes a synthetic stop.
        for _ in 0..<300 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            if guardEntity.components[AgentNavigationComponent.self]?.task?.worldRevision
                == originalRevision + 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let replannedComponent = try #require(guardEntity.components[AgentNavigationComponent.self])
        let replanned = try #require(replannedComponent.task)
        #expect(replanned.worldRevision == originalRevision + 1)
        #expect(replanned.goal == moving.goal)
        let liveAtHandoff = moving.state(at: replanned.startedAt).position
        #expect(replanned.waypoints.first?.planarDistance(to: liveAtHandoff) ?? 99 < 0.1)
        #expect(liveAtHandoff.planarDistance(to: positionBeforeCube) > 0.01)
        #expect(!replanned.isBlocked)

        _ = try #require(session.navigationWorld?.dynamicObstacles["debug.dynamic-cube"])
        let replannedGrid = try #require(session.navigationWorld?.grid)
        #expect(!replannedGrid.isWalkable(replannedGrid.cell(at: cubeCenter)))
        for (from, to) in zip(replanned.waypoints, replanned.waypoints.dropFirst()) {
            #expect(
                PathFinder.hasLineOfSight(from: from, to: to, in: replannedGrid),
                "Replanned segment \(from) -> \(to) intersects the cube or another blocker"
            )
        }

        // Repeatedly toggling the same blocker is not repeated information for
        // an already legal detour. Only the stale-response revision advances.
        let stableStartedAt = replanned.startedAt
        let stableWaypoints = replanned.waypoints
        var expectedRevision = replanned.worldRevision
        for _ in 0..<3 {
            session.removeDynamicObstacle(id: "debug.dynamic-cube")
            expectedRevision += 1
            for _ in 0..<300 where session.navigationWorld?.revision != expectedRevision {
                try await Task.sleep(for: .milliseconds(2))
            }
            session.tick(realTimeDelta: 1.0 / 60.0)

            session.placeDebugCube(center: cubeCenter, size: 0.9)
            expectedRevision += 1
            for _ in 0..<300 where session.navigationWorld?.revision != expectedRevision {
                try await Task.sleep(for: .milliseconds(2))
            }
            session.tick(realTimeDelta: 1.0 / 60.0)

            let stable = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            #expect(stable.startedAt == stableStartedAt)
            #expect(stable.waypoints == stableWaypoints)
            #expect(stable.worldRevision == expectedRevision)
        }

        for _ in 0..<3_600 {
            let component = try #require(guardEntity.components[AgentNavigationComponent.self])
            let task = try #require(component.task)
            if task.state(at: session.clock.elapsed).activity == .arrived { break }
            session.tick(realTimeDelta: 1.0 / 60.0)
        }

        let finishedComponent = try #require(guardEntity.components[AgentNavigationComponent.self])
        let finished = try #require(finishedComponent.task)
        let final = finished.state(at: session.clock.elapsed)
        #expect(final.activity == .arrived)
        #expect(final.position.planarDistance(to: goalPoint) < 0.1)
        #expect(session.clock.isRunning)
    }

    @Test("Rapid obstacle edits publish the complete latest overlay")
    func rapidObstacleEditsAreCoalescedWithoutLoss() async throws {
        let session = GameSession()
        session.load(.office01)
        let first = WorldBox(
            center: WorldPoint(x: 8, y: 0.5, z: 8),
            width: 0.8, height: 1, depth: 0.8,
            surface: .metal, sourceID: "rapid.first"
        )
        let second = WorldBox(
            center: WorldPoint(x: 10, y: 0.5, z: 8),
            width: 0.8, height: 1, depth: 0.8,
            surface: .metal, sourceID: "rapid.second"
        )

        session.setDynamicObstacle(id: "rapid.first", box: first, isVisible: false)
        session.setDynamicObstacle(id: "rapid.second", box: second, isVisible: false)
        session.removeDynamicObstacle(id: "rapid.first")

        for _ in 0..<300 where session.navigationWorld?.revision != 3 {
            try await Task.sleep(for: .milliseconds(5))
        }

        let world = try #require(session.navigationWorld)
        #expect(world.revision == 3)
        #expect(world.dynamicObstacles["rapid.first"] == nil)
        #expect(world.dynamicObstacles["rapid.second"] == second)
    }

    @Test("A guard makes one stable detour around a stationary thief")
    func guardAvoidsPlacedThief() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardEntity = try #require(session.level?.actors["office01.guard.01"])
        let thiefEntity = try #require(session.level?.actors["office01.thief.01"])
        let guardComponent = try #require(guardEntity.components[GuardComponent.self])
        let guardNavigation = try #require(guardEntity.components[AgentNavigationComponent.self])
        let thiefNavigation = try #require(thiefEntity.components[AgentNavigationComponent.self])

        session.startClock()
        // Get past the authored opening turn/pause and choose a point one second
        // ahead on the live patrol as the user's newly placed thief position.
        for _ in 0..<240 { session.tick(realTimeDelta: 1.0 / 60.0) }
        let guardPhase = guardComponent.patrolTime(at: session.clock.elapsed)
        let expectedNextAnchor = try #require(
            guardComponent.route.nextAnchor(after: guardPhase)
        )
        let guardStart = guardComponent.route.state(at: guardPhase).position
        let thiefPoint = guardComponent.route.state(at: guardPhase + 1.0).position
        #expect(session.placeActor(id: "office01.thief.01", at: thiefPoint))

        let travelX = thiefPoint.x - guardStart.x
        let travelZ = thiefPoint.z - guardStart.z
        let travelLength = max(0.001, hypot(travelX, travelZ))
        let forwardX = travelX / travelLength
        let forwardZ = travelZ / travelLength

        // Match the real tap workflow: a completed player move remains as an
        // arrived task until another command settles it. Avoidance must treat
        // that actor as stationary and must never move it on the guard's behalf.
        var placedThiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        placedThiefNavigation.task = AgentNavigationTask(
            goal: .move(destination: thiefPoint),
            start: thiefPoint,
            path: PathResult(waypoints: [thiefPoint], length: 0),
            startedAt: session.clock.elapsed - 1,
            speed: placedThiefNavigation.character.walkSpeed,
            initialFacing: placedThiefNavigation.restingFacing,
            worldRevision: session.navigationWorld?.revision ?? 0
        )
        thiefEntity.components[AgentNavigationComponent.self] = placedThiefNavigation
        #expect(
            placedThiefNavigation.task?.state(at: session.clock.elapsed).activity == .arrived
        )

        let minimumAllowed = guardNavigation.character.radius
            + thiefNavigation.character.radius
        var minimumObserved = Double.greatestFiniteMagnitude
        var minimumContext = ""
        var createdDetour = false
        var detourDestination: WorldPoint?
        var guardPassedBlocker = false
        var distinctPlanStarts: [Double] = []
        for step in 0..<1_200 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let navigation = try #require(
                guardEntity.components[AgentNavigationComponent.self]
            )
            let state: WorldPoint
            if let task = navigation.task {
                state = task.state(at: session.clock.elapsed).position
                if case .resumePatrol(_, _, let location) = task.goal {
                    createdDetour = true
                    detourDestination = detourDestination ?? location
                }
                if !task.isBlocked,
                   distinctPlanStarts.last.map({ abs($0 - task.startedAt) > 1e-9 }) ?? true {
                    distinctPlanStarts.append(task.startedAt)
                }
            } else {
                let patrol = try #require(guardEntity.components[GuardComponent.self])
                state = patrol.route.state(
                    at: patrol.patrolTime(at: session.clock.elapsed)
                ).position
            }
            let liveThiefNavigation = try #require(
                thiefEntity.components[AgentNavigationComponent.self]
            )
            let thiefState: WorldPoint
            if let task = liveThiefNavigation.task {
                thiefState = task.state(at: session.clock.elapsed).position
            } else {
                thiefState = liveThiefNavigation.restingPosition
            }
            let separation = state.planarDistance(to: thiefState)
            if separation < minimumObserved {
                minimumObserved = separation
                minimumContext = "step=\(step), guard=\(state), thief=\(thiefState), guardTask=\(String(describing: navigation.task)), thiefTask=\(String(describing: liveThiefNavigation.task)), status=\(session.status)"
            }
            let beyondBlocker = (state.x - thiefPoint.x) * forwardX
                + (state.z - thiefPoint.z) * forwardZ
            if createdDetour, beyondBlocker > 0.75 {
                guardPassedBlocker = true
            }
            if step.isMultiple(of: 10) {
                // Mission time is intentionally advanced much faster than wall
                // time in this test. Give the detached planner a bounded slice
                // so the test exercises its result instead of starving it.
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        #expect(createdDetour)
        #expect(
            detourDestination == expectedNextAnchor.position,
            "Guard rejoined an obsolete patrol segment instead of targeting the next authored node"
        )
        #expect(
            distinctPlanStarts.count <= 3,
            "One body encounter thrashed through \(distinctPlanStarts.count) plans: \(distinctPlanStarts)"
        )
        #expect(
            guardPassedBlocker,
            "Guard retained a route but never passed the stationary thief"
        )
        #expect(
            minimumObserved + 0.01 >= minimumAllowed,
            "Guard/thief capsules overlapped: \(minimumObserved) < \(minimumAllowed); \(minimumContext)"
        )
        let endingThief = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        let endingThiefTask = try #require(endingThief.task)
        #expect(endingThiefTask.goal == .move(destination: thiefPoint))
        #expect(endingThiefTask.state(at: session.clock.elapsed).activity == .arrived)
        #expect(
            endingThiefTask.state(at: session.clock.elapsed).position == thiefPoint,
            "Navigation moved the stationary thief instead of routing around it"
        )
        #expect(session.clock.isRunning)
    }

    @Test("An occupied patrol node is skipped instead of deadlocking the guard")
    func guardSkipsOccupiedPatrolNode() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let thiefID = "office01.thief.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let guardComponent = try #require(guardEntity.components[GuardComponent.self])
        let occupied = try #require(guardComponent.route.nextAnchor(after: 0))
        let following = try #require(
            guardComponent.route.nextAnchor(after: occupied.routeTime + 1e-6)
        )

        #expect(session.placeActor(id: thiefID, at: occupied.position))
        session.startClock()

        var selectedDestination: WorldPoint?
        var everBlocked = false
        for step in 0..<2_400 where selectedDestination == nil {
            session.tick(realTimeDelta: 1.0 / 60.0)
            if let task = guardEntity.components[AgentNavigationComponent.self]?.task {
                everBlocked = everBlocked || task.isBlocked
                if case .resumePatrol(_, _, let location) = task.goal {
                    selectedDestination = location
                }
            }
            if step.isMultiple(of: 10) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        #expect(selectedDestination == following.position)
        #expect(selectedDestination != occupied.position)
        #expect(!everBlocked, "The planner exposed its asynchronous wait as a blocked locomotion state")

        var movedPastOccupiedNode = false
        for step in 0..<2_400 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let state = session.level?.actors[guardID].map {
                if let task = $0.components[AgentNavigationComponent.self]?.task {
                    return task.state(at: session.clock.elapsed).position
                }
                let patrol = $0.components[GuardComponent.self]!
                return patrol.route.state(at: patrol.patrolTime(at: session.clock.elapsed)).position
            }
            if let state, state.planarDistance(to: following.position) < 0.35 {
                movedPastOccupiedNode = true
                break
            }
            if step.isMultiple(of: 10) { try await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(movedPastOccupiedNode)
        #expect(session.clock.isRunning)
    }

    @Test("A thief who crosses then stops on an active patrol becomes a stationary obstacle")
    func guardAvoidsThiefWhoStopsAfterCrossing() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let thiefID = "office01.thief.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let thiefEntity = try #require(session.level?.actors[thiefID])
        let grid = try #require(session.navigationWorld?.grid)

        session.startClock()
        for _ in 0..<240 { session.tick(realTimeDelta: 1.0 / 60.0) }
        let guardComponent = try #require(guardEntity.components[GuardComponent.self])
        let phase = guardComponent.patrolTime(at: session.clock.elapsed)
        let guardNow = guardComponent.route.state(at: phase).position
        let stopPoint = guardComponent.route.state(at: phase + 2.0).position
        let travel = (stopPoint - guardNow).normalized
        let side = WorldPoint(x: -travel.z, y: 0, z: travel.x)
        let candidates = [stopPoint + side * 0.9, stopPoint - side * 0.9]
        let thiefStart = try #require(candidates.first {
            grid.isWalkable(grid.cell(at: $0))
                && PathFinder.hasLineOfSight(from: $0, to: stopPoint, in: grid)
        })
        #expect(session.placeActor(id: thiefID, at: thiefStart))

        var thiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        thiefNavigation.task = AgentNavigationTask(
            goal: .move(destination: stopPoint),
            start: thiefStart,
            path: PathResult(
                waypoints: [stopPoint],
                length: thiefStart.planarDistance(to: stopPoint)
            ),
            startedAt: session.clock.elapsed,
            speed: thiefNavigation.character.walkSpeed,
            initialFacing: PatrolRoute.yaw(from: thiefStart, to: stopPoint),
            worldRevision: session.navigationWorld?.revision ?? 0,
            acceleration: .infinity,
            deceleration: .infinity,
            maximumTurnRateDegrees: .infinity
        )
        thiefEntity.components[AgentNavigationComponent.self] = thiefNavigation

        var thiefArrived = false
        var guardDetoured = false
        var guardPassed = false
        var minimumObserved = Double.greatestFiniteMagnitude
        let guardRadius = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        ).character.radius
        let thiefRadius = thiefNavigation.character.radius
        for _ in 0..<2_400 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let thiefTask = try #require(
                thiefEntity.components[AgentNavigationComponent.self]?.task
            )
            let thiefState = thiefTask.state(at: session.clock.elapsed)
            thiefArrived = thiefArrived || thiefState.activity == .arrived

            let guardNavigation = try #require(
                guardEntity.components[AgentNavigationComponent.self]
            )
            let guardState: WorldPoint
            if let task = guardNavigation.task {
                guardState = task.state(at: session.clock.elapsed).position
                if case .resumePatrol = task.goal { guardDetoured = true }
            } else {
                let patrol = try #require(guardEntity.components[GuardComponent.self])
                guardState = patrol.route.state(
                    at: patrol.patrolTime(at: session.clock.elapsed)
                ).position
            }
            minimumObserved = min(
                minimumObserved,
                guardState.planarDistance(to: thiefState.position)
            )
            let forwardProgress = (guardState.x - stopPoint.x) * travel.x
                + (guardState.z - stopPoint.z) * travel.z
            if thiefArrived, guardDetoured, forwardProgress > 0.65 {
                guardPassed = true
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(thiefArrived)
        #expect(guardDetoured)
        #expect(guardPassed)
        #expect(
            minimumObserved + 0.01 >= guardRadius + thiefRadius,
            "Guard crossed the thief after it became stationary: minimum=\(minimumObserved), status=\(session.status)"
        )
        let endingThief = try #require(
            thiefEntity.components[AgentNavigationComponent.self]?.task
        )
        #expect(endingThief.state(at: session.clock.elapsed).position == stopPoint)
        #expect(session.clock.isRunning)
    }

    @Test("A moving-crossing reservation is replaced when the thief stops in the guard corridor")
    func staleCrossingBecomesStationaryDetour() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let thiefID = "office01.thief.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let thiefEntity = try #require(session.level?.actors[thiefID])
        let guardStart = WorldPoint(x: 13.2, y: 0, z: 8)
        let guardGoal = WorldPoint(x: 10, y: 0, z: 8)
        let thiefStart = WorldPoint(x: 12, y: 0, z: 7)
        let crossingGoal = WorldPoint(x: 12, y: 0, z: 9)
        let stoppedOnPath = WorldPoint(x: 12, y: 0, z: 8)
        #expect(session.placeActor(id: guardID, at: guardStart, facing: 270))
        #expect(session.placeActor(id: thiefID, at: thiefStart, facing: 0))

        var guardNavigation = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        )
        var thiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        guardNavigation.task = AgentNavigationTask(
            goal: .move(destination: guardGoal),
            start: guardStart,
            path: PathResult(waypoints: [guardGoal], length: 3.2),
            startedAt: 0,
            speed: guardNavigation.character.walkSpeed,
            initialFacing: 270,
            worldRevision: 0
        )
        thiefNavigation.task = AgentNavigationTask(
            goal: .move(destination: crossingGoal),
            start: thiefStart,
            path: PathResult(waypoints: [crossingGoal], length: 2),
            startedAt: 0.01,
            speed: thiefNavigation.character.walkSpeed,
            initialFacing: 0,
            worldRevision: 0
        )
        guardEntity.components[AgentNavigationComponent.self] = guardNavigation
        thiefEntity.components[AgentNavigationComponent.self] = thiefNavigation
        session.startClock()

        // The first tick observes two colliding moving trajectories and opens
        // a crossing reservation with the older guard route as right of way.
        session.tick(realTimeDelta: 1.0 / 60.0)
        #expect(session.placeActor(id: thiefID, at: stoppedOnPath))

        var guardWasReplanned = false
        var guardPassed = false
        var minimumObserved = Double.greatestFiniteMagnitude
        let minimumAllowed = guardNavigation.character.radius
            + thiefNavigation.character.radius
        // The detour planner is deliberately detached from MainActor. Give it
        // wall-clock time while the deterministic mission clock advances;
        // otherwise a parallel/full-suite run can simulate tens of seconds
        // before the worker gets scheduled and turn this into a scheduler
        // benchmark instead of a navigation regression.
        for _ in 0..<600 where !guardWasReplanned {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let liveGuard = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            let guardState = liveGuard.state(at: session.clock.elapsed)
            let liveThief = try #require(
                thiefEntity.components[AgentNavigationComponent.self]
            )
            let thiefPosition = liveThief.task?.state(at: session.clock.elapsed).position
                ?? liveThief.restingPosition
            minimumObserved = min(
                minimumObserved,
                guardState.position.planarDistance(to: thiefPosition)
            )
            guardWasReplanned = guardWasReplanned || liveGuard.startedAt > 0.01
            try await Task.sleep(for: .milliseconds(2))
        }

        #expect(guardWasReplanned)

        for _ in 0..<2_400 where guardWasReplanned && !guardPassed {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let liveGuard = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            let guardState = liveGuard.state(at: session.clock.elapsed)
            let liveThief = try #require(
                thiefEntity.components[AgentNavigationComponent.self]
            )
            let thiefPosition = liveThief.task?.state(at: session.clock.elapsed).position
                ?? liveThief.restingPosition
            minimumObserved = min(
                minimumObserved,
                guardState.position.planarDistance(to: thiefPosition)
            )
            if guardState.position.x < stoppedOnPath.x - 0.65 {
                guardPassed = true
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(guardPassed)
        #expect(
            minimumObserved + 0.01 >= minimumAllowed,
            "Stale moving right-of-way let the guard cross a stopped thief: minimum=\(minimumObserved), status=\(session.status)"
        )
        let endingThief = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        #expect(endingThief.task == nil)
        #expect(endingThief.restingPosition == stoppedOnPath)
    }

    @Test("The debug ambush control lands the thief on the guard's live path and the guard still avoids it")
    func ambushControlPlacesThiefOnGuardPathAndGuardAvoidsIt() async throws {
        // Covers the debug panel's "Ambush with thief" button
        // (`GameSession.placeBlockerAheadOfAgent`), added so the owner's own
        // repro for "guard passes through my character" can be triggered
        // instantly and repeatedly instead of walking the thief into
        // position by hand each time. `guardAvoidsPlacedThief` above proves
        // the underlying avoidance in depth; this only proves the button's
        // own plumbing — landing the thief on the guard's live path, and
        // that the same safety net still holds the capsules apart from
        // there — without duplicating that whole scenario.
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let thiefID = "office01.thief.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let thiefEntity = try #require(session.level?.actors[thiefID])
        let guardNavigation = try #require(guardEntity.components[AgentNavigationComponent.self])
        let thiefNavigation = try #require(thiefEntity.components[AgentNavigationComponent.self])

        session.startClock()
        for _ in 0..<240 { session.tick(realTimeDelta: 1.0 / 60.0) }

        let guardComponent = try #require(guardEntity.components[GuardComponent.self])
        let phase = guardComponent.patrolTime(at: session.clock.elapsed)
        let expectedPoint = guardComponent.route.state(at: phase + 1.5).position

        #expect(session.placeBlockerAheadOfAgent(
            blockerID: thiefID, targetID: guardID, secondsAhead: 1.5
        ))
        let placedThiefPosition = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        ).restingPosition
        #expect(
            placedThiefPosition.planarDistance(to: expectedPoint) < 0.01,
            "Ambush landed the thief at \(placedThiefPosition), expected \(expectedPoint)"
        )

        let minimumAllowed = guardNavigation.character.radius + thiefNavigation.character.radius
        var minimumObserved = Double.greatestFiniteMagnitude
        for _ in 0..<600 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let guardState: WorldPoint
            if let task = guardEntity.components[AgentNavigationComponent.self]?.task {
                guardState = task.state(at: session.clock.elapsed).position
            } else {
                let patrol = try #require(guardEntity.components[GuardComponent.self])
                guardState = patrol.route.state(at: patrol.patrolTime(at: session.clock.elapsed)).position
            }
            let thiefState = try #require(
                thiefEntity.components[AgentNavigationComponent.self]
            ).restingPosition
            minimumObserved = min(minimumObserved, guardState.planarDistance(to: thiefState))
        }
        #expect(
            minimumObserved + 0.01 >= minimumAllowed,
            "Ambushed guard clipped the thief: \(minimumObserved) < \(minimumAllowed)"
        )
    }

    @Test("Rapid re-tapping across the guard's patrol never leaves capsules overlapping")
    func rapidRetapDoesNotLeaveStaleReservation() async throws {
        // Regression for the exact bug report: "когда я своим вором хожу и
        // перегораживаю ему по-разному путь... иногда охранник сквозь вора
        // проходит" — retargeting the thief with `requestMoveSelectedActor`
        // (the real tap path, not the synchronous test-only
        // `moveSelectedActor`) faster than each request's worker settles.
        // Before `invalidateBodyEncounterReservations` existed, a stale
        // `.crossingTrajectories` reservation from an earlier tap kept
        // governing a crossing the retap had already made obsolete, and its
        // frozen maneuvering/right-of-way roles never got re-decided against
        // the actual new geometry — this is what let a capsule overlap slip
        // through undetected.
        let session = GameSession()
        session.load(.office01)
        let guardEntity = try #require(session.level?.actors["office01.guard.01"])
        let thiefEntity = try #require(session.level?.actors["office01.thief.01"])
        let guardComponent = try #require(guardEntity.components[GuardComponent.self])
        let guardNavigation = try #require(guardEntity.components[AgentNavigationComponent.self])
        let thiefNavigation = try #require(thiefEntity.components[AgentNavigationComponent.self])
        let minimumAllowed = guardNavigation.character.radius + thiefNavigation.character.radius

        session.startClock()
        // Past the authored opening turn/pause, matching the sibling test.
        for _ in 0..<240 { session.tick(realTimeDelta: 1.0 / 60.0) }

        // Retap the thief across the guard's live corridor several times,
        // only a handful of fixed steps apart — far less than the several
        // milliseconds a detached `NavigationPlanner.resolve` normally takes
        // to answer, so most of these supersede a still-in-flight request.
        for offset in stride(from: 0.4, through: 2.2, by: 0.45) {
            let phase = guardComponent.patrolTime(at: session.clock.elapsed)
            let target = guardComponent.route.state(at: phase + offset).position
            session.requestMoveSelectedActor(to: SIMD3<Float>(
                Float(target.x), 0, Float(target.z)
            ))
            for _ in 0..<3 { session.tick(realTimeDelta: 1.0 / 60.0) }
        }

        var minimumObserved = Double.greatestFiniteMagnitude
        var minimumContext = ""
        for step in 0..<1_200 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let guardState: WorldPoint
            if let task = guardEntity.components[AgentNavigationComponent.self]?.task {
                guardState = task.state(at: session.clock.elapsed).position
            } else {
                let patrol = try #require(guardEntity.components[GuardComponent.self])
                guardState = patrol.route.state(at: patrol.patrolTime(at: session.clock.elapsed)).position
            }
            let thiefState: WorldPoint
            if let task = thiefEntity.components[AgentNavigationComponent.self]?.task {
                thiefState = task.state(at: session.clock.elapsed).position
            } else {
                thiefState = try #require(
                    thiefEntity.components[AgentNavigationComponent.self]
                ).restingPosition
            }
            let separation = guardState.planarDistance(to: thiefState)
            if separation < minimumObserved {
                minimumObserved = separation
                let guardNav = guardEntity.components[AgentNavigationComponent.self]
                let thiefNav = thiefEntity.components[AgentNavigationComponent.self]
                let guardPatrol = guardEntity.components[GuardComponent.self]
                minimumContext = """
                    step=\(step) t=\(session.clock.elapsed) guard=\(guardState) thief=\(thiefState) \
                    guardTask=\(String(describing: guardNav?.task)) \
                    guardPaused=\(String(describing: guardPatrol?.isPatrolPaused)) \
                    thiefTask=\(String(describing: thiefNav?.task)) \
                    status=\(session.status)
                    """
            }
            if step.isMultiple(of: 10) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        #expect(
            minimumObserved + 0.01 >= minimumAllowed,
            "Guard/thief capsules overlapped after rapid retapping: \(minimumObserved) < \(minimumAllowed); \(minimumContext)"
        )
    }

    @Test("A late moving crossing gets one atomic detour and preserves both goals")
    func movingActorsPredictCrossing() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardEntity = try #require(session.level?.actors["office01.guard.01"])
        let thiefEntity = try #require(session.level?.actors["office01.thief.01"])
        // These speeds put both capsule centres at the crossing within the
        // same time window. The former x=14 setup only crossed geometrically:
        // the thief had already passed long before the guard arrived.
        let guardStart = WorldPoint(x: 13, y: 0, z: 8)
        let guardGoal = WorldPoint(x: 10, y: 0, z: 8)
        let thiefStart = WorldPoint(x: 12, y: 0, z: 7)
        let thiefGoal = WorldPoint(x: 12, y: 0, z: 9.5)
        #expect(session.placeActor(id: "office01.guard.01", at: guardStart, facing: 270))
        #expect(session.placeActor(id: "office01.thief.01", at: thiefStart, facing: 0))

        var guardNavigation = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        )
        var thiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        guardNavigation.task = AgentNavigationTask(
            goal: .move(destination: guardGoal),
            start: guardStart,
            path: PathResult(waypoints: [guardGoal], length: 3),
            startedAt: 0,
            speed: guardNavigation.character.walkSpeed,
            initialFacing: 270,
            worldRevision: 0
        )
        thiefNavigation.task = AgentNavigationTask(
            goal: .move(destination: thiefGoal),
            start: thiefStart,
            path: PathResult(waypoints: [thiefGoal], length: 2.5),
            startedAt: 0,
            speed: thiefNavigation.character.walkSpeed,
            initialFacing: 0,
            worldRevision: 0
        )
        guardEntity.components[AgentNavigationComponent.self] = guardNavigation
        thiefEntity.components[AgentNavigationComponent.self] = thiefNavigation
        session.startClock()

        var minimumObserved = Double.greatestFiniteMagnitude
        var distinctThiefPaths: [[WorldPoint]] = []
        var crossingTrace: [String] = []
        var lastThiefStart: Double?
        for step in 0..<900 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let liveGuard = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            let liveThief = try #require(
                thiefEntity.components[AgentNavigationComponent.self]?.task
            )
            let guardState = liveGuard.state(at: session.clock.elapsed)
            let thiefState = liveThief.state(at: session.clock.elapsed)
            minimumObserved = min(
                minimumObserved,
                guardState.position.planarDistance(to: thiefState.position)
            )
            if !liveThief.isBlocked {
                if distinctThiefPaths.last != liveThief.waypoints {
                    distinctThiefPaths.append(liveThief.waypoints)
                }
            }
            if lastThiefStart != liveThief.startedAt {
                crossingTrace.append(
                    "t=\(session.clock.elapsed), status=\(session.status), guard=\(guardState), thief=\(thiefState), thiefStart=\(liveThief.startedAt), blocked=\(liveThief.isBlocked)"
                )
                lastThiefStart = liveThief.startedAt
            }
            if guardState.activity == .arrived, thiefState.activity == .arrived { break }
            if step.isMultiple(of: 10) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        let finalGuard = try #require(
            guardEntity.components[AgentNavigationComponent.self]?.task
        )
        let finalThief = try #require(
            thiefEntity.components[AgentNavigationComponent.self]?.task
        )
        #expect(finalGuard.startedAt == 0, "The guard surrendered its priority route")
        #expect(finalGuard.goal == .move(destination: guardGoal))
        #expect(finalGuard.state(at: session.clock.elapsed).activity == .arrived)
        #expect(finalThief.goal == .move(destination: thiefGoal))
        #expect(
            finalThief.state(at: session.clock.elapsed).activity == .arrived,
            "Thief did not finish predictive detour: \(crossingTrace)"
        )
        #expect(
            distinctThiefPaths.count == 2,
            "The lower-priority actor needs exactly one stable replacement arc, not a stop or repeated frame-by-frame replans: \(crossingTrace)"
        )
        #expect(
            minimumObserved + 0.01 >= guardNavigation.character.radius
                + thiefNavigation.character.radius,
            "Predictive crossing allowed actor capsules to overlap; minimum=\(minimumObserved), thiefPath=\(finalThief.waypoints), trace=\(crossingTrace)"
        )
    }

    @Test("Crossing safety is invariant across sub-second command timing")
    func crossingTimingMatrixNeverPenetrates() async throws {
        let offsets: [Double] = [-0.45, -0.2, -0.05, 0, 0.05, 0.2, 0.45]

        for offset in offsets {
            let session = GameSession()
            session.load(.office01)
            let guardEntity = try #require(session.level?.actors["office01.guard.01"])
            let thiefEntity = try #require(session.level?.actors["office01.thief.01"])
            let guardStart = WorldPoint(x: 13, y: 0, z: 8)
            let guardGoal = WorldPoint(x: 10, y: 0, z: 8)
            let thiefStart = WorldPoint(x: 12, y: 0, z: 7)
            let thiefGoal = WorldPoint(x: 12, y: 0, z: 9.5)
            #expect(session.placeActor(id: "office01.guard.01", at: guardStart, facing: 270))
            #expect(session.placeActor(id: "office01.thief.01", at: thiefStart, facing: 0))

            var guardNavigation = try #require(
                guardEntity.components[AgentNavigationComponent.self]
            )
            var thiefNavigation = try #require(
                thiefEntity.components[AgentNavigationComponent.self]
            )
            guardNavigation.task = AgentNavigationTask(
                goal: .move(destination: guardGoal),
                start: guardStart,
                path: PathResult(waypoints: [guardGoal], length: 3),
                startedAt: 0,
                speed: guardNavigation.character.walkSpeed,
                initialFacing: 270,
                worldRevision: 0
            )
            thiefNavigation.task = AgentNavigationTask(
                goal: .move(destination: thiefGoal),
                start: thiefStart,
                path: PathResult(waypoints: [thiefGoal], length: 2.5),
                startedAt: offset,
                speed: thiefNavigation.character.walkSpeed,
                initialFacing: 0,
                worldRevision: 0
            )
            guardEntity.components[AgentNavigationComponent.self] = guardNavigation
            thiefEntity.components[AgentNavigationComponent.self] = thiefNavigation
            session.startClock()

            let required = guardNavigation.character.radius
                + thiefNavigation.character.radius
            var minimum = Double.infinity
            for step in 0..<1_200 {
                session.tick(realTimeDelta: 1.0 / 60.0)
                let guardTask = try #require(
                    guardEntity.components[AgentNavigationComponent.self]?.task
                )
                let thiefTask = try #require(
                    thiefEntity.components[AgentNavigationComponent.self]?.task
                )
                minimum = min(
                    minimum,
                    guardTask.state(at: session.clock.elapsed).position.planarDistance(
                        to: thiefTask.state(at: session.clock.elapsed).position
                    )
                )
                if guardTask.state(at: session.clock.elapsed).activity == .arrived,
                   thiefTask.state(at: session.clock.elapsed).activity == .arrived {
                    break
                }
                if step.isMultiple(of: 10) { await Task.yield() }
            }

            let finalGuard = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            let finalThief = try #require(
                thiefEntity.components[AgentNavigationComponent.self]?.task
            )
            #expect(
                minimum + 0.005 >= required,
                "offset=\(offset) penetrated: \(minimum) < \(required)"
            )
            #expect(finalGuard.goal == .move(destination: guardGoal))
            #expect(finalThief.goal == .move(destination: thiefGoal))
            #expect(finalGuard.state(at: session.clock.elapsed).activity == .arrived)
            #expect(finalThief.state(at: session.clock.elapsed).activity == .arrived)
        }
    }

    @Test("A sealed doorway retains the guard goal without moving the thief")
    func doorwayBodyBecomesContactBlock() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let thiefEntity = try #require(session.level?.actors["office01.thief.01"])
        let guardNavigation = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        )
        let thiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        let doorEntity = try #require(
            session.level?.interactableProps["office01.door.store"]
        )
        var door = try #require(doorEntity.components[InteractableComponent.self])
        door.config["open"] = .bool(true)
        doorEntity.components[InteractableComponent.self] = door
        let doorway = WorldPoint(x: 18, y: 0, z: 6.55)
        let goal = WorldPoint(x: 18, y: 0, z: 4.5)
        #expect(session.placeActor(id: "office01.thief.01", at: doorway))

        #expect(session.commandGuard(
            id: guardID,
            goal: .investigate(stimulusID: "doorway.test", location: goal)
        ))
        session.startClock()

        var minimumObserved = Double.greatestFiniteMagnitude
        var guardBlocked = false
        for step in 0..<2_400 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let guardTask = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            let guardState = guardTask.state(at: session.clock.elapsed)
            let liveThief = try #require(
                thiefEntity.components[AgentNavigationComponent.self]
            )
            let thiefState: WorldPoint
            if let task = liveThief.task {
                thiefState = task.state(at: session.clock.elapsed).position
            } else {
                thiefState = liveThief.restingPosition
            }
            minimumObserved = min(
                minimumObserved,
                guardState.position.planarDistance(to: thiefState)
            )
            if guardTask.isBlocked {
                guardBlocked = true
                break
            }
            if step.isMultiple(of: 10) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        let minimumAllowed = guardNavigation.character.radius
            + thiefNavigation.character.radius
        let endingGuardTask = guardEntity.components[AgentNavigationComponent.self]?.task
        let endingGuardState = endingGuardTask?.state(at: session.clock.elapsed)
        let endingThief = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        #expect(
            guardBlocked,
            """
            Guard did not publish a safe contact block; status=\(session.status), \
            guardTask=\(String(describing: endingGuardTask)), \
            guardState=\(String(describing: endingGuardState))
            """
        )
        #expect(endingGuardTask?.goal == .investigate(
            stimulusID: "doorway.test", location: goal
        ))
        #expect(endingThief.task == nil)
        #expect(endingThief.restingPosition == doorway)
        #expect(minimumObserved + 0.01 >= minimumAllowed)
        #expect(session.clock.isRunning)
    }

    @Test("Opposing actors reserve a one-body doorway and both eventually pass")
    func opposingActorsSerializeThroughDoorway() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardEntity = try #require(session.level?.actors["office01.guard.01"])
        let thiefEntity = try #require(session.level?.actors["office01.thief.01"])
        let guardStart = WorldPoint(x: 18, y: 0, z: 4.5)
        let guardGoal = WorldPoint(x: 18, y: 0, z: 7.8)
        // The later actor waits in the corridor pocket rather than occupying
        // the doorway centre while the earlier route owns the portal.
        let thiefStart = WorldPoint(x: 18.8, y: 0, z: 7.8)
        let thiefGoal = WorldPoint(x: 18, y: 0, z: 4.5)
        #expect(session.placeActor(id: "office01.guard.01", at: guardStart, facing: 0))
        #expect(session.placeActor(id: "office01.thief.01", at: thiefStart, facing: 180))

        var guardNavigation = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        )
        var thiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        guardNavigation.task = AgentNavigationTask(
            goal: .move(destination: guardGoal),
            start: guardStart,
            path: PathResult(waypoints: [guardGoal], length: 3.3),
            startedAt: 0,
            speed: guardNavigation.character.walkSpeed,
            initialFacing: 0,
            worldRevision: 0
        )
        thiefNavigation.task = AgentNavigationTask(
            goal: .move(destination: thiefGoal),
            start: thiefStart,
            path: PathResult(waypoints: [WorldPoint(x: 18, y: 0, z: 7), thiefGoal], length: 3.7),
            startedAt: 0.1,
            speed: thiefNavigation.character.walkSpeed,
            initialFacing: 180,
            worldRevision: 0
        )
        guardEntity.components[AgentNavigationComponent.self] = guardNavigation
        thiefEntity.components[AgentNavigationComponent.self] = thiefNavigation
        session.startClock()

        let required = guardNavigation.character.radius
            + thiefNavigation.character.radius
        var minimum = Double.infinity
        for _ in 0..<1_800 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let guardTask = try #require(
                guardEntity.components[AgentNavigationComponent.self]?.task
            )
            let thiefTask = try #require(
                thiefEntity.components[AgentNavigationComponent.self]?.task
            )
            minimum = min(
                minimum,
                guardTask.state(at: session.clock.elapsed).position.planarDistance(
                    to: thiefTask.state(at: session.clock.elapsed).position
                )
            )
            if guardTask.state(at: session.clock.elapsed).activity == .arrived,
               thiefTask.state(at: session.clock.elapsed).activity == .arrived {
                break
            }
            // The production planner runs concurrently while real mission
            // time advances at wall-clock pace. This test deliberately fast-
            // forwards 30 seconds in a tight loop, so yield actual executor
            // time or a parallel full-suite run becomes a scheduler race.
            try await Task.sleep(for: .milliseconds(1))
        }

        let finalGuard = try #require(
            guardEntity.components[AgentNavigationComponent.self]?.task
        )
        let finalThief = try #require(
            thiefEntity.components[AgentNavigationComponent.self]?.task
        )
        #expect(minimum + 0.005 >= required)
        #expect(finalGuard.goal == .move(destination: guardGoal))
        #expect(finalThief.goal == .move(destination: thiefGoal))
        #expect(finalGuard.state(at: session.clock.elapsed).activity == .arrived)
        #expect(finalThief.state(at: session.clock.elapsed).activity == .arrived)
    }

    @Test("A guard inserts key, open and traversal for a locked door")
    func guardAutomaticallyTraversesLockedDoor() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let doorID = "office01.door.store"
        let guardEntity = try #require(session.level?.actors[guardID])
        let doorEntity = try #require(session.level?.interactableProps[doorID])
        let goal = WorldPoint(x: 18, y: 0, z: 4.5)

        #expect(session.commandGuard(
            id: guardID,
            goal: .investigate(stimulusID: "locked-door.test", location: goal)
        ))
        session.startClock()

        var observed = Set<InteractionKind>()
        var arrived = false
        for step in 0..<4_800 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            if let pending = guardEntity.components[PendingInteractionComponent.self] {
                observed.insert(pending.interaction)
            }
            if let active = guardEntity.components[ActiveInteractionComponent.self] {
                observed.insert(active.interaction)
            }
            if let task = guardEntity.components[AgentNavigationComponent.self]?.task,
               task.goal == .investigate(stimulusID: "locked-door.test", location: goal),
               task.state(at: session.clock.elapsed).activity == .arrived {
                arrived = true
                break
            }
            if step.isMultiple(of: 10) { await Task.yield() }
        }

        let doorState = try #require(doorEntity.components[InteractableComponent.self])
        #expect(observed.contains(.unlock))
        #expect(observed.contains(.open))
        #expect(!observed.contains(.lockpick))
        #expect(doorState.config["locked"]?.boolValue == false)
        #expect(doorState.config["open"]?.boolValue == true)
        #expect(arrived, "Guard did not resume the original semantic goal after opening the door")
    }

    @Test("GameplayKit steering is deterministic and cannot bypass hard body clearance")
    func gameplayKitSteeringIsDeterministic() throws {
        let grid = NavGrid(
            minX: -1, minZ: -2, cellSize: 0.1,
            columns: 60, rows: 40,
            walkable: [Bool](repeating: true, count: 2_400)
        )
        let start = WorldPoint(x: 0, y: 0, z: 0)
        let destination = WorldPoint(x: 4, y: 0, z: 0)
        let blocker = WorldPoint(x: 2, y: 0, z: 0)
        let character = CharacterProfile.standard
        let request = NavigationPlanRequest(
            id: 1,
            actorID: "guard",
            worldRevision: 0,
            start: start,
            destination: destination,
            character: character,
            topology: .grid(grid),
            startedAt: 5,
            initialFacing: 90,
            trajectoryCommittedAt: 5,
            avoidanceGrid: grid,
            reservedTrajectories: [
                ReservedAgentTrajectory(
                    actorID: "thief",
                    radius: character.radius,
                    committedAt: nil,
                    tieBreakerPriority: 50,
                    motion: .stationary(blocker)
                )
            ]
        )
        let straight = PathResult(waypoints: [destination], length: 4)

        let first = GameplayKitSteeringAdapter.refine(
            request: request, path: straight, grid: grid
        )
        let second = GameplayKitSteeringAdapter.refine(
            request: request, path: straight, grid: grid
        )
        #expect(first == second)
        if let path = first.path {
            #expect(path.waypoints.last == destination)
            #expect(path.waypoints.allSatisfy { grid.isWalkable(grid.cell(at: $0)) })
            let points = [start] + path.waypoints
            let minimum = zip(points, points.dropFirst()).map { from, to in
                Self.distance(blocker, toSegmentFrom: from, to: to)
            }.min() ?? 0
            #expect(minimum + 0.01 >= character.radius * 2 + 0.08)
        } else {
            // GKGoal is a soft steering preference, not a collision proof.
            // A deterministic rejection is therefore a valid optimization
            // miss; it must fall back to the hard-clearance core planner.
            #expect(first.rejection == .violatedBodyClearance)
        }

        let guarded = AppleNavigationPlanner.resolve(request)
        let guardedPath = try #require(try? guarded.result.get())
        #expect(guardedPath.waypoints.last == destination)
        let guardedPoints = [start] + guardedPath.waypoints
        let guardedMinimum = zip(guardedPoints, guardedPoints.dropFirst()).map { from, to in
            Self.distance(blocker, toSegmentFrom: from, to: to)
        }.min() ?? 0
        #expect(guardedMinimum + 0.01 >= character.radius * 2 + 0.08)
    }

    @Test("Removing and replacing a passed cube does not invalidate the remaining guard corridor")
    func passedCubeDoesNotReplanGuard() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let start = WorldPoint(x: 13.2, y: 0, z: 8)
        let destination = WorldPoint(x: 10, y: 0, z: 8)
        #expect(session.placeActor(id: guardID, at: start, facing: 270))
        var navigation = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        )
        navigation.task = AgentNavigationTask(
            goal: .investigate(stimulusID: "revision.scope", location: destination),
            start: start,
            path: PathResult(waypoints: [destination], length: 3.2),
            startedAt: 0,
            speed: navigation.character.walkSpeed,
            initialFacing: 270,
            worldRevision: session.navigationWorld?.revision ?? 0
        )
        guardEntity.components[AgentNavigationComponent.self] = navigation
        session.startClock()
        session.tick(realTimeDelta: 0.25)
        let original = try #require(guardEntity.components[AgentNavigationComponent.self]?.task)
        let cubeCenter = original.state(at: session.clock.elapsed + 0.8).position
        session.placeDebugCube(id: "revision.scope.cube", center: cubeCenter, size: 0.7)

        let firstRevision = original.worldRevision + 1
        for _ in 0..<300 where session.navigationWorld?.revision != firstRevision {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<300 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            if let task = guardEntity.components[AgentNavigationComponent.self]?.task,
               task.worldRevision == firstRevision,
               task.startedAt > original.startedAt { break }
            try await Task.sleep(for: .milliseconds(2))
        }

        // Advance until the cube no longer intersects any unconsumed link.
        var passedTask: AgentNavigationTask?
        for _ in 0..<2_400 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            guard let task = guardEntity.components[AgentNavigationComponent.self]?.task else { break }
            let remaining = task.remainingWaypoints(at: session.clock.elapsed)
            let stillAhead = zip(remaining, remaining.dropFirst()).contains { from, to in
                WorldSegmentIntersection.entryFraction(
                    from: from,
                    to: to,
                    box: WorldBox(
                        center: WorldPoint(x: cubeCenter.x, y: 0.45, z: cubeCenter.z),
                        width: 0.7, height: 0.7, depth: 0.7,
                        surface: .metal, sourceID: "revision.scope.cube"
                    ),
                    expansion: navigation.character.radius + 0.08
                ) != nil
            }
            if !stillAhead, task.state(at: session.clock.elapsed).activity != .arrived {
                passedTask = task
                break
            }
            if session.clock.elapsed.truncatingRemainder(dividingBy: 0.2) < 0.02 {
                await Task.yield()
            }
        }
        let beforeRemoval = try #require(passedTask)

        session.removeDynamicObstacle(id: "revision.scope.cube")
        let removalRevision = firstRevision + 1
        for _ in 0..<300 where session.navigationWorld?.revision != removalRevision {
            try await Task.sleep(for: .milliseconds(5))
        }
        session.tick(realTimeDelta: 1.0 / 60.0)
        let afterRemoval = try #require(guardEntity.components[AgentNavigationComponent.self]?.task)
        #expect(afterRemoval.startedAt == beforeRemoval.startedAt)
        #expect(afterRemoval.waypoints == beforeRemoval.waypoints)
        #expect(afterRemoval.worldRevision == removalRevision)

        session.placeDebugCube(id: "revision.scope.cube", center: cubeCenter, size: 0.7)
        let replacementRevision = removalRevision + 1
        for _ in 0..<300 where session.navigationWorld?.revision != replacementRevision {
            try await Task.sleep(for: .milliseconds(5))
        }
        session.tick(realTimeDelta: 1.0 / 60.0)
        let afterReplacement = try #require(guardEntity.components[AgentNavigationComponent.self]?.task)
        #expect(afterReplacement.startedAt == beforeRemoval.startedAt)
        #expect(afterReplacement.waypoints == beforeRemoval.waypoints)
        #expect(afterReplacement.worldRevision == replacementRevision)
    }

    @Test("Two obstacles and an actor in their gap invalidate the whole remaining corridor")
    func compoundBottleneckReplansWithoutBodyPenetration() async throws {
        let session = GameSession()
        session.load(.office01)
        let guardID = "office01.guard.01"
        let thiefID = "office01.thief.01"
        let guardEntity = try #require(session.level?.actors[guardID])
        let thiefEntity = try #require(session.level?.actors[thiefID])
        let guardStart = WorldPoint(x: 13, y: 0, z: 8)
        let guardGoal = WorldPoint(x: 10, y: 0, z: 8)
        let gap = WorldPoint(x: 11.5, y: 0, z: 8)

        #expect(session.placeActor(id: guardID, at: guardStart, facing: 270))
        #expect(session.placeActor(
            id: thiefID,
            at: WorldPoint(x: 14, y: 0, z: 8),
            facing: 270
        ))
        var guardNavigation = try #require(
            guardEntity.components[AgentNavigationComponent.self]
        )
        let thiefNavigation = try #require(
            thiefEntity.components[AgentNavigationComponent.self]
        )
        guardNavigation.task = AgentNavigationTask(
            goal: .move(destination: guardGoal),
            start: guardStart,
            path: PathResult(waypoints: [guardGoal], length: 3),
            startedAt: 0,
            speed: guardNavigation.character.walkSpeed,
            initialFacing: 270,
            worldRevision: session.navigationWorld?.revision ?? 0,
            acceleration: guardNavigation.character.acceleration,
            deceleration: guardNavigation.character.deceleration,
            maximumTurnRateDegrees: guardNavigation.character.maximumTurnRateDegrees
        )
        guardEntity.components[AgentNavigationComponent.self] = guardNavigation

        // The cubes leave a body-sized visual slit on the obsolete straight
        // route. With a person in that slit, the combined obstacle must be
        // treated as one closed corridor, not as three unrelated events.
        session.placeDebugCube(
            id: "bottleneck.north",
            center: WorldPoint(x: gap.x, y: 0, z: 7.35),
            size: 0.7
        )
        session.placeDebugCube(
            id: "bottleneck.south",
            center: WorldPoint(x: gap.x, y: 0, z: 8.65),
            size: 0.7
        )
        #expect(session.placeActor(id: thiefID, at: gap, facing: 270))
        for _ in 0..<400 where session.navigationWorld?.revision != 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(session.navigationWorld?.revision == 2)

        session.startClock()
        var minimumSeparation = Double.infinity
        var observedReplacement = false
        for step in 0..<1_200 {
            session.tick(realTimeDelta: 1.0 / 60.0)
            let guardTask = guardEntity.components[AgentNavigationComponent.self]?.task
            let guardPosition = guardTask?.state(at: session.clock.elapsed).position
                ?? guardEntity.components[AgentNavigationComponent.self]?.restingPosition
                ?? guardStart
            let thiefPosition = thiefEntity.components[AgentNavigationComponent.self]?.task?
                .state(at: session.clock.elapsed).position ?? gap
            minimumSeparation = min(
                minimumSeparation,
                guardPosition.planarDistance(to: thiefPosition)
            )
            if let guardTask,
               guardTask.startedAt > 0,
               guardTask.waypoints != [guardStart, guardGoal] {
                observedReplacement = true
            }
            if step.isMultiple(of: 8) { await Task.yield() }
        }

        let required = guardNavigation.character.radius
            + thiefNavigation.character.radius + 0.04
        #expect(
            minimumSeparation + 0.005 >= required,
            "Compound bottleneck allowed capsule penetration: \(minimumSeparation) < \(required)"
        )
        #expect(
            observedReplacement,
            "The guard kept its obsolete straight route after the cubes and body closed its corridor"
        )
    }

    private static func distance(
        _ point: WorldPoint,
        toSegmentFrom start: WorldPoint,
        to end: WorldPoint
    ) -> Double {
        let segment = end - start
        let lengthSquared = segment.x * segment.x + segment.z * segment.z
        guard lengthSquared > 1e-12 else { return point.planarDistance(to: start) }
        let relative = point - start
        let projection = max(0, min(1,
            (relative.x * segment.x + relative.z * segment.z) / lengthSquared
        ))
        return point.planarDistance(to: start + segment * projection)
    }

}
