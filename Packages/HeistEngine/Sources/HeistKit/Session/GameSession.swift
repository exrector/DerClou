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
    @ObservationIgnored private var destinationMarker: Entity?

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
            // Interaction dispatch lands in a later phase; for now report what
            // the object offers so the wiring is visible and testable.
            let verbs = interactable.interactions.map(\.rawValue).joined(separator: ", ")
            status = "\(interactable.id): \(verbs)"
            return
        }

        moveSelectedActor(to: worldPoint)
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

        let from = actor.position(relativeTo: nil)
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
        destinationMarker.setPosition(SIMD3<Float>(point.x, 0.02, point.z), relativeTo: nil)
    }

}
