import Foundation
import Observation
import OSLog
import RealityKit
import HeistCore

/// Runtime state for one loaded level: what is built, who is selected, and where
/// they were last told to go.
///
/// Kept deliberately small. Planning, security and objectives get their own
/// types later; this is the seam they will plug into, not a god object.
@MainActor
@Observable
public final class GameSession {
    private enum DoorRouteDecision {
        case clear
        case action(doorID: String, interaction: InteractionKind, approachSide: ApproachPointSolver.Side)
        case blocked(doorID: String)
    }
    private struct BodyReplanContext {
        enum Reason {
            case agentBody
            case navigationWorld
        }
        var requestID: UInt64
        var goal: AgentGoal
        var expectedTaskGoal: AgentGoal?
        var wasPlainPatrol: Bool
        var grid: NavGrid
        var reason: Reason
    }
    private struct BodyEncounterReservation {
        var decision: AgentEncounterDecision
        var createdAt: Double
        var validUntil: Double
        var rightOfWayAnchor: WorldPoint
        var suspendedTask: AgentNavigationTask?
        var suspendedAt: Double?
    }
    private let log = Logger(subsystem: "com.exrector.DerClou", category: "session")

    public private(set) var level: BuiltLevel?
    public private(set) var selectedActorID: String?
    /// Last resolved tap destination in world space, for the debug marker.
    public private(set) var destination: SIMD3<Float>?
    /// Short human-readable result of the last action, shown in the debug HUD.
    public private(set) var status: String = "No level loaded"
    /// The mission's authoritative time. Guards are posed from it, and failures
    /// are reported against it.
    public private(set) var clock = MissionClock()
    /// First deterministic sighting in the current attempt. A mission failure
    /// is data, not a transient HUD string, so replay/edit can inspect it.
    public private(set) var detection: DetectionEvent?
    /// Readable accumulated security state. Stimuli feed it; it never owns the
    /// mission clock or character transforms.
    public private(set) var alertState = AlertState()
    public private(set) var stimuli: [PerceptionStimulus] = []

    /// World region clear of system-reserved screen areas, for the current
    /// device and orientation.
    public private(set) var safeBounds: SafeGameplayBounds?
    /// Mission-critical objects currently sitting outside that region.
    public private(set) var placementIssues: [LevelIssue] = []

    @ObservationIgnored private var destinationMarker: Entity?
    @ObservationIgnored private var safeBoundsMarker: Entity?
    @ObservationIgnored public private(set) var navigationWorld: NavigationWorld?
    @ObservationIgnored private var dynamicObstacleEntities: [String: Entity] = [:]
    /// Authoritative requested overlay. It is separate from the last published
    /// navigation world because an expensive bake may still be in flight.
    @ObservationIgnored private var desiredDynamicObstacles: [String: WorldBox] = [:]
    @ObservationIgnored private var lastBlockedRetryBucket: [String: Int] = [:]
    @ObservationIgnored private var bodyEncounterReservations: [String: BodyEncounterReservation] = [:]
    @ObservationIgnored private var automaticDoorResumeGoals: [String: AgentGoal] = [:]
    @ObservationIgnored private var bodyReplanContexts: [String: BodyReplanContext] = [:]
    @ObservationIgnored private var nextNavigationRequestID: UInt64 = 0
    @ObservationIgnored private var latestNavigationRequestByActor: [String: UInt64] = [:]
    /// Actors whose current route was checked against committed moving
    /// trajectories before it was published.
    @ObservationIgnored private var timeAwareRouteActors: Set<String> = []
    @ObservationIgnored private var nextNavigationWorldMutationID: UInt64 = 0
    @ObservationIgnored private var nextNavigationWorldRevision: Int = 0
    /// Render frames feed this accumulator; gameplay only sees fixed 60 Hz
    /// mission steps. Never expose it to presentation as authoritative state.
    @ObservationIgnored private var simulationSteps = FixedStepAccumulator()

    public init() {}

    /// The entity to place in the RealityView.
    public var rootEntity: Entity? { level?.root }

    public var selectedActorEntity: Entity? {
        guard let selectedActorID else { return nil }
        return level?.actors[selectedActorID]
    }

    // MARK: - Loading

    public func load(_ blueprint: LevelBlueprint, catalog: PropCatalog = .standard) {
        HeistComponents.registerAll()

        let built = LevelSceneBuilder.build(blueprint, catalog: catalog)
        level = built
        navigationWorld = NavigationWorld(geometry: built.geometry, budget: built.build.budget)
        dynamicObstacleEntities = [:]
        desiredDynamicObstacles = [:]
        lastBlockedRetryBucket = [:]
        bodyEncounterReservations = [:]
        automaticDoorResumeGoals = [:]
        bodyReplanContexts = [:]
        nextNavigationRequestID = 0
        latestNavigationRequestByActor = [:]
        timeAwareRouteActors = []
        nextNavigationWorldMutationID = 0
        nextNavigationWorldRevision = 0
        detection = nil
        alertState = AlertState()
        stimuli = []

        for issue in built.issues {
            log.warning("\(issue.description, privacy: .public)")
        }

        let marker = GreyboxKit.destinationMarker()
        marker.isEnabled = false
        built.root.addChild(marker)
        destinationMarker = marker

        // Select the first playable actor so the level is usable on launch.
        selectedActorID = built.geometry.actors
            .first { $0.prototype.actorRole == .thief }?
            .id

        let walkableCells = built.navGrid.walkable.count { $0 }
        status = built.issues.hasErrors
            ? "Loaded \(blueprint.id) with \(built.issues.errors.count) blueprint errors"
            : "Loaded \(blueprint.id), \(walkableCells) walkable cells"
        log.info("\(self.status, privacy: .public)")
    }

    /// Bumped when the player asks to re-frame the whole level.
    public private(set) var cameraResetToken = 0

    /// Asks the view to drop pan and zoom and frame the level again.
    public func requestCameraReset() {
        cameraResetToken += 1
    }

    // MARK: - Mission time

    /// Advances mission time and poses every guard for the new moment.
    ///
    /// The only place render time touches gameplay: it converts frame delta into
    /// mission seconds and hands those to systems that are otherwise pure
    /// functions of time.
    public func tick(realTimeDelta: Double) {
        guard clock.isRunning else { return }
        simulationSteps.enqueue(realTimeDelta: realTimeDelta, rate: clock.rate)
        while let step = simulationSteps.popStep() {
            let previousTime = clock.elapsed
            clock.advance(byMissionTime: step)
            replanAgentTasksIfNeeded(at: clock.elapsed)
            reactToObstaclesOnPatrolLegs(at: clock.elapsed)
            completePatrolDetours(at: clock.elapsed)
            enforceHardBodySeparation(
                from: previousTime,
                to: clock.elapsed,
                stepDuration: step
            )
            resolveAgentBodyConflicts(at: clock.elapsed)
            poseSimulation(at: clock.elapsed)
            updateInteractions(at: clock.elapsed)
            evaluateGuardVision(at: clock.elapsed)
        }
    }

    public func startClock() {
        clock.start()
    }

    public func pauseClock() {
        clock.pause()
    }

    /// Deterministically places an actor for level authoring, debugging or a
    /// scripted setup. This is the only supported way to teleport a body: the
    /// simulation pose and RealityKit presentation are updated together.
    @discardableResult
    public func placeActor(id: String, at position: WorldPoint, facing: Double? = nil) -> Bool {
        guard let entity = level?.actors[id],
              currentNavigationGrid.isWalkable(currentNavigationGrid.cell(at: position)),
              var navigation = entity.components[AgentNavigationComponent.self] else { return false }
        let overlapsAnotherActor = level?.actors.contains { otherID, other in
            guard otherID != id,
                  let otherNavigation = other.components[AgentNavigationComponent.self]
            else { return false }
            let otherPosition = authoritativeState(for: other, at: clock.elapsed).position
            let minimum = navigation.character.radius + otherNavigation.character.radius + 0.02
            return position.planarDistance(to: otherPosition) < minimum
        } ?? false
        guard !overlapsAnotherActor else { return false }
        let resolvedFacing = facing ?? authoritativeState(for: entity, at: clock.elapsed).facing
        navigation.restingPosition = position
        navigation.restingFacing = resolvedFacing
        navigation.task = nil
        entity.components[AgentNavigationComponent.self] = navigation
        entity.position = SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z))
        entity.orientation = simd_quatf(
            angle: Float(resolvedFacing * .pi / 180),
            axis: SIMD3<Float>(0, 1, 0)
        )
        return true
    }

    /// Teleports `blockerID` onto `targetID`'s current path, `secondsAhead`
    /// seconds ahead of where `targetID` is right now.
    ///
    /// This is the debug-panel "ambush" control: the owner's own repro for
    /// the guard-walks-through-the-thief report has been manually walking
    /// the thief into the guard's path by hand, which only tests whatever
    /// timing that particular run happened to land on. This reuses the same
    /// live-position math `resolveAgentBodyConflicts` reads every tick
    /// (`authoritativeState`, which already knows how to read a plain
    /// patrol, a mid-task agent, or an idle actor) to put the blocker
    /// exactly on the target's near-future path on demand, so the same
    /// scenario can be triggered instantly and repeatedly from a button.
    @discardableResult
    public func placeBlockerAheadOfAgent(
        blockerID: String,
        targetID: String,
        secondsAhead: Double = 1.5
    ) -> Bool {
        guard let target = level?.actors[targetID] else { return false }
        let ahead = authoritativeState(for: target, at: clock.elapsed + secondsAhead)
        return placeActor(id: blockerID, at: ahead.position)
    }

    /// Rewinds the mission to its opening state.
    public func resetClock() {
        clock.reset()
        simulationSteps.reset()
        detection = nil
        alertState = AlertState()
        stimuli = []
        if let level {
            navigationWorld = NavigationWorld(geometry: level.geometry, budget: level.build.budget)
            for entity in dynamicObstacleEntities.values {
                entity.removeFromParent()
            }
            dynamicObstacleEntities = [:]
            desiredDynamicObstacles = [:]
            nextNavigationWorldMutationID = 0
            nextNavigationWorldRevision = 0
            lastBlockedRetryBucket = [:]
            bodyEncounterReservations = [:]
            automaticDoorResumeGoals = [:]
            bodyReplanContexts = [:]
            for (id, entity) in level.actors {
                guard var navigation = entity.components[AgentNavigationComponent.self] else { continue }
                navigation.task = nil
                navigation.missionTime = 0
                if let authored = level.geometry.actors.first(where: { $0.id == id }) {
                    navigation.restingPosition = WorldPoint(
                        x: authored.box.center.x, y: 0, z: authored.box.center.z
                    )
                    navigation.restingFacing = authored.box.yaw
                }
                entity.components[AgentNavigationComponent.self] = navigation
                if var guardComponent = entity.components[GuardComponent.self] {
                    guardComponent.patrolPhaseAtAnchor = 0
                    guardComponent.patrolAnchorMissionTime = 0
                    guardComponent.isPatrolPaused = false
                    entity.components[GuardComponent.self] = guardComponent
                }
            }
            for entity in level.interactableProps.values {
                guard var door = entity.components[DoorComponent.self] else { continue }
                door.settledFraction = door.initialFraction
                door.transition = nil
                door.missionTime = 0
                entity.components[DoorComponent.self] = door
            }
        }
        poseSimulation(at: 0)
    }

    private func poseSimulation(at time: Double) {
        guard let level else { return }
        for entity in level.actors.values {
            guard var component = entity.components[AgentNavigationComponent.self] else { continue }
            component.missionTime = time
            entity.components[AgentNavigationComponent.self] = component
        }
        var occluders = level.geometry.walls
        if let navigationWorld {
            occluders.append(contentsOf: navigationWorld.dynamicObstacles.values)
        }
        for entity in level.interactableProps.values {
            guard var door = entity.components[DoorComponent.self] else { continue }
            door.missionTime = time
            entity.components[DoorComponent.self] = door
            occluders.append(door.liveBox(at: time))
        }
        for entity in level.visionSources.values {
            guard var component = entity.components[VisionSourceComponent.self] else { continue }
            component.missionTime = time
            component.occluders = occluders
            entity.components[VisionSourceComponent.self] = component
        }
    }

    private func evaluateGuardVision(at missionTime: Double) {
        guard detection == nil, let level else { return }

        let targets = level.actors
            .filter { $0.value.components[PlayableActorComponent.self] != nil }
            .sorted { $0.key < $1.key }

        for sourceID in level.visionSources.keys.sorted() {
            guard let sourceEntity = level.visionSources[sourceID],
                  let source = sourceEntity.components[VisionSourceComponent.self],
                  source.isEnabled else { continue }

            let sourcePose: (position: WorldPoint, facing: Double)
            if sourceEntity.components[GuardComponent.self] != nil {
                let state = authoritativeState(for: sourceEntity, at: missionTime)
                sourcePose = (
                    WorldPoint(
                        x: state.position.x,
                        y: source.eyeHeight,
                        z: state.position.z
                    ),
                    state.facing
                )
            } else {
                sourcePose = (
                    WorldPoint(
                        x: Double(sourceEntity.position.x),
                        y: Double(sourceEntity.position.y),
                        z: Double(sourceEntity.position.z)
                    ),
                    VisionScan.facing(
                        baseDegrees: source.baseFacing,
                        arcDegrees: source.scanArc,
                        period: source.scanPeriod,
                        time: missionTime
                    )
                )
            }

            for (targetID, targetEntity) in targets {
                let targetEyeHeight = level.geometry.actors
                    .first(where: { $0.id == targetID })
                    .map { $0.prototype.height * 0.88 } ?? 1.5
                let target = WorldPoint(
                    x: Double(targetEntity.position.x),
                    y: targetEyeHeight,
                    z: Double(targetEntity.position.z)
                )
                let result = VisionSolver.evaluate(
                    observer: sourcePose.position,
                    facingDegrees: sourcePose.facing,
                    target: target,
                    config: source.config,
                    occluders: source.occluders
                )
                guard result.isVisible else { continue }

                detection = DetectionEvent(
                    sourceID: sourceID,
                    sourceKind: source.kind,
                    targetID: targetID,
                    missionTime: missionTime
                )
                let stimulus = PerceptionStimulus(
                    id: "vision.\(sourceID).\(targetID).\(String(format: "%.3f", missionTime))",
                    kind: source.kind == .securityCamera
                        ? .cameraVisualContact : .guardVisualContact,
                    sourceID: sourceID,
                    targetID: targetID,
                    location: target,
                    missionTime: missionTime,
                    intensity: 1
                )
                stimuli.append(stimulus)
                alertState.observe(stimulus)
                status = String(
                    format: "%@ spotted %@ at %.2f s",
                    sourceID, targetID, missionTime
                )
                log.info("\(self.status, privacy: .public)")
                return
            }
        }
    }

    // MARK: - Safe gameplay area

    /// Recomputes the safe region from the live safe-area insets.
    ///
    /// The world renders edge to edge, but anything the player must see, tap or
    /// reason about has to stay inside the system safe area. That region depends
    /// on the device and orientation, so it is checked here rather than in the
    /// blueprint. See docs/DEVELOPMENT_FINDINGS.md.
    public func updateSafeArea(
        viewportSize: (width: Double, height: Double),
        insets: ScreenInsets,
        projection: CameraProjection
    ) {
        guard let level else { return }

        guard let bounds = SafeAreaSolver.gameplayBounds(
            viewportSize: viewportSize,
            insets: insets,
            projection: projection
        ) else { return }

        guard bounds != safeBounds else { return }
        safeBounds = bounds

        placementIssues = SafeAreaSolver.placementIssues(
            for: level.blueprint,
            catalog: level.build.catalog,
            bounds: bounds
        )
        for issue in placementIssues {
            log.warning("\(issue.description, privacy: .public)")
        }

        updateSafeBoundsMarker(bounds)
    }

    /// Shows or hides the debug outline of the safe gameplay area.
    public func setSafeBoundsVisible(_ isVisible: Bool) {
        isSafeBoundsShown = isVisible
        safeBoundsMarker?.isEnabled = isVisible
    }

    public private(set) var isSafeBoundsShown = false

    private func updateSafeBoundsMarker(_ bounds: SafeGameplayBounds) {
        guard let root = level?.root else { return }

        safeBoundsMarker?.removeFromParent()
        let marker = GreyboxKit.boundsOutline(
            minX: Float(bounds.minX),
            maxX: Float(bounds.maxX),
            minZ: Float(bounds.minZ),
            maxZ: Float(bounds.maxZ)
        )
        marker.isEnabled = isSafeBoundsShown
        root.addChild(marker)
        safeBoundsMarker = marker
    }

    // MARK: - Input

    /// First entity the ray hits, ignoring pure scenery.
    ///
    /// Uses `Scene.raycast` rather than gesture targeting so hit resolution does
    /// not depend on RealityKit's input stack, which never reported hits for
    /// this orthographic non-AR scene.
    public func entity(along ray: WorldRay) -> Entity? {
        guard let scene = level?.root.scene else { return nil }

        let origin = SIMD3<Float>(
            Float(ray.origin.x),
            Float(ray.origin.y),
            Float(ray.origin.z)
        )
        let direction = SIMD3<Float>(
            Float(ray.direction.x),
            Float(ray.direction.y),
            Float(ray.direction.z)
        )

        let hits = scene.raycast(origin: origin, direction: direction, length: 500)
        // Nearest hit that means something to gameplay: a selectable actor or an
        // interactable prop. Walls and floors are just scenery for tap purposes.
        return hits
            .sorted { $0.distance < $1.distance }
            .first { hit in
                playableActorID(for: hit.entity) != nil
                    || interactableComponent(for: hit.entity) != nil
                    || tappablePropComponent(for: hit.entity) != nil
            }?
            .entity
    }

    /// Handles a tap that resolved to a world position, plus whatever entity was
    /// under the finger.
    public func handleTap(at worldPoint: SIMD3<Float>, entity: Entity?) {
        if let actorID = playableActorID(for: entity) {
            selectedActorID = actorID
            status = "Selected \(actorID)"
            return
        }

        if let interactable = interactableComponent(for: entity) {
            guard let verb = InteractionResolver.primaryInteraction(
                for: interactable.interactions, config: interactable.config
            ) else {
                status = "Nothing more to do with \(interactable.id)"
                return
            }
            requestInteraction(with: interactable.id, interaction: verb)
            return
        }


        // A prop hit is never reinterpreted as a floor destination. Objects
        // with no current affordance remain selectable/inspectable and may gain
        // one from level state later (a discovered drawer, key, safe, etc.).
        if let prop = tappablePropComponent(for: entity) {
            status = "No available action for \(prop.id)"
            return
        }

        requestMoveSelectedActor(to: worldPoint)
    }

    // MARK: - Interaction

    /// Routes the selected actor to `propID` and, once it arrives, starts
    /// `interaction` on it. Phase 3's whole "tap entity -> available
    /// contextual actions -> approach point -> actor walks there -> runs the
    /// interaction for its configured duration -> emits an event" loop, from
    /// the input side: `ApproachPointSolver` answers where to stand,
    /// `PathFinder` answers how to get there (identically to
    /// `moveSelectedActor`'s own plain-floor case — an interaction walk is
    /// not a different kind of walk), and `updateInteractions(at:)` below
    /// picks the thread back up once the walk itself finishes.
    ///
    /// Any interaction already in flight for this actor is dropped first: a
    /// new tap always supersedes whatever the actor was in the middle of,
    /// the same way `moveSelectedActor` already replaces an in-progress
    /// plain walk.
    public func beginInteraction(with propID: String, interaction: InteractionKind) {
        guard let actor = selectedActorEntity, let actorID = selectedActorID else {
            status = "No actor selected"
            return
        }
        guard let level else { return }
        guard let prop = level.geometry.props.first(where: { $0.id == propID }) else {
            log.error("beginInteraction: \(propID, privacy: .public) is not a known prop")
            return
        }

        actor.components.remove(PendingInteractionComponent.self)
        actor.components.remove(ActiveInteractionComponent.self)

        let actorState = authoritativeState(for: actor, at: clock.elapsed)
        let origin = actorState.position
        let actorGrid = navigationGrid(forAgent: actorID, at: clock.elapsed)

        let character = level.geometry.actors.first(where: { $0.id == actorID })?.character ?? .standard
        let routes: [(slot: ApproachPointSolver.Slot, path: PathResult)] =
            ApproachPointSolver.slots(for: prop.box, grid: actorGrid).compactMap { slot in
            guard case .success(let path) = PathFinder.findPath(
                from: origin,
                to: slot.position,
                in: actorGrid,
                character: character
            ) else { return nil }
            return (slot: slot, path: path)
        }
        guard let route = routes.min(by: { lhs, rhs in
            if abs(lhs.path.length - rhs.path.length) > 1e-9 {
                return lhs.path.length < rhs.path.length
            }
            return lhs.slot.side.rawValue < rhs.slot.side.rawValue
        }) else {
            if var navigation = actor.components[AgentNavigationComponent.self] {
                settleNavigationTask(&navigation, at: clock.elapsed)
                actor.components[AgentNavigationComponent.self] = navigation
            }
            status = "Nowhere to stand to reach \(propID)"
            log.debug("No approach point for \(propID, privacy: .public)")
            return
        }

        guard var navigation = actor.components[AgentNavigationComponent.self] else { return }
        navigation.task = makeNavigationTask(
            goal: .interact(objectID: propID, location: route.slot.position),
            start: origin,
            path: route.path,
            facing: authoritativeState(for: actor, at: clock.elapsed).facing,
            navigation: navigation,
            finalFacing: route.slot.facingDegrees,
            grid: actorGrid
        )
        actor.components[AgentNavigationComponent.self] = navigation
        actor.components.set(PendingInteractionComponent(
            propID: propID,
            interaction: interaction,
            arrivalFacingDegrees: route.slot.facingDegrees
        ))
        status = "\(actorID) -> approaching \(propID) to \(interaction.rawValue)"
        log.debug("""
            \(actorID, privacy: .public) approaching \(propID, privacy: .public) \
            to \(interaction.rawValue, privacy: .public), \(route.path.waypoints.count) legs
            """)
    }

    /// Nonblocking interactive counterpart to `beginInteraction`.
    public func requestInteraction(with propID: String, interaction: InteractionKind) {
        guard let actorID = selectedActorID else {
            status = "No actor selected"
            return
        }
        requestInteraction(
            actorID: actorID,
            with: propID,
            interaction: interaction,
            allowedSides: nil
        )
    }

    private func requestInteraction(
        actorID: String,
        with propID: String,
        interaction: InteractionKind,
        allowedSides: Set<ApproachPointSolver.Side>?
    ) {
        guard let actor = level?.actors[actorID],
              let level,
              let prop = level.geometry.props.first(where: { $0.id == propID }),
              let navigation = actor.components[AgentNavigationComponent.self] else {
            status = "Cannot plan that interaction"
            return
        }

        actor.components.remove(PendingInteractionComponent.self)
        actor.components.remove(ActiveInteractionComponent.self)
        let state = authoritativeState(for: actor, at: clock.elapsed)
        let topology = navigationTopology
        let revision = navigationWorld?.revision ?? 0

        nextNavigationRequestID &+= 1
        let requestID = nextNavigationRequestID
        latestNavigationRequestByActor[actorID] = requestID
        // Keep an existing locomotion task alive while the worker prepares the
        // approach. A semantic retarget is an atomic route handoff, not an
        // exposed stop between "tap" and "path ready".
        actor.components[AgentNavigationComponent.self] = navigation
        status = navigation.task == nil
            ? "Planning approach to \(propID)…"
            : "\(actorID) keeps moving while approach to \(propID) is planned…"

        let request = NavigationApproachPlanRequest(
            id: requestID,
            actorID: actorID,
            worldRevision: revision,
            start: state.position,
            objectBox: prop.box,
            character: navigation.character,
            topology: topology,
            allowedSides: allowedSides
        )
        let worker = Task.detached(priority: .userInitiated) {
            NavigationPlanner.resolveApproach(request)
        }
        Task { @MainActor [weak self] in
            let response = await worker.value
            self?.commitInteractiveApproach(
                response,
                propID: propID,
                interaction: interaction,
                allowedSides: allowedSides
            )
        }
    }

    /// Advances every actor's interaction state by one tick, in the same
    /// place and the same way `poseGuards(at:)` advances guards: a pure
    /// function of mission time, called only while the clock is running.
    ///
    /// Two independent transitions happen here, and only here:
    ///
    /// 1. **Pending -> active.** The shared navigation task reports `arrived`
    ///    from mission time; the session clears it and starts the interaction.
    /// 2. **Active -> complete.** An `ActiveInteractionComponent` whose
    ///    `duration` has elapsed since `startedAt` (measured in mission
    ///    seconds, never render time) applies its effect via
    ///    `InteractionResolver.applying(_:to:)` and clears.
    private func updateInteractions(at missionTime: Double) {
        guard let level else { return }

        for (actorID, actor) in level.actors {
            if let pending = actor.components[PendingInteractionComponent.self],
               var navigation = actor.components[AgentNavigationComponent.self],
               let task = navigation.task,
               task.state(at: missionTime).activity == .arrived {
                settleNavigationTask(&navigation, at: missionTime)
                actor.components[AgentNavigationComponent.self] = navigation
                actor.components.remove(PendingInteractionComponent.self)
                startActiveInteraction(pending, for: actor, actorID: actorID, missionTime: missionTime)
            }

            if let active = actor.components[ActiveInteractionComponent.self],
               active.isFinished(at: missionTime) {
                actor.components.remove(ActiveInteractionComponent.self)
                completeInteraction(active, actorID: actorID)
            }
        }
    }

    private func startActiveInteraction(
        _ pending: PendingInteractionComponent, for actor: Entity, actorID: String, missionTime: Double
    ) {
        guard let target = level?.interactableProps[pending.propID],
              let interactable = target.components[InteractableComponent.self] else { return }

        actor.orientation = simd_quatf(
            angle: Float(pending.arrivalFacingDegrees * .pi / 180),
            axis: SIMD3<Float>(0, 1, 0)
        )

        let duration = InteractionResolver.duration(for: pending.interaction, config: interactable.config)
        beginPresentation(
            for: pending.interaction,
            target: target,
            missionTime: missionTime,
            duration: duration
        )
        actor.components.set(ActiveInteractionComponent(
            propID: pending.propID, interaction: pending.interaction,
            startedAt: missionTime, duration: duration
        ))
        if var navigation = actor.components[AgentNavigationComponent.self] {
            navigation.isAnimating = false
            navigation.presentedActivity = nil
            navigation.walkLoopStartsAt = nil
            actor.components[AgentNavigationComponent.self] = navigation
        }
        status = "\(actorID) is \(pending.interaction.rawValue)ing \(pending.propID)"
        log.debug("""
            \(actorID, privacy: .public) started \(pending.interaction.rawValue, privacy: .public) \
            on \(pending.propID, privacy: .public), \(duration, privacy: .public) s
            """)
    }

    private func beginPresentation(
        for interaction: InteractionKind,
        target: Entity,
        missionTime: Double,
        duration: Double
    ) {
        if var door = target.components[DoorComponent.self] {
            let targetFraction: Double?
            switch interaction {
            case .open, .lockpick: targetFraction = 1
            case .close: targetFraction = 0
            default: targetFraction = nil
            }
            if let targetFraction {
                door.transition = DoorTransition(
                    startedAt: missionTime,
                    duration: duration,
                    fromFraction: door.openFraction(at: missionTime),
                    toFraction: targetFraction
                )
                target.components[DoorComponent.self] = door
            }
        }

    }

    private func completeInteraction(_ active: ActiveInteractionComponent, actorID: String) {
        guard let target = level?.interactableProps[active.propID],
              var interactable = target.components[InteractableComponent.self] else { return }

        interactable.config = InteractionResolver.applying(active.interaction, to: interactable.config)
        target.components[InteractableComponent.self] = interactable

        // Taking a standalone loot pickup (not a container's contents)
        // removes it from the scene — there is nothing left to look at.
        // A container that was looted stays: it is now just an empty crate.
        if active.interaction == .takeLoot,
           let prop = level?.geometry.props.first(where: { $0.id == active.propID }),
           prop.prototype.kind == .loot {
            target.isEnabled = false
        }

        status = "\(actorID) finished \(active.interaction.rawValue) on \(active.propID)"
        log.info("""
            \(actorID, privacy: .public) finished \(active.interaction.rawValue, privacy: .public) \
            on \(active.propID, privacy: .public)
            """)

        if let resume = automaticDoorResumeGoals.removeValue(forKey: actorID) {
            _ = commandGuard(id: actorID, goal: resume)
        }
    }

    /// Finds a route and starts walking the selected actor.
    ///
    /// Synchronous and deterministic: the same actor position and destination
    /// always yield the same path, which is what makes a recorded plan
    /// trustworthy.
    public func moveSelectedActor(to worldPoint: SIMD3<Float>) {
        guard let actor = selectedActorEntity, let actorID = selectedActorID else {
            status = "No actor selected"
            return
        }
        // A plain destination always supersedes whatever the actor was in
        // the middle of doing — the same rule `beginInteraction` applies in
        // the other direction.
        actor.components.remove(PendingInteractionComponent.self)
        actor.components.remove(ActiveInteractionComponent.self)

        let start = authoritativeState(for: actor, at: clock.elapsed).position
        let goal = WorldPoint(x: Double(worldPoint.x), y: 0, z: Double(worldPoint.z))
        let actorGrid = navigationGrid(forAgent: actorID, at: clock.elapsed)

        switch PathFinder.findPath(from: start, to: goal, in: actorGrid) {
        case .failure(let failure):
            if var navigation = actor.components[AgentNavigationComponent.self] {
                settleNavigationTask(&navigation, at: clock.elapsed)
                actor.components[AgentNavigationComponent.self] = navigation
            }
            destinationMarker?.isEnabled = false
            status = switch failure {
            case .startNotOnGrid: "\(actorID) is not standing anywhere walkable"
            case .destinationNotReachable: "Nowhere to stand there"
            case .noRoute: "No route to that point"
            }
            log.debug("Path failed for \(actorID, privacy: .public): \(failure.rawValue, privacy: .public)")

        case .success(let path):
            guard var navigation = actor.components[AgentNavigationComponent.self] else { return }
            invalidateBodyEncounterReservations(involving: actorID)
            navigation.task = makeNavigationTask(
                goal: .move(destination: goal),
                start: start,
                path: path,
                facing: authoritativeState(for: actor, at: clock.elapsed).facing,
                navigation: navigation,
                grid: actorGrid
            )
            actor.components[AgentNavigationComponent.self] = navigation

            // Mark where the actor will actually end up, not where the finger
            // landed — they differ when the tap lands on furniture or a wall.
            if let arrival = path.waypoints.last {
                let marker = SIMD3<Float>(Float(arrival.x), 0, Float(arrival.z))
                showDestinationMarker(at: marker)
                destination = marker
            }

            let speed = Double(actor.components[PlayableActorComponent.self]?.walkSpeed
                ?? Float(CharacterProfile.fallbackWalkSpeed))
            let eta = path.length / speed
            status = String(
                format: "%@ -> %.1f m, %d legs, ETA %.1f s",
                actorID,
                path.length,
                path.waypoints.count,
                eta
            )
            log.debug("""
                Path for \(actorID, privacy: .public): \
                \(path.waypoints.count) legs, \(path.length, privacy: .public) m
                """)
        }
    }

    /// Starts a path query without occupying the main/render actor.
    ///
    /// Taps are commands, not permission to rebuild or search navigation on the
    /// render thread. The immutable request is solved on a worker. Only the most
    /// recent response for an actor, against the current world revision, may be
    /// committed. The synchronous `moveSelectedActor` remains as a deterministic
    /// test/tooling entry point; interactive input must use this method.
    public func requestMoveSelectedActor(to worldPoint: SIMD3<Float>) {
        guard let actor = selectedActorEntity, let actorID = selectedActorID,
              let navigation = actor.components[AgentNavigationComponent.self] else {
            status = "No actor selected"
            return
        }

        actor.components.remove(PendingInteractionComponent.self)
        actor.components.remove(ActiveInteractionComponent.self)

        let state = authoritativeState(for: actor, at: clock.elapsed)
        let goal = WorldPoint(x: Double(worldPoint.x), y: 0, z: Double(worldPoint.z))
        let topology = navigationTopology
        let revision = navigationWorld?.revision ?? 0
        let commandTime = clock.elapsed
        let reservations = reservedTrajectories(
            excluding: actorID,
            from: commandTime
        )

        nextNavigationRequestID &+= 1
        let requestID = nextNavigationRequestID
        latestNavigationRequestByActor[actorID] = requestID
        // The current immutable trajectory remains authoritative until the
        // newest worker response is ready. Its reservations remain valid too;
        // they are replaced only at the atomic handoff below.
        actor.components[AgentNavigationComponent.self] = navigation
        status = navigation.task == nil
            ? "Planning route for \(actorID)…"
            : "\(actorID) keeps moving while the new route is planned…"

        let request = NavigationPlanRequest(
            id: requestID,
            actorID: actorID,
            worldRevision: revision,
            start: state.position,
            destination: goal,
            character: navigation.character,
            topology: topology,
            startedAt: commandTime,
            initialFacing: state.facing,
            trajectoryCommittedAt: commandTime,
            tieBreakerPriority: avoidancePriority(for: actor),
            avoidanceGrid: navigationWorld?.grid,
            reservedTrajectories: reservations
        )

        let worker = Task.detached(priority: .userInitiated) {
            NavigationPlanner.resolve(request)
        }
        Task { @MainActor [weak self] in
            let response = await worker.value
            self?.commitInteractiveNavigation(
                response,
                goal: goal
            )
        }
    }

    // MARK: - Autonomous navigation

    /// Gives a guard a semantic destination. The resulting path is disposable;
    /// the goal is not. Runtime obstacle changes replan from the guard's exact
    /// mission-time pose without involving RealityKit collision callbacks.
    @discardableResult
    public func commandGuard(id: String, goal: AgentGoal) -> Bool {
        guard let level,
              let entity = level.actors[id],
              entity.components[GuardComponent.self] != nil,
              var navigation = entity.components[AgentNavigationComponent.self],
              let destination = goal.navigationDestination,
              navigationWorld != nil else {
            status = "Cannot route guard \(id) to that goal"
            return false
        }

        let current = authoritativeState(for: entity, at: clock.elapsed)
        switch globalPath(
            from: current.position,
            to: destination,
            character: navigation.character
        ) {
        case .success(let path):
            switch automaticDoorDecision(
                actorID: id,
                start: current.position,
                path: path
            ) {
            case .action(let doorID, let interaction, let approachSide):
                automaticDoorResumeGoals[id] = goal
                requestInteraction(
                    actorID: id,
                    with: doorID,
                    interaction: interaction,
                    allowedSides: [approachSide]
                )
                status = "\(id) inserts \(interaction.rawValue) for \(doorID)"
                return true
            case .blocked(let doorID):
                navigation.task = .blocked(
                    goal: goal,
                    at: current.position,
                    facing: current.facing,
                    startedAt: clock.elapsed,
                    worldRevision: navigationWorld?.revision ?? 0
                )
                entity.components[AgentNavigationComponent.self] = navigation
                status = "\(id) cannot traverse locked door \(doorID)"
                return false
            case .clear:
                break
            }
            navigation.task = makeNavigationTask(
                goal: goal,
                start: current.position,
                path: path,
                facing: current.facing,
                navigation: navigation,
                grid: currentNavigationGrid
            )
            status = String(format: "%@ received goal, %.1f m", id, path.length)
        case .failure(let failure):
            navigation.task = .blocked(
                goal: goal,
                at: current.position,
                facing: current.facing,
                startedAt: clock.elapsed,
                worldRevision: navigationWorld?.revision ?? 0
            )
            status = "Guard \(id) retains blocked goal: \(failure.rawValue)"
        }
        entity.components[AgentNavigationComponent.self] = navigation
        return navigation.task?.isBlocked == false
    }

    /// Adds or moves a runtime blocker. This is the generic API used by doors,
    /// movable furniture and scripted hazards later; `placeDebugCube` below is
    /// merely a visible test fixture on top of it.
    public func setDynamicObstacle(id: String, box: WorldBox, isVisible: Bool = true) {
        guard let navigationWorld, let root = level?.root,
              desiredDynamicObstacles[id] != box else { return }

        desiredDynamicObstacles[id] = box
        nextNavigationWorldMutationID &+= 1
        let mutationID = nextNavigationWorldMutationID
        nextNavigationWorldRevision += 1
        let targetRevision = nextNavigationWorldRevision
        let requestedObstacles = desiredDynamicObstacles
        let geometry = navigationWorld.geometry
        let budget = navigationWorld.budget
        status = "Updating navigation for \(id)…"

        dynamicObstacleEntities[id]?.removeFromParent()
        if !isVisible {
            dynamicObstacleEntities.removeValue(forKey: id)
        } else {
            let entity = ModelEntity(
                mesh: .generateBox(
                    width: Float(box.width),
                    height: Float(box.height),
                    depth: Float(box.depth),
                    cornerRadius: 0.04
                ),
                materials: [GreyboxKit.flat(
                    PlatformColor(red: 0.96, green: 0.55, blue: 0.12, alpha: 1),
                    roughness: 0.65
                )]
            )
            entity.name = id
            entity.position = SIMD3<Float>(
                Float(box.center.x), Float(box.center.y), Float(box.center.z)
            )
            entity.orientation = simd_quatf(
                angle: Float(box.yaw * .pi / 180), axis: SIMD3<Float>(0, 1, 0)
            )
            entity.collision = CollisionComponent(shapes: [
                .generateBox(
                    width: Float(box.width),
                    height: Float(box.height),
                    depth: Float(box.depth)
                )
            ])
            GreyboxKit.castsShadow(entity)
            root.addChild(entity)
            dynamicObstacleEntities[id] = entity
        }

        let worker = Task.detached(priority: .utility) {
            NavigationWorld(
                geometry: geometry,
                budget: budget,
                dynamicObstacles: requestedObstacles,
                revision: targetRevision
            )
        }
        Task { @MainActor [weak self] in
            let candidate = await worker.value
            guard let self, self.nextNavigationWorldMutationID == mutationID else { return }
            self.navigationWorld = candidate
            self.status = "Navigation world revision \(candidate.revision): \(id) added"
        }
    }

    public func placeDebugCube(
        id: String = "debug.dynamic-cube",
        center: WorldPoint,
        size: Double = 0.9
    ) {
        setDynamicObstacle(
            id: id,
            box: WorldBox(
                center: WorldPoint(x: center.x, y: size / 2, z: center.z),
                width: size,
                height: size,
                depth: size,
                surface: .metal,
                sourceID: id
            )
        )
    }

    public func removeDynamicObstacle(id: String) {
        guard let navigationWorld, desiredDynamicObstacles.removeValue(forKey: id) != nil else { return }
        nextNavigationWorldMutationID &+= 1
        let mutationID = nextNavigationWorldMutationID
        nextNavigationWorldRevision += 1
        let targetRevision = nextNavigationWorldRevision
        let requestedObstacles = desiredDynamicObstacles
        let geometry = navigationWorld.geometry
        let budget = navigationWorld.budget
        dynamicObstacleEntities.removeValue(forKey: id)?.removeFromParent()
        status = "Updating navigation after removing \(id)…"
        let worker = Task.detached(priority: .utility) {
            NavigationWorld(
                geometry: geometry,
                budget: budget,
                dynamicObstacles: requestedObstacles,
                revision: targetRevision
            )
        }
        Task { @MainActor [weak self] in
            let candidate = await worker.value
            guard let self, self.nextNavigationWorldMutationID == mutationID else { return }
            self.navigationWorld = candidate
            self.status = "Navigation world revision \(candidate.revision): \(id) removed"
        }
    }

    private func replanAgentTasksIfNeeded(at missionTime: Double) {
        guard let level, let navigationWorld else { return }

        for id in level.actors.keys.sorted() {
            guard let entity = level.actors[id],
                  var navigation = entity.components[AgentNavigationComponent.self],
                  var oldTask = navigation.task,
                  oldTask.worldRevision != navigationWorld.revision else { continue }

            let remaining = oldTask.remainingWaypoints(at: missionTime)
            // Validate the actual committed corridor against the newly
            // published, body-eroded navigation field. Event count and object
            // history are irrelevant: if this detour already clears a cube,
            // removing and placing the same cube ten times remains a no-op for
            // the route.
            let routeWasInvalidated = oldTask.isBlocked || zip(
                remaining, remaining.dropFirst()
            ).contains { start, end in
                !PathFinder.hasLineOfSight(
                    from: start,
                    to: end,
                    in: navigationWorld.grid
                )
            }

            guard routeWasInvalidated else {
                // Revision is still acknowledged for stale-worker protection;
                // the path and its time origin remain byte-for-byte unchanged.
                oldTask.worldRevision = navigationWorld.revision
                navigation.task = oldTask
                entity.components[AgentNavigationComponent.self] = navigation
                continue
            }

            requestReplanForAgentBodies(
                id: id,
                at: missionTime,
                reason: .navigationWorld
            )
        }

    }

    /// The obstacle-reactivity counterpart to `replanAgentTasksIfNeeded`, for
    /// guards that function is structurally blind to.
    ///
    /// `replanAgentTasksIfNeeded` only ever looks at actors with an active
    /// `AgentNavigationTask` — a guard mid-patrol with nothing currently
    /// asked of it has none; `AgentLocomotionSystem` poses it straight from
    /// `GuardComponent.route`, a closed-form function of authored waypoints
    /// with no notion that `NavigationWorld` or its obstacle overlay exist
    /// at all. Before this, a crate dropped, a door left shut, or any future
    /// movable/interactive object placed directly across a guard's *current*
    /// leg — between the node it just left and the node it is walking
    /// toward — went completely unnoticed until the guard happened to reach
    /// the next authored node and some *other* system gave it a reason to
    /// plan again. This closes that gap the same way a placed obstacle
    /// already closes it for a guard already mid-task: one line-of-sight
    /// check from the guard's live position to its next authored node, at
    /// most a few tens of microseconds of work per guard per tick — the
    /// "nanoseconds" the owner asked for is not literal, but this is the
    /// same order of cost as everything else this loop already does every
    /// 1/60 s.
    ///
    /// Deliberately unconditional — an earlier version gated this on
    /// `NavigationWorld.revision` having changed since the guard's last
    /// check, to skip the work on ticks where nothing moved. That is wrong:
    /// the check only tells you the *current* leg is clear, and the guard
    /// is rarely on the leg the obstacle actually landed on the moment it
    /// appears. Once "checked" at that revision, a since-cleared revision
    /// gate never re-armed, so a guard walked straight through an obstacle
    /// it had already "seen" — from a leg the obstacle was not on — by the
    /// time it patrolled onto the leg the obstacle *was* on. A guard's own
    /// leg only has two states, obstructed or not, and checking it fresh
    /// every tick is cheap enough that the gate was never buying anything.
    ///
    /// Detouring reuses `requestReplanForAgentBodies`'s own guard branch
    /// (pause the authored patrol at its current phase, route to
    /// `PatrolRoute.nextAnchor(after:)`, resume patrol from that node on
    /// arrival via the already-existing `completePatrolDetours`) rather than
    /// inventing a second way to reroute a guard — a moved obstacle and a
    /// blocking actor are the same problem to a patrol: "the leg to the next
    /// authored node is not walkable right now."
    private func reactToObstaclesOnPatrolLegs(at missionTime: Double) {
        guard let level, let navigationWorld else { return }

        for id in level.actors.keys.sorted() {
            guard let entity = level.actors[id],
                  let navigation = entity.components[AgentNavigationComponent.self],
                  navigation.task == nil,
                  let guardComponent = entity.components[GuardComponent.self],
                  !guardComponent.isPatrolPaused else { continue }

            let phase = guardComponent.patrolTime(at: missionTime)
            guard let anchor = guardComponent.route.nextAnchor(after: phase) else { continue }
            let current = guardComponent.route.state(at: phase).position
            let sight = PathFinder.hasLineOfSight(
                from: current, to: anchor.position, in: navigationWorld.grid
            )
            guard !sight else { continue }

            requestReplanForAgentBodies(id: id, at: missionTime)
            status = "\(id) detours around a new obstacle on its current leg"
        }
    }

    /// A patrol detour ends on a known point of the patrol timeline. Resuming
    /// from that phase keeps the guard continuous instead of teleporting to
    /// wherever the global clock would have put the unpaused patrol.
    private func completePatrolDetours(at missionTime: Double) {
        guard let level else { return }
        for id in level.actors.keys.sorted() {
            guard let entity = level.actors[id],
                  var navigation = entity.components[AgentNavigationComponent.self],
                  let task = navigation.task,
                  task.state(at: missionTime).activity == .arrived,
                  case .resumePatrol(_, let routeTime, _) = task.goal,
                  var guardComponent = entity.components[GuardComponent.self] else { continue }
            settleNavigationTask(&navigation, at: missionTime)
            guardComponent.resumePatrol(at: missionTime, routeTime: routeTime)
            entity.components[AgentNavigationComponent.self] = navigation
            entity.components[GuardComponent.self] = guardComponent
            status = "\(id) resumed patrol after detour"
        }
    }

    /// Drops any encounter reservation involving `actorID` — called whenever
    /// that actor's committed trajectory is replaced (a new tap, mid-walk).
    ///
    /// `resolveAgentBodyConflicts` only opens a fresh reservation for a pair
    /// once its previous one has released, and release for a
    /// `.crossingTrajectories` reservation is gated on `missionTime >=
    /// validUntil` — a deadline computed from the *old* route's predicted
    /// closest approach. Without this, retargeting an actor (especially
    /// rapidly — the owner's own report: "когда я слишком часто и быстро
    /// маршрут выставляю") leaves a stale reservation governing a crossing
    /// that no longer happens, while blocking detection of the real one the
    /// new route creates, for as long as that stale deadline still has left
    /// to run. The safety-net loop keeps sampling live positions for the
    /// *frozen* maneuvering/right-of-way roles from the old decision, so it
    /// can clear a stale reservation as harmless without ever re-deciding
    /// who actually has to yield in the new situation — which is exactly
    /// the "guard walks through the thief" the owner saw. Any in-flight
    /// detour this actor was mid-executing because of a reservation is also
    /// abandoned: a superseding command already means the player no longer
    /// wants that detour honoured over the new destination.
    private func invalidateBodyEncounterReservations(involving actorID: String) {
        for (key, reservation) in bodyEncounterReservations {
            guard reservation.decision.maneuveringAgentID == actorID
                || reservation.decision.rightOfWayAgentID == actorID else { continue }
            bodyEncounterReservations.removeValue(forKey: key)
        }
    }

    /// Global destinations never change here. This layer predicts one local
    /// encounter window and submits at most one disposable detour for it.
    /// Stationary bodies are bypassed by the mover. When both move, the actor
    /// with lower right-of-way avoids the other's swept future corridor.
    private func resolveAgentBodyConflicts(at missionTime: Double) {
        guard let level else { return }
        let ids = level.actors.keys.sorted()
        // Sample the actors' exact mission-time trajectories. A single long
        // linear extrapolation is wrong around braking, curved turns and
        // patrol pauses; a short emergency-only horizon notices a narrow gate
        // too late. Exact bounded samples give both early notice and stable
        // decisions independent of a few milliseconds of command timing.
        let encounterHorizon = 2.5
        let stationaryProbeHorizon = 0.25

        // A crossing reservation describes two moving trajectories, not an
        // eternal right to walk through the other body. If either actor later
        // finishes its route and becomes stationary, discard that prediction
        // so this same tick can classify the pair as mover + obstacle and give
        // the mover a real detour. Do not reinterpret an actor that this very
        // reservation has deliberately emergency-held: its zero velocity is a
        // consequence of the reservation, not a changed player command.
        for key in bodyEncounterReservations.keys.sorted() {
            guard let reservation = bodyEncounterReservations[key],
                  reservation.decision.kind == .crossingTrajectories,
                  reservation.suspendedAt == nil,
                  let maneuver = level.actors[reservation.decision.maneuveringAgentID],
                  let priority = level.actors[reservation.decision.rightOfWayAgentID]
            else { continue }
            let maneuverNow = authoritativeState(for: maneuver, at: missionTime).position
            let priorityNow = authoritativeState(for: priority, at: missionTime).position
            let maneuverProbe = authoritativeState(
                for: maneuver, at: missionTime + stationaryProbeHorizon
            ).position
            let priorityProbe = authoritativeState(
                for: priority, at: missionTime + stationaryProbeHorizon
            ).position
            let maneuverMoves = maneuverNow.planarDistance(to: maneuverProbe) > 0.01
            let priorityMoves = priorityNow.planarDistance(to: priorityProbe) > 0.01
            if maneuverMoves != priorityMoves {
                bodyEncounterReservations.removeValue(forKey: key)
            }
        }

        // Safety net for an asynchronous detour: if a worker result arrives
        // too late or its rounded path still enters the reserved crossing
        // window, only the lower-priority actor is held at the last safe pose.
        // The guard never replans and the reservation is not recreated.
        //
        // Covers `.stationaryBlocker` too, not only `.crossingTrajectories`.
        // A tap-committed (`timeAwareRouteActors`) mover is deliberately never
        // sent a fresh detour request against a stationary blocker — the
        // comment at that call site is right that its own immutable plan
        // already accounted for every trajectory committed as of tap time.
        // What it did not account for is a blocker whose "stationary" pose
        // only exists *because this same tick loop paused it* — an authored
        // patrol dwell, or an emergency hold from an unrelated encounter —
        // which can put a guard somewhere the thief's plan never knew about.
        // Excluding `.stationaryBlocker` here left exactly that case with no
        // protection at all: confirmed by instrumenting a failing run of
        // "Rapid re-tapping across the guard's patrol never leaves capsules
        // overlapping" — at the moment of closest approach neither actor had
        // any hold on it (`guardTask=nil guardPaused=false`, thief mid-plan,
        // `isBlocked=false`), because the encounter had been decided
        // `.stationaryBlocker` and this loop skipped it outright. The
        // release logic below already branches correctly on both kinds; only
        // this filter was too narrow.
        for key in bodyEncounterReservations.keys.sorted() {
            guard var reservation = bodyEncounterReservations[key] else { continue }
            let maneuverID = reservation.decision.maneuveringAgentID
            let priorityID = reservation.decision.rightOfWayAgentID
            guard let maneuver = level.actors[maneuverID],
                  let priority = level.actors[priorityID],
                  var navigation = maneuver.components[AgentNavigationComponent.self],
                  let priorityNavigation = priority.components[AgentNavigationComponent.self] else { continue }
            // A maneuvering actor is not always mid-task: a patrolling guard
            // with nothing currently asked of it has no `AgentNavigationTask`
            // at all — `AgentLocomotionSystem` drives it straight from
            // `GuardComponent.route`, a closed-form function of time with no
            // idea this reservation, or any obstacle, exists. Requiring a
            // task here meant this whole safety net silently did nothing for
            // a patrolling guard — the exact "everything else is fine but a
            // plain patrolling guard walks straight through" the owner
            // reported. Both shapes hold the same way — the *maneuvering*
            // actor stops where it is — they just differ in what "stops" and
            // "already stopped" mean for each.
            if navigation.task?.isBlocked == true { continue }
            if navigation.task == nil,
               let guardComponent = maneuver.components[GuardComponent.self],
               guardComponent.isPatrolPaused { continue }

            // While the local detour is still being solved, reserve the whole
            // already-predicted encounter window. Waiting until the last
            // 0.45 s lets a yielding actor enter a one-body doorway and stop
            // inside it; the right-of-way actor then has nowhere to pass and
            // both deadlock. On open floor the worker atomically replaces the
            // hold with its arc. If no arc exists, this keeps the later actor
            // on the safe side of the bottleneck.
            let pendingDetour = bodyReplanContexts[maneuverID] != nil
            let safetyHorizon = pendingDetour
                ? max(0.45, min(encounterHorizon, reservation.validUntil - missionTime))
                : 0.45
            let maneuverNow = authoritativeState(for: maneuver, at: missionTime)
            let priorityNow = authoritativeState(for: priority, at: missionTime)
            let maneuverFuture = authoritativeState(
                for: maneuver, at: missionTime + safetyHorizon
            )
            let priorityFuture = authoritativeState(
                for: priority, at: missionTime + safetyHorizon
            )
            let predicted = AgentSeparation.minimumSweptDistance(
                firstStart: maneuverNow.position,
                firstEnd: maneuverFuture.position,
                secondStart: priorityNow.position,
                secondEnd: priorityFuture.position
            )
            let minimum = navigation.character.radius
                + priorityNavigation.character.radius + 0.08
            guard predicted < minimum else { continue }

            if let task = navigation.task {
                reservation.suspendedTask = task
                reservation.suspendedAt = missionTime
                navigation.task = .blocked(
                    goal: task.goal,
                    at: maneuverNow.position,
                    facing: maneuverNow.facing,
                    startedAt: missionTime,
                    worldRevision: navigationWorld?.revision ?? 0
                )
                maneuver.components[AgentNavigationComponent.self] = navigation
                bodyReplanContexts.removeValue(forKey: maneuverID)
            } else if var guardComponent = maneuver.components[GuardComponent.self] {
                guardComponent.pausePatrol(at: missionTime)
                maneuver.components[GuardComponent.self] = guardComponent
                reservation.suspendedAt = missionTime
            } else {
                continue
            }
            bodyEncounterReservations[key] = reservation
            status = "\(maneuverID) holds its predicted crossing for \(priorityID)"
        }

        // Release a reservation after its prediction window. A stationary
        // blocker that made the route impossible keeps the reservation until
        // it actually moves; this prevents blind retry loops in narrow doors.
        for (key, reservation) in bodyEncounterReservations {
            guard let rightOfWay = level.actors[reservation.decision.rightOfWayAgentID] else {
                bodyEncounterReservations.removeValue(forKey: key)
                continue
            }
            let currentAnchor = authoritativeState(for: rightOfWay, at: missionTime).position
            let blockerMoved = currentAnchor.planarDistance(to: reservation.rightOfWayAnchor) > 0.25
            let maneuverActor = level.actors[reservation.decision.maneuveringAgentID]
            let maneuverIsBlocked = maneuverActor?
                .components[AgentNavigationComponent.self]?.task?.isBlocked
                ?? maneuverActor?.components[GuardComponent.self]?.isPatrolPaused
                ?? false
            let maneuverPosition = level.actors[reservation.decision.maneuveringAgentID].map {
                authoritativeState(for: $0, at: missionTime).position
            }
            let currentDistance = maneuverPosition?.planarDistance(to: currentAnchor) ?? .infinity
            let releaseDistance = (level.actors[reservation.decision.maneuveringAgentID]?
                .components[AgentNavigationComponent.self]?.character.radius ?? 0.3)
                + (rightOfWay.components[AgentNavigationComponent.self]?.character.radius ?? 0.3)
                + 0.2
            let shouldRelease = switch reservation.decision.kind {
            case .stationaryBlocker:
                blockerMoved || (missionTime >= reservation.validUntil && !maneuverIsBlocked)
            case .crossingTrajectories:
                // Motion of the right-of-way actor is the reservation itself,
                // not evidence that the obstacle changed. Keep the predicted
                // crossing window intact until both have passed it.
                missionTime >= reservation.validUntil
                    && bodyReplanContexts[reservation.decision.maneuveringAgentID] == nil
                    && currentDistance > releaseDistance
            }
            if shouldRelease {
                if var suspended = reservation.suspendedTask,
                   let suspendedAt = reservation.suspendedAt,
                   let maneuver = level.actors[reservation.decision.maneuveringAgentID],
                   var navigation = maneuver.components[AgentNavigationComponent.self],
                   navigation.task?.isBlocked == true {
                    suspended.startedAt += missionTime - suspendedAt
                    navigation.task = suspended
                    maneuver.components[AgentNavigationComponent.self] = navigation
                } else if reservation.suspendedTask == nil,
                          let maneuver = level.actors[reservation.decision.maneuveringAgentID],
                          var guardComponent = maneuver.components[GuardComponent.self],
                          guardComponent.isPatrolPaused {
                    // A patrol pause has no task to restore — resume from
                    // exactly the phase it was paused at, so the wait costs
                    // the patrol nothing but the wait itself, same as a
                    // person actually stepping aside and continuing.
                    guardComponent.resumePatrol(
                        at: missionTime,
                        routeTime: guardComponent.patrolPhaseAtAnchor
                    )
                    maneuver.components[GuardComponent.self] = guardComponent
                }
                bodyEncounterReservations.removeValue(forKey: key)
            }
        }

        // Retry a generic blocked goal only when no encounter owns it. A body
        // reservation is released by time or movement, never four times a
        // second while the same actor is still in the same place.
        let retryBucket = Int((missionTime * 4).rounded(.down))
        for id in ids {
            let hasEncounter = bodyEncounterReservations.values.contains {
                $0.decision.maneuveringAgentID == id
            }
            guard !hasEncounter,
                  let entity = level.actors[id],
                  let task = entity.components[AgentNavigationComponent.self]?.task,
                  task.isBlocked,
                  bodyReplanContexts[id] == nil,
                  lastBlockedRetryBucket[id] != retryBucket else { continue }
            lastBlockedRetryBucket[id] = retryBucket
            requestReplanForAgentBodies(id: id, at: missionTime)
        }

        guard ids.count > 1 else { return }
        for leftIndex in 0..<(ids.count - 1) {
            for rightIndex in (leftIndex + 1)..<ids.count {
                let leftID = ids[leftIndex]
                let rightID = ids[rightIndex]
                let pairKey = "\(leftID)|\(rightID)"
                guard bodyEncounterReservations[pairKey] == nil,
                      let left = level.actors[leftID],
                      let right = level.actors[rightID],
                      let leftNavigation = left.components[AgentNavigationComponent.self],
                      let rightNavigation = right.components[AgentNavigationComponent.self] else { continue }

                let leftNow = authoritativeState(for: left, at: missionTime)
                let rightNow = authoritativeState(for: right, at: missionTime)
                guard let decision = predictedEncounter(
                    firstID: leftID,
                    first: left,
                    firstNavigation: leftNavigation,
                    secondID: rightID,
                    second: right,
                    secondNavigation: rightNavigation,
                    startingAt: missionTime,
                    horizon: encounterHorizon
                ) else { continue }

                let rightOfWayAnchor = decision.rightOfWayAgentID == leftID
                    ? leftNow.position : rightNow.position
                bodyEncounterReservations[pairKey] = BodyEncounterReservation(
                    decision: decision,
                    createdAt: missionTime,
                    validUntil: missionTime + max(
                        encounterHorizon,
                        decision.closestApproachTime + 0.75
                    ),
                    rightOfWayAnchor: rightOfWayAnchor,
                    suspendedTask: nil,
                    suspendedAt: nil
                )
                // Every newly observed conflict gets one stable replacement
                // attempt. A tap-time snapshot cannot know that a moving actor
                // will later stop in a newly narrowed gate. On open floor this
                // produces a smooth arc; where no alternate corridor exists,
                // the reservation holds the later actor outside the gate.
                requestReplanForAgentBodies(
                    id: decision.maneuveringAgentID,
                    avoiding: decision.rightOfWayAgentID,
                    predictionHorizon: encounterHorizon,
                    at: missionTime
                )
            }
        }
    }

    /// Exact piecewise prediction over authoritative task/patrol timelines.
    /// Sampling is deterministic mission time, not render cadence.
    private func predictedEncounter(
        firstID: String,
        first: Entity,
        firstNavigation: AgentNavigationComponent,
        secondID: String,
        second: Entity,
        secondNavigation: AgentNavigationComponent,
        startingAt missionTime: Double,
        horizon: Double,
        sampleInterval: Double = 0.15
    ) -> AgentEncounterDecision? {
        var elapsed = 0.0
        while elapsed < horizon - 1e-9 {
            let duration = min(sampleInterval, horizon - elapsed)
            let segmentStart = missionTime + elapsed
            let segmentEnd = segmentStart + duration
            let firstStart = authoritativeState(for: first, at: segmentStart).position
            let firstEnd = authoritativeState(for: first, at: segmentEnd).position
            let secondStart = authoritativeState(for: second, at: segmentStart).position
            let secondEnd = authoritativeState(for: second, at: segmentEnd).position
            if var decision = AgentEncounterPlanner.decide(
                first: AgentMotionIntent(
                    id: firstID,
                    position: firstStart,
                    futurePosition: firstEnd,
                    radius: firstNavigation.character.radius,
                    trajectoryCommittedAt: trajectoryCommitment(for: first),
                    avoidancePriority: avoidancePriority(for: first)
                ),
                second: AgentMotionIntent(
                    id: secondID,
                    position: secondStart,
                    futurePosition: secondEnd,
                    radius: secondNavigation.character.radius,
                    trajectoryCommittedAt: trajectoryCommitment(for: second),
                    avoidancePriority: avoidancePriority(for: second)
                ),
                horizon: duration
            ) {
                decision.closestApproachTime += elapsed
                return decision
            }
            elapsed += duration
        }
        return nil
    }

    /// Absolute safety invariant beneath pathfinding and steering. If an
    /// asynchronous plan or prediction ever arrives late, delay deterministic
    /// mission-time motion before presentation rather than allowing two swept
    /// capsules to exchange sides between fixed samples.
    private func enforceHardBodySeparation(
        from previousTime: Double,
        to missionTime: Double,
        stepDuration: Double
    ) {
        guard let level else { return }
        let ids = level.actors.keys.sorted()
        guard ids.count > 1 else { return }

        for leftIndex in 0..<(ids.count - 1) {
            for rightIndex in (leftIndex + 1)..<ids.count {
                let leftID = ids[leftIndex]
                let rightID = ids[rightIndex]
                guard let left = level.actors[leftID],
                      let right = level.actors[rightID],
                      let leftNavigation = left.components[AgentNavigationComponent.self],
                      let rightNavigation = right.components[AgentNavigationComponent.self]
                else { continue }
                let minimum = leftNavigation.character.radius
                    + rightNavigation.character.radius + 0.04
                let leftPrevious = authoritativeState(for: left, at: previousTime).position
                let leftDesired = authoritativeState(for: left, at: missionTime).position
                let rightPrevious = authoritativeState(for: right, at: previousTime).position
                let rightDesired = authoritativeState(for: right, at: missionTime).position
                let swept = AgentSeparation.minimumSweptDistance(
                    firstStart: leftPrevious,
                    firstEnd: leftDesired,
                    secondStart: rightPrevious,
                    secondEnd: rightDesired
                )
                guard swept < minimum else { continue }

                let pairKey = "\(leftID)|\(rightID)"
                let decision = bodyEncounterReservations[pairKey]?.decision
                    ?? AgentEncounterPlanner.decide(
                        first: AgentMotionIntent(
                            id: leftID,
                            position: leftPrevious,
                            futurePosition: leftDesired,
                            radius: leftNavigation.character.radius,
                            trajectoryCommittedAt: trajectoryCommitment(for: left),
                            avoidancePriority: avoidancePriority(for: left)
                        ),
                        second: AgentMotionIntent(
                            id: rightID,
                            position: rightPrevious,
                            futurePosition: rightDesired,
                            radius: rightNavigation.character.radius,
                            trajectoryCommittedAt: trajectoryCommitment(for: right),
                            avoidancePriority: avoidancePriority(for: right)
                        ),
                        horizon: stepDuration
                    )
                let yieldingID = decision?.maneuveringAgentID
                    ?? (avoidancePriority(for: left) <= avoidancePriority(for: right)
                        ? rightID : leftID)
                delayActorTimeline(id: yieldingID, by: stepDuration)

                let leftSafe = authoritativeState(for: left, at: missionTime).position
                let rightSafe = authoritativeState(for: right, at: missionTime).position
                let stillUnsafe = AgentSeparation.minimumSweptDistance(
                    firstStart: leftPrevious,
                    firstEnd: leftSafe,
                    secondStart: rightPrevious,
                    secondEnd: rightSafe
                ) < minimum
                if stillUnsafe {
                    delayActorTimeline(
                        id: yieldingID == leftID ? rightID : leftID,
                        by: stepDuration
                    )
                }
                status = "Body safety held \(yieldingID) before \(pairKey) could overlap"
            }
        }
    }

    private func delayActorTimeline(id: String, by duration: Double) {
        guard duration > 0,
              let actor = level?.actors[id],
              var navigation = actor.components[AgentNavigationComponent.self]
        else { return }
        if var task = navigation.task, !task.isBlocked {
            task.startedAt += duration
            navigation.task = task
            actor.components[AgentNavigationComponent.self] = navigation
        } else if var guardComponent = actor.components[GuardComponent.self],
                  !guardComponent.isPatrolPaused {
            guardComponent.patrolAnchorMissionTime += duration
            actor.components[GuardComponent.self] = guardComponent
        }
    }

    private func requestReplanForAgentBodies(
        id: String,
        avoiding rightOfWayID: String? = nil,
        predictionHorizon: Double = 0,
        at missionTime: Double,
        reason: BodyReplanContext.Reason = .agentBody
    ) {
        guard let level,
              let entity = level.actors[id],
              let navigation = entity.components[AgentNavigationComponent.self],
              bodyReplanContexts[id] == nil else { return }

        let current = authoritativeState(for: entity, at: missionTime)
        let goal: AgentGoal
        let expectedTaskGoal = navigation.task?.goal
        let wasPlainPatrol = navigation.task == nil
            && entity.components[GuardComponent.self] != nil
        if let existing = navigation.task,
           entity.components[GuardComponent.self] == nil {
            goal = existing.goal
        } else if let guardComponent = entity.components[GuardComponent.self],
                  navigation.task == nil || navigation.task?.goal.isPatrolResume == true {
            let currentPhase = guardComponent.patrolTime(at: missionTime)
            guard let anchor = nextAvailablePatrolAnchor(
                for: id,
                route: guardComponent.route,
                after: currentPhase,
                at: missionTime
            ) else { return }
            goal = .resumePatrol(
                routeID: id,
                routeTime: anchor.routeTime,
                location: anchor.position
            )
        } else if let existing = navigation.task {
            goal = existing.goal
        } else {
            return
        }
        guard let destination = goal.navigationDestination else { return }

        let grid = navigationGrid(
            forAgent: id,
            at: missionTime,
            sweptAgentID: rightOfWayID,
            sweepHorizon: predictionHorizon
        )
        nextNavigationRequestID &+= 1
        let requestID = nextNavigationRequestID
        latestNavigationRequestByActor[id] = requestID
        bodyReplanContexts[id] = BodyReplanContext(
            requestID: requestID,
            goal: goal,
            expectedTaskGoal: expectedTaskGoal,
            wasPlainPatrol: wasPlainPatrol,
            grid: grid,
            reason: reason
        )
        status = reason == .navigationWorld
            ? "\(id) keeps moving while its affected corridor is replanned"
            : "\(id) keeps moving while its body-avoidance route is prepared"

        let request = NavigationPlanRequest(
            id: requestID,
            actorID: id,
            worldRevision: navigationWorld?.revision ?? 0,
            start: current.position,
            destination: destination,
            character: navigation.character,
            topology: .grid(grid),
            startedAt: missionTime,
            initialFacing: current.facing,
            avoidanceGrid: grid
        )
        let worker = Task.detached(priority: .userInitiated) {
            NavigationPlanner.resolve(request)
        }
        Task { @MainActor [weak self] in
            let response = await worker.value
            self?.commitBodyReplan(response)
        }
    }

    private func commitBodyReplan(_ response: NavigationPlanResponse) {
        guard let context = bodyReplanContexts[response.actorID],
              context.requestID == response.requestID else { return }
        bodyReplanContexts.removeValue(forKey: response.actorID)
        guard latestNavigationRequestByActor[response.actorID] == response.requestID,
              response.worldRevision == (navigationWorld?.revision ?? 0),
              let actor = level?.actors[response.actorID],
              var navigation = actor.components[AgentNavigationComponent.self] else { return }
        if let expectedTaskGoal = context.expectedTaskGoal {
            guard navigation.task?.goal == expectedTaskGoal else { return }
        } else {
            guard navigation.task == nil,
                  actor.components[GuardComponent.self] != nil else { return }
        }
        let live = authoritativeState(for: actor, at: clock.elapsed)
        let liveSpeed = authoritativeSpeed(for: actor, at: clock.elapsed)
        switch response.result {
        case .success(let path):
            let minimalPath = PathFinder.minimumLinkPath(
                from: live.position,
                path: path,
                in: context.grid
            )
            if context.wasPlainPatrol,
               var guardComponent = actor.components[GuardComponent.self] {
                guardComponent.pausePatrol(at: clock.elapsed)
                actor.components[GuardComponent.self] = guardComponent
            }
            navigation.task = makeNavigationTask(
                goal: context.goal,
                start: live.position,
                path: minimalPath,
                facing: live.facing,
                navigation: navigation,
                startedAt: clock.elapsed,
                initialSpeed: liveSpeed,
                grid: context.grid
            )
            status = "\(response.actorID) received a minimal-link route to its next node"
        case .failure(let failure):
            if context.reason == .navigationWorld {
                navigation.task = .blocked(
                    goal: context.goal,
                    at: live.position,
                    facing: live.facing,
                    startedAt: clock.elapsed,
                    worldRevision: navigationWorld?.revision ?? 0
                )
                status = "\(response.actorID) keeps goal but its corridor is blocked: \(failure.rawValue)"
            } else {
                // Keep the old immutable trajectory. The encounter
                // reservation's last-safe-pose brake remains the fail-safe if
                // the two bodies get close before a later retry finds a route.
                status = "\(response.actorID) keeps its route; no legal detour was found"
            }
        }
        actor.components[AgentNavigationComponent.self] = navigation
    }

    /// Patrol nodes are temporal anchors, not mandatory parking spots. If a
    /// stationary actor occupies one, advance monotonically to the following
    /// authored node instead of creating an impossible goal and deadlocking
    /// the patrol state.
    private func nextAvailablePatrolAnchor(
        for guardID: String,
        route: PatrolRoute,
        after phase: Double,
        at missionTime: Double
    ) -> PatrolRoute.Anchor? {
        guard let level,
              let guardEntity = level.actors[guardID],
              let guardNavigation = guardEntity.components[AgentNavigationComponent.self]
        else { return route.nextAnchor(after: phase) }

        var cursor = phase
        for _ in 0..<route.waypoints.count {
            guard let anchor = route.nextAnchor(after: cursor) else { return nil }
            let occupied = level.actors.contains { otherID, otherEntity in
                guard otherID != guardID,
                      let otherNavigation = otherEntity.components[AgentNavigationComponent.self]
                else { return false }
                let now = authoritativeState(for: otherEntity, at: missionTime).position
                let probe = authoritativeState(for: otherEntity, at: missionTime + 0.25).position
                let isStationary = now.planarDistance(to: probe) <= 0.01
                let clearance = guardNavigation.character.radius
                    + otherNavigation.character.radius + 0.12
                return isStationary && now.planarDistance(to: anchor.position) < clearance
            }
            if !occupied { return anchor }
            cursor = anchor.routeTime + 1e-6
        }
        return nil
    }

    // MARK: - Helpers

    private func automaticDoorDecision(
        actorID: String,
        start: WorldPoint,
        path: PathResult
    ) -> DoorRouteDecision {
        guard let level else { return .clear }
        let closedDoors: [DoorTraversalGate] = level.geometry.props.compactMap { prop in
            guard prop.prototype.mechanic == .hingedDoor,
                  let entity = level.interactableProps[prop.id],
                  let interactable = entity.components[InteractableComponent.self],
                  interactable.config["open"]?.boolValue != true else { return nil }
            return DoorTraversalGate(id: prop.id, box: prop.box)
        }
        guard let crossing = DoorTraversalPlanner.firstCrossing(
            path: path,
            gates: closedDoors
        ), let entity = level.interactableProps[crossing.gate.id],
           let interactable = entity.components[InteractableComponent.self] else { return .clear }

        let fromSide = crossing.approachSide == .front ? "a" : "b"
        let toSide = fromSide == "a" ? "b" : "a"
        var actorFacts = Set<PlanningFact>()
        if level.actors[actorID]?.components[GuardComponent.self] != nil {
            actorFacts.insert(PlanningFact("actor.can.unlock"))
        } else {
            actorFacts.insert(PlanningFact("actor.can.lockpick"))
        }
        let initial = DoorAffordanceFactory.facts(
            doorID: crossing.gate.id,
            isOpen: false,
            isLocked: interactable.config["locked"]?.boolValue ?? false,
            actorSide: fromSide,
            actorFacts: actorFacts
        )
        let goal: Set<PlanningFact> = [
            PlanningFact("actor.at.\(crossing.gate.id).\(toSide)")
        ]
        guard case .success(let plan) = AffordancePlanner.plan(
            initial: initial,
            goal: goal,
            actions: DoorAffordanceFactory.actions(doorID: crossing.gate.id)
        ) else { return .blocked(doorID: crossing.gate.id) }
        guard let firstInteraction = plan.actions.compactMap({ action -> InteractionKind? in
            if case .interact(_, let kind) = action.semantic { return kind }
            return nil
        }).first else { return .blocked(doorID: crossing.gate.id) }
        return .action(
            doorID: crossing.gate.id,
            interaction: firstInteraction,
            approachSide: crossing.approachSide
        )
    }

    private func commitInteractiveNavigation(
        _ response: NavigationPlanResponse,
        goal: WorldPoint
    ) {
        guard latestNavigationRequestByActor[response.actorID] == response.requestID else {
            return
        }
        guard response.worldRevision == (navigationWorld?.revision ?? 0) else {
            status = "World changed; replanning \(response.actorID)"
            if selectedActorID == response.actorID {
                requestMoveSelectedActor(to: SIMD3<Float>(Float(goal.x), 0, Float(goal.z)))
            }
            return
        }
        guard let actor = level?.actors[response.actorID],
              var navigation = actor.components[AgentNavigationComponent.self] else { return }

        switch response.result {
        case .failure(let failure):
            // A rejected retarget does not destroy the still-valid route the
            // actor was already executing.
            actor.components[AgentNavigationComponent.self] = navigation
            destinationMarker?.isEnabled = false
            status = switch failure {
            case .startNotOnGrid: "\(response.actorID) is not standing anywhere walkable"
            case .destinationNotReachable: "Nowhere to stand there"
            case .noRoute: "No route to that point"
            }

        case .success(let path):
            let grid = navigationGrid(forAgent: response.actorID, at: clock.elapsed)
            let live = authoritativeState(for: actor, at: clock.elapsed)
            let liveSpeed = authoritativeSpeed(for: actor, at: clock.elapsed)
            let joinedPath = PathFinder.minimumLinkPath(
                from: live.position,
                path: path,
                in: grid
            )
            let joinedPoints = [live.position] + joinedPath.waypoints
            guard zip(joinedPoints, joinedPoints.dropFirst()).allSatisfy({
                PathFinder.hasLineOfSight(from: $0.0, to: $0.1, in: grid)
            }) else {
                // The actor moved behind different geometry while this worker
                // was solving. Keep the old route and retry from the new live
                // pose instead of snapping onto a stale corridor.
                if selectedActorID == response.actorID {
                    requestMoveSelectedActor(to: SIMD3<Float>(
                        Float(goal.x), 0, Float(goal.z)
                    ))
                }
                return
            }
            // The request already invalidated reservations current at tap
            // time, but the worker took real time to answer; clear whatever
            // may have opened against the actor's held-still position during
            // that gap too, now that its definitive new route is landing.
            invalidateBodyEncounterReservations(involving: response.actorID)
            navigation.task = makeNavigationTask(
                goal: .move(destination: goal),
                start: live.position,
                path: joinedPath,
                facing: live.facing,
                navigation: navigation,
                startedAt: clock.elapsed,
                initialSpeed: liveSpeed,
                grid: grid
            )
            actor.components[AgentNavigationComponent.self] = navigation
            timeAwareRouteActors.insert(response.actorID)

            if let arrival = joinedPath.waypoints.last {
                let marker = SIMD3<Float>(Float(arrival.x), 0, Float(arrival.z))
                showDestinationMarker(at: marker)
                destination = marker
            }
            let eta = joinedPath.length / navigation.character.walkSpeed
            status = String(
                format: "%@ -> %.1f m, %d legs, ETA %.1f s",
                response.actorID,
                joinedPath.length,
                joinedPath.waypoints.count,
                eta
            )
        }
    }

    private func commitInteractiveApproach(
        _ response: NavigationApproachPlanResponse,
        propID: String,
        interaction: InteractionKind,
        allowedSides: Set<ApproachPointSolver.Side>?
    ) {
        guard latestNavigationRequestByActor[response.actorID] == response.requestID else { return }
        guard response.worldRevision == (navigationWorld?.revision ?? 0) else {
            status = "World changed before \(response.actorID) could approach \(propID)"
            return
        }
        guard let actor = level?.actors[response.actorID],
              var navigation = actor.components[AgentNavigationComponent.self],
              let route = response.route else {
            automaticDoorResumeGoals.removeValue(forKey: response.actorID)
            status = "Nowhere to stand to reach \(propID)"
            return
        }

        let grid = navigationGrid(forAgent: response.actorID, at: clock.elapsed)
        let live = authoritativeState(for: actor, at: clock.elapsed)
        let liveSpeed = authoritativeSpeed(for: actor, at: clock.elapsed)
        let joinedPath = PathFinder.minimumLinkPath(
            from: live.position,
            path: route.path,
            in: grid
        )
        let joinedPoints = [live.position] + joinedPath.waypoints
        guard zip(joinedPoints, joinedPoints.dropFirst()).allSatisfy({
            PathFinder.hasLineOfSight(from: $0.0, to: $0.1, in: grid)
        }) else {
            requestInteraction(
                actorID: response.actorID,
                with: propID,
                interaction: interaction,
                allowedSides: allowedSides
            )
            return
        }
        invalidateBodyEncounterReservations(involving: response.actorID)
        navigation.task = makeNavigationTask(
            goal: .interact(objectID: propID, location: route.slot.position),
            start: live.position,
            path: joinedPath,
            facing: live.facing,
            navigation: navigation,
            startedAt: clock.elapsed,
            initialSpeed: liveSpeed,
            finalFacing: route.slot.facingDegrees,
            grid: grid
        )
        actor.components[AgentNavigationComponent.self] = navigation
        actor.components.set(PendingInteractionComponent(
            propID: propID,
            interaction: interaction,
            arrivalFacingDegrees: route.slot.facingDegrees
        ))
        status = "\(response.actorID) -> approaching \(propID) to \(interaction.rawValue)"
    }

    private var currentNavigationGrid: NavGrid {
        navigationWorld?.grid ?? level?.navGrid
            ?? NavGrid(minX: 0, minZ: 0, cellSize: 1, columns: 0, rows: 0, walkable: [])
    }

    private var navigationTopology: NavigationTopologySnapshot {
        if let mesh = navigationWorld?.bakedMesh { return .polygon(mesh) }
        return .polygon(NavigationMeshBaker.bake(from: currentNavigationGrid))
    }

    /// Static and persistent geometry is always solved on the polygon
    /// topology. Actor bodies deliberately stay out of this global graph and
    /// are handled by the fixed-step right-of-way/reservation layer.
    private func globalPath(
        from start: WorldPoint,
        to destination: WorldPoint,
        character: CharacterProfile
    ) -> Result<PathResult, PathFailure> {
        let mesh = navigationWorld?.bakedMesh
            ?? NavigationMeshBaker.bake(from: currentNavigationGrid)
        return PolygonPathFinder.findPath(
            from: start,
            to: destination,
            in: mesh,
            character: character
        )
    }

    private func navigationGrid(
        forAgent excludedID: String,
        at missionTime: Double,
        sweptAgentID: String? = nil,
        sweepHorizon: Double = 0
    ) -> NavGrid {
        guard let level, let navigationWorld else { return currentNavigationGrid }
        var blockers: [WorldBox] = []
        for id in level.actors.keys.sorted() where id != excludedID {
            guard let entity = level.actors[id],
                  let navigation = entity.components[AgentNavigationComponent.self] else { continue }
            let position = authoritativeState(for: entity, at: missionTime).position
            let future: WorldPoint
            if id == sweptAgentID, sweepHorizon > 0 {
                // Reserve the right-of-way actor's whole remaining steering
                // segment to its current goal/anchor. Truncating this to a time
                // slice merely moves the second conflict to the end of that
                // slice and causes another detour.
                future = navigation.task?.waypoints.last
                    ?? authoritativeState(for: entity, at: missionTime + sweepHorizon).position
            } else {
                future = position
            }
            let dx = future.x - position.x
            let dz = future.z - position.z
            let sweptLength = hypot(dx, dz)
            let centre = WorldPoint(
                x: (position.x + future.x) / 2,
                y: navigation.character.height / 2,
                z: (position.z + future.z) / 2
            )
            blockers.append(WorldBox(
                center: centre,
                width: navigation.character.width,
                height: navigation.character.height,
                depth: navigation.character.width + sweptLength,
                yaw: sweptLength > 0.01 ? atan2(dx, dz) * 180 / .pi : 0,
                surface: .fabric,
                sourceID: "agent-body.\(id)"
            ))
        }
        return navigationWorld.grid.blockingTransientObstacles(
            blockers,
            // Cell centres approximate continuous capsules. A small comfort
            // band absorbs that discretisation and prevents shoulder clipping
            // while keeping authored door clearance unchanged in the base mesh.
            // Rounded steering may cut inside a discrete cell-centre route.
            // Reserve enough transient-body margin that the resulting
            // continuous capsule still clears the other actor after rounding.
            characterRadius: navigationWorld.budget.characterRadius + 0.28,
            characterHeight: navigationWorld.budget.characterHeight
        )
    }

    /// Existing motion owns its corridor. A patrol is authored at mission start;
    /// a goal-directed task owns its corridor from the instant it is committed.
    private func trajectoryCommitment(for entity: Entity) -> Double? {
        if let task = entity.components[AgentNavigationComponent.self]?.task,
           !task.isBlocked {
            return task.startedAt
        }
        if entity.components[GuardComponent.self] != nil { return 0 }
        return nil
    }

    /// Captures future actor positions as plain Sendable data. The detached
    /// planner never reads RealityKit entities or mutable session state.
    private func reservedTrajectories(
        excluding excludedID: String,
        from startTime: Double
    ) -> [ReservedAgentTrajectory] {
        guard let level else { return [] }
        return level.actors.keys.sorted().compactMap { id in
            guard id != excludedID,
                  let entity = level.actors[id],
                  let navigation = entity.components[AgentNavigationComponent.self] else {
                return nil
            }
            let motion: ReservedAgentTrajectory.Motion
            if let task = navigation.task, !task.isBlocked {
                motion = .navigation(task)
            } else if let guardComponent = entity.components[GuardComponent.self],
                      !guardComponent.isPatrolPaused {
                motion = .patrol(
                    route: guardComponent.route,
                    phaseAtStart: guardComponent.patrolTime(at: startTime),
                    missionStart: startTime
                )
            } else {
                motion = .stationary(authoritativeState(for: entity, at: startTime).position)
            }
            return ReservedAgentTrajectory(
                actorID: id,
                radius: navigation.character.radius,
                committedAt: trajectoryCommitment(for: entity),
                tieBreakerPriority: avoidancePriority(for: entity),
                motion: motion
            )
        }
    }

    /// Role is only the deterministic tie-breaker for commands committed at
    /// exactly the same mission time; it never overrides an older trajectory.
    private func avoidancePriority(for entity: Entity) -> Int {
        entity.components[GuardComponent.self] == nil ? 50 : 10
    }

    private func makeNavigationTask(
        goal: AgentGoal,
        start: WorldPoint,
        path: PathResult,
        facing: Double,
        navigation: AgentNavigationComponent,
        startedAt: Double? = nil,
        initialSpeed: Double = 0,
        finalFacing: Double? = nil,
        grid: NavGrid? = nil
    ) -> AgentNavigationTask {
        let resolvedGrid = grid ?? currentNavigationGrid
        let trajectory = TrajectoryBuilder.continuous(
            start: start,
            path: path,
            initialFacing: facing,
            in: resolvedGrid,
            character: navigation.character
        )
        return AgentNavigationTask(
            goal: goal,
            start: start,
            path: trajectory,
            startedAt: startedAt ?? clock.elapsed,
            speed: navigation.character.walkSpeed,
            initialFacing: facing,
            initialSpeed: initialSpeed,
            finalFacing: finalFacing,
            worldRevision: navigationWorld?.revision ?? 0,
            acceleration: navigation.character.acceleration,
            deceleration: navigation.character.deceleration,
            maximumTurnRateDegrees: navigation.character.maximumTurnRateDegrees
        )
    }

    private func authoritativeState(for entity: Entity, at missionTime: Double) -> PatrolRoute.State {
        if let navigation = entity.components[AgentNavigationComponent.self],
           let task = navigation.task {
            let state = task.state(at: missionTime)
            return PatrolRoute.State(
                position: state.position,
                facing: state.facing,
                activity: state.activity == .walking ? .walking : .waiting
            )
        }
        if let guardComponent = entity.components[GuardComponent.self] {
            return guardComponent.route.state(
                at: guardComponent.patrolTime(at: missionTime)
            )
        }
        if let navigation = entity.components[AgentNavigationComponent.self] {
            return PatrolRoute.State(
                position: navigation.restingPosition,
                facing: navigation.restingFacing,
                activity: .waiting
            )
        }
        return PatrolRoute.State(
            position: WorldPoint(x: Double(entity.position.x), y: 0, z: Double(entity.position.z)),
            facing: Double(entity.orientation.angle) * 180 / .pi,
            activity: .waiting
        )
    }

    private func authoritativeSpeed(for entity: Entity, at missionTime: Double) -> Double {
        if let task = entity.components[AgentNavigationComponent.self]?.task {
            return task.state(at: missionTime).speed
        }
        if let guardComponent = entity.components[GuardComponent.self] {
            return guardComponent.route.state(at: guardComponent.patrolTime(at: missionTime)).activity
                == .walking ? guardComponent.route.speed : 0
        }
        return 0
    }

    private func settleNavigationTask(
        _ navigation: inout AgentNavigationComponent,
        at missionTime: Double
    ) {
        if let task = navigation.task {
            let state = task.state(at: missionTime)
            navigation.restingPosition = state.position
            navigation.restingFacing = state.facing
        }
        navigation.task = nil
    }

    private func playableActorID(for entity: Entity?) -> String? {
        var candidate = entity
        while let current = candidate {
            if let actor = current.components[PlayableActorComponent.self] {
                return actor.id
            }
            candidate = current.parent
        }
        return nil
    }

    private func interactableComponent(for entity: Entity?) -> InteractableComponent? {
        var candidate = entity
        while let current = candidate {
            if let interactable = current.components[InteractableComponent.self], interactable.isEnabled {
                return interactable
            }
            candidate = current.parent
        }
        return nil
    }

    private func tappablePropComponent(for entity: Entity?) -> LevelEntityComponent? {
        var candidate = entity
        while let current = candidate {
            if let levelEntity = current.components[LevelEntityComponent.self],
               levelEntity.kind != .scenery,
               levelEntity.kind != .architecture,
               levelEntity.kind != .marker,
               levelEntity.kind != .actor {
                return levelEntity
            }
            candidate = current.parent
        }
        return nil
    }

    private func showDestinationMarker(at point: SIMD3<Float>) {
        guard let destinationMarker else { return }
        destinationMarker.isEnabled = true
        destinationMarker.position = SIMD3<Float>(point.x, 0.02, point.z)
    }

}
