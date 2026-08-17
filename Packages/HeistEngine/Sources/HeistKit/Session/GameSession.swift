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
    /// Length of the last computed path, in meters.
    public private(set) var lastPathLength: Double = 0
    /// Number of waypoints in the last computed path.
    public private(set) var lastPathNodeCount: Int = 0

    @ObservationIgnored private var destinationMarker: Entity?
    @ObservationIgnored private var pathTask: Task<Void, Never>?

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

        let navigationState = built.navigationMesh == nil ? "navigation bake FAILED" : "navigation ready"
        status = built.issues.hasErrors
            ? "Loaded \(blueprint.id) with \(built.issues.errors.count) blueprint errors"
            : "Loaded \(blueprint.id), \(navigationState)"
        log.info("\(self.status, privacy: .public)")
    }

    // MARK: - Input

    /// Handles a tap that resolved to a world position, plus whatever entity was
    /// under the finger.
    public func handleTap(at worldPoint: SIMD3<Float>, entity: Entity?) {
        if let actorID = playableActorID(for: entity) {
            selectedActorID = actorID
            status = "Selected \(actorID)"
            return
        }

        if let interactable = interactableComponent(for: entity) {
            // Interaction dispatch lands in a later phase; for now report what
            // the object offers so the wiring is visible and testable.
            let verbs = interactable.interactions.map(\.rawValue).joined(separator: ", ")
            status = "\(interactable.id): \(verbs)"
            return
        }

        moveSelectedActor(to: worldPoint)
    }

    /// Requests a navigation path and starts walking the selected actor.
    public func moveSelectedActor(to worldPoint: SIMD3<Float>) {
        guard let actor = selectedActorEntity, let actorID = selectedActorID else {
            status = "No actor selected"
            return
        }

        showDestinationMarker(at: worldPoint)
        destination = worldPoint

        pathTask?.cancel()
        pathTask = Task { [weak self] in
            guard let self else { return }
            await self.requestPath(for: actor, actorID: actorID, to: worldPoint)
        }
    }

    private func requestPath(for actor: Entity, actorID: String, to worldPoint: SIMD3<Float>) async {
        let controller: NavigationController
        do {
            controller = try NavigationController(entity: actor)
        } catch {
            status = "Navigation unavailable: \(error.localizedDescription)"
            log.error("NavigationController init failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let path = await controller.computePath(to: worldPoint), !path.isEmpty else {
            status = "No route to that point"
            actor.components.remove(PathFollowingComponent.self)
            return
        }

        guard !Task.isCancelled else { return }

        let waypoints = path.map(\.position)
        actor.components.set(PathFollowingComponent(waypoints: waypoints))

        lastPathNodeCount = waypoints.count
        lastPathLength = Double(pathLength(from: actor.position(relativeTo: nil), through: waypoints))

        let speed = actor.components[PlayableActorComponent.self]?.walkSpeed ?? 1.4
        let eta = lastPathLength / Double(speed)
        status = String(
            format: "%@ -> %.1f m, %d nodes, ETA %.1f s",
            actorID,
            lastPathLength,
            waypoints.count,
            eta
        )
        log.debug("""
            Path for \(actorID, privacy: .public): \
            \(waypoints.count) nodes, \(self.lastPathLength, privacy: .public) m
            """)
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
        destinationMarker.setPosition(SIMD3<Float>(point.x, 0.02, point.z), relativeTo: nil)
    }

    private func pathLength(from start: SIMD3<Float>, through waypoints: [SIMD3<Float>]) -> Float {
        guard let first = waypoints.first else { return 0 }
        var total = distance(start, first)
        for index in 1..<max(waypoints.count, 1) {
            total += distance(waypoints[index - 1], waypoints[index])
        }
        return total
    }
}
