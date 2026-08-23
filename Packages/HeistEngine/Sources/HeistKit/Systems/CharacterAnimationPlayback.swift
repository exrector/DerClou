import Foundation
import RealityKit

/// Stable animation vocabulary used by gameplay. Asset filenames, Blender
/// action suffixes and RealityKit's generated resource names stay behind the
/// character manifest/adapter.
public enum CharacterAnimationSemantic: String, CaseIterable, Sendable, Equatable {
    case idle = "Idle"
    case startWalking = "StartWalking"
    case walk = "Walk"
    case stopWalking = "StopWalking"
    case shortStep = "ShortStep"
    case turnLeft = "TurnLeft"
    case turnRight = "TurnRight"
    case turnAround = "TurnAround"
    case openDoor = "OpenDoor"
    case closeDoor = "CloseDoor"
    case lockpick = "Lockpick"
    case unlockDoor = "UnlockDoor"
    case pressButton = "PressButton"
    case pullLever = "PullLever"
    case look = "Look"
}

@MainActor
public enum CharacterAnimationPlayback {
    @discardableResult
    public static func playLoop(
        _ semantic: CharacterAnimationSemantic,
        on entity: Entity,
        speed: Float = 1,
        transitionDuration: TimeInterval = 0.15
    ) -> Bool {
        let bindings = CharacterAnimationLibrary.bindings(named: semantic.rawValue, on: entity)
        for binding in bindings {
            let controller = binding.entity.playAnimation(
                binding.resource.repeat(), transitionDuration: transitionDuration
            )
            controller.speed = speed
        }
        return !bindings.isEmpty
    }

    @discardableResult
    public static func playOnce(
        _ semantic: CharacterAnimationSemantic,
        on entity: Entity,
        speed: Float = 1,
        transitionDuration: TimeInterval = 0.12
    ) -> Bool {
        let bindings = CharacterAnimationLibrary.bindings(named: semantic.rawValue, on: entity)
        for binding in bindings {
            let controller = binding.entity.playAnimation(
                binding.resource, transitionDuration: transitionDuration
            )
            controller.speed = speed
        }
        return !bindings.isEmpty
    }

    public static func rest(on entity: Entity) {
        if playLoop(.idle, on: entity) { return }

        // Until an Idle clip is exported, hold the first Walk frame rather than
        // letting the last stride freeze in mid-air.
        for binding in CharacterAnimationLibrary.bindings(
            named: CharacterAnimationSemantic.walk.rawValue,
            on: entity
        ) {
            let controller = binding.entity.playAnimation(
                binding.resource, transitionDuration: 0.12
            )
            controller.time = 0
            controller.pause()
        }
    }
}
