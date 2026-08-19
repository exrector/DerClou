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

    /// World region clear of system-reserved screen areas, for the current
    /// device and orientation.
    public private(set) var safeBounds: SafeGameplayBounds?
    /// Mission-critical objects currently sitting outside that region.
    public private(set) var placementIssues: [LevelIssue] = []

    @ObservationIgnored private var destinationMarker: Entity?
    @ObservationIgnored private var safeBoundsMarker: Entity?

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

        for issue in built.issues {
            log.warning("\(issue.description, privacy: .public)")
        }

        let marker = GreyboxKit.destinationMarker()
        marker.isEnabled = false
        built.root.addChild(marker)
        destinationMarker = marker

        // Select the first playable actor so the level is usable on launch.
        selectedActorID = built.geometry.actors
            .first { $0.prototype.id == "actor.thief" }?
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
        clock.advance(byRealTime: realTimeDelta)
        poseGuards(at: clock.elapsed)
        updateInteractions(at: clock.elapsed)
    }

    public func startClock() {
        clock.start()
    }

    public func pauseClock() {
        clock.pause()
    }

    /// Rewinds the mission to its opening state.
    public func resetClock() {
        clock.reset()
        poseGuards(at: 0)
    }

    private func poseGuards(at time: Double) {
        guard let level else { return }
        for entity in level.actors.values {
            guard var component = entity.components[GuardComponent.self] else { continue }
            component.missionTime = time
            entity.components[GuardComponent.self] = component
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
                playableActorID(for: hit.entity) != nil || interactableComponent(for: hit.entity) != nil
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
            beginInteraction(with: interactable.id, interaction: verb)
            return
        }

        moveSelectedActor(to: worldPoint)
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

        let from = actor.position
        let origin = WorldPoint(x: Double(from.x), y: 0, z: Double(from.z))

        guard let approach = ApproachPointSolver.approachPoint(
            for: prop.box, grid: level.navGrid, from: origin
        ) else {
            actor.components.remove(PathFollowingComponent.self)
            status = "Nowhere to stand to reach \(propID)"
            log.debug("No approach point for \(propID, privacy: .public)")
            return
        }

        switch PathFinder.findPath(from: origin, to: approach, in: level.navGrid) {
        case .failure(let failure):
            actor.components.remove(PathFollowingComponent.self)
            status = "No route to \(propID)"
            log.debug("""
                Approach path failed for \(actorID, privacy: .public) -> \(propID, privacy: .public): \
                \(failure.rawValue, privacy: .public)
                """)

        case .success(let path):
            actor.components.set(PathFollowingComponent(waypoints: path.waypoints))
            actor.components.set(PendingInteractionComponent(propID: propID, interaction: interaction))
            status = "\(actorID) -> approaching \(propID) to \(interaction.rawValue)"
            log.debug("""
                \(actorID, privacy: .public) approaching \(propID, privacy: .public) \
                to \(interaction.rawValue, privacy: .public), \(path.waypoints.count) legs
                """)
        }
    }

    /// Advances every actor's interaction state by one tick, in the same
    /// place and the same way `poseGuards(at:)` advances guards: a pure
    /// function of mission time, called only while the clock is running.
    ///
    /// Two independent transitions happen here, and only here:
    ///
    /// 1. **Pending -> active.** A `PendingInteractionComponent` survives
    ///    without its `PathFollowingComponent` exactly once — the frame the
    ///    walk finishes — because `PathFollowingSystem` removes
    ///    `PathFollowingComponent` the instant it is done. That is the
    ///    signal "arrived," and it starts the timed interaction itself.
    /// 2. **Active -> complete.** An `ActiveInteractionComponent` whose
    ///    `duration` has elapsed since `startedAt` (measured in mission
    ///    seconds, never render time) applies its effect via
    ///    `InteractionResolver.applying(_:to:)` and clears.
    private func updateInteractions(at missionTime: Double) {
        guard let level else { return }

        for (actorID, actor) in level.actors {
            if let pending = actor.components[PendingInteractionComponent.self],
               actor.components[PathFollowingComponent.self] == nil {
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

        let duration = InteractionResolver.duration(for: pending.interaction, config: interactable.config)
        actor.components.set(ActiveInteractionComponent(
            propID: pending.propID, interaction: pending.interaction,
            startedAt: missionTime, duration: duration
        ))
        status = "\(actorID) is \(pending.interaction.rawValue)ing \(pending.propID)"
        log.debug("""
            \(actorID, privacy: .public) started \(pending.interaction.rawValue, privacy: .public) \
            on \(pending.propID, privacy: .public), \(duration, privacy: .public) s
            """)
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
        guard let level else { return }

        // A plain destination always supersedes whatever the actor was in
        // the middle of doing — the same rule `beginInteraction` applies in
        // the other direction.
        actor.components.remove(PendingInteractionComponent.self)
        actor.components.remove(ActiveInteractionComponent.self)

        let from = actor.position
        let start = WorldPoint(x: Double(from.x), y: 0, z: Double(from.z))
        let goal = WorldPoint(x: Double(worldPoint.x), y: 0, z: Double(worldPoint.z))

        switch PathFinder.findPath(from: start, to: goal, in: level.navGrid) {
        case .failure(let failure):
            actor.components.remove(PathFollowingComponent.self)
            destinationMarker?.isEnabled = false
            status = switch failure {
            case .startNotOnGrid: "\(actorID) is not standing anywhere walkable"
            case .destinationNotReachable: "Nowhere to stand there"
            case .noRoute: "No route to that point"
            }
            log.debug("Path failed for \(actorID, privacy: .public): \(failure.rawValue, privacy: .public)")

        case .success(let path):
            actor.components.set(PathFollowingComponent(waypoints: path.waypoints))

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

    // MARK: - Helpers

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

    private func showDestinationMarker(at point: SIMD3<Float>) {
        guard let destinationMarker else { return }
        destinationMarker.isEnabled = true
        destinationMarker.position = SIMD3<Float>(point.x, 0.02, point.z)
    }

}
