import GameplayKit
import HeistCore
import RealityKit

/// Universal presentation phases shared by thieves, guards and future actors.
/// Gameplay remains mission-time data; this component only remembers which
/// animation block has already been presented for the current authoritative
/// phase.
public enum CharacterActionPhase: String, Sendable, Equatable {
    case idle
    case turningLeft
    case turningRight
    case turningAround
    case starting
    case walking
    case braking
    case shortStep
    case aligningLeft
    case aligningRight
    case aligningAround
    case interacting
    case blocked
}

public struct CharacterActionIntent: Sendable, Equatable {
    public var phase: CharacterActionPhase
    public var animation: CharacterAnimationSemantic?
    public var fallbackAnimation: CharacterAnimationSemantic?
    public var loops: Bool
    public var playbackSpeed: Float

    public init(
        phase: CharacterActionPhase,
        animation: CharacterAnimationSemantic? = nil,
        fallbackAnimation: CharacterAnimationSemantic? = nil,
        loops: Bool = false,
        playbackSpeed: Float = 1
    ) {
        self.phase = phase
        self.animation = animation
        self.fallbackAnimation = fallbackAnimation
        self.loops = loops
        self.playbackSpeed = playbackSpeed
    }
}

/// A RealityKit component may contain reference-backed Apple game state (the
/// same pattern as a `GKAgent` component). The reference is presentation-only:
/// position, facing, interaction completion and replay never read it.
public struct CharacterActionStateComponent: Component {
    public fileprivate(set) var phase: CharacterActionPhase
    public fileprivate(set) var animation: CharacterAnimationSemantic?
    public fileprivate(set) var enteredAt: Double
    fileprivate var driver: CharacterActionStateDriver

    public init(missionTime: Double = 0) {
        phase = .idle
        animation = .idle
        enteredAt = missionTime
        driver = CharacterActionStateDriver(initial: .idle)
    }

    @MainActor
    public mutating func synchronize(
        to intent: CharacterActionIntent,
        on entity: Entity,
        missionTime: Double
    ) {
        guard intent.phase != phase || intent.animation != animation else { return }
        driver.enter(intent.phase)
        phase = intent.phase
        animation = intent.animation
        enteredAt = missionTime
        Self.present(intent, on: entity)
    }

    @MainActor
    private static func present(_ intent: CharacterActionIntent, on entity: Entity) {
        guard let animation = intent.animation else {
            CharacterAnimationPlayback.rest(on: entity)
            return
        }

        let played: Bool
        if intent.loops {
            played = CharacterAnimationPlayback.playLoop(
                animation,
                on: entity,
                speed: intent.playbackSpeed
            )
        } else {
            played = CharacterAnimationPlayback.playOnce(
                animation,
                on: entity,
                speed: intent.playbackSpeed
            )
        }
        guard !played else { return }

        if let fallback = intent.fallbackAnimation {
            // Turn clips are not yet present on every downloaded rig. A slow
            // Walk fallback visibly transfers weight between feet while the
            // authoritative body pivots in place, rather than rotating rigid
            // planted feet across the floor.
            if fallback == .walk {
                _ = CharacterAnimationPlayback.playLoop(
                    .walk,
                    on: entity,
                    speed: max(0.28, intent.playbackSpeed)
                )
            } else {
                _ = CharacterAnimationPlayback.playOnce(fallback, on: entity)
            }
        } else {
            CharacterAnimationPlayback.rest(on: entity)
        }
    }
}

/// Persistent Apple `GKStateMachine` boundary. Its only job is to serialize
/// presentation-state transitions; the desired phase is still derived from
/// mission time on every update, so seeking or replay cannot change gameplay.
private final class CharacterActionStateDriver: @unchecked Sendable {
    private var machine: GKStateMachine
    private var phase: CharacterActionPhase

    init(initial: CharacterActionPhase) {
        phase = initial
        machine = Self.makeMachine()
        _ = machine.enter(Self.stateClass(for: initial))
    }

    @MainActor
    func enter(_ desired: CharacterActionPhase) {
        guard desired != phase else { return }
        let target = Self.stateClass(for: desired)
        if !machine.enter(target) {
            // A timeline seek may legitimately skip intermediate visual
            // phases. Rebuild presentation state directly; simulation data is
            // already authoritative for the requested mission time.
            machine = Self.makeMachine()
            _ = machine.enter(target)
        }
        phase = desired
    }

    private static func makeMachine() -> GKStateMachine {
        GKStateMachine(states: [
            RestingState(), TurningState(), StartingState(), WalkingState(),
            BrakingState(), ShortStepState(), AligningState(),
            InteractingState(), BlockedState()
        ])
    }

    private static func stateClass(for phase: CharacterActionPhase) -> GKState.Type {
        switch phase {
        case .idle: RestingState.self
        case .turningLeft, .turningRight, .turningAround: TurningState.self
        case .starting: StartingState.self
        case .walking: WalkingState.self
        case .braking: BrakingState.self
        case .shortStep: ShortStepState.self
        case .aligningLeft, .aligningRight, .aligningAround: AligningState.self
        case .interacting: InteractingState.self
        case .blocked: BlockedState.self
        }
    }
}

private class CharacterGKState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        // Mission-time sampling can legitimately jump across presentation
        // phases during replay or a slow render frame. The state machine owns
        // exclusive entry/exit ordering, while the pure simulation owns which
        // phase is correct; no render transition may veto that truth.
        stateClass is CharacterGKState.Type
    }
}

private final class RestingState: CharacterGKState {}
private final class TurningState: CharacterGKState {}
private final class StartingState: CharacterGKState {}
private final class WalkingState: CharacterGKState {}
private final class BrakingState: CharacterGKState {}
private final class ShortStepState: CharacterGKState {}
private final class AligningState: CharacterGKState {}
private final class InteractingState: CharacterGKState {}
private final class BlockedState: CharacterGKState {}

@MainActor
public enum CharacterActionIntentResolver {
    public static func task(
        _ state: AgentNavigationTask.State,
        character: CharacterProfile
    ) -> CharacterActionIntent {
        let walkRate = Float(max(0.2, state.speed)) / WalkAnimationSync.referenceWalkSpeed
        switch state.activity {
        case .turningLeft:
            return turn(
                state.isAlignment ? .aligningLeft : .turningLeft,
                animation: .turnLeft,
                character: character
            )
        case .turningRight:
            return turn(
                state.isAlignment ? .aligningRight : .turningRight,
                animation: .turnRight,
                character: character
            )
        case .turningAround:
            return turn(
                state.isAlignment ? .aligningAround : .turningAround,
                animation: .turnAround,
                character: character
            )
        case .starting:
            return CharacterActionIntent(
                phase: .starting,
                animation: .startWalking,
                fallbackAnimation: .walk,
                playbackSpeed: max(0.35, walkRate)
            )
        case .walking:
            return CharacterActionIntent(
                phase: .walking,
                animation: .walk,
                loops: true,
                playbackSpeed: max(0.35, walkRate)
            )
        case .braking:
            return CharacterActionIntent(
                phase: .braking,
                animation: .stopWalking,
                fallbackAnimation: .walk,
                playbackSpeed: max(0.28, walkRate)
            )
        case .shortStep:
            return CharacterActionIntent(
                phase: .shortStep,
                animation: .shortStep,
                fallbackAnimation: .walk,
                playbackSpeed: max(0.3, walkRate)
            )
        case .arrived:
            return CharacterActionIntent(phase: .idle, animation: .idle, loops: true)
        case .blocked:
            return CharacterActionIntent(phase: .blocked, animation: .idle, loops: true)
        }
    }

    public static func patrol(
        _ state: PatrolRoute.State,
        speed: Double,
        character: CharacterProfile
    ) -> CharacterActionIntent {
        switch state.activity {
        case .walking:
            return CharacterActionIntent(
                phase: .walking,
                animation: .walk,
                loops: true,
                playbackSpeed: Float(speed) / WalkAnimationSync.referenceWalkSpeed
            )
        case .turning:
            switch state.turnDirection {
            case .right:
                return turn(.turningRight, animation: .turnRight, character: character)
            case .around:
                return turn(.turningAround, animation: .turnAround, character: character)
            case .left, .none:
                return turn(.turningLeft, animation: .turnLeft, character: character)
            }
        case .waiting:
            return CharacterActionIntent(phase: .idle, animation: .idle, loops: true)
        }
    }

    public static func interaction(_ interaction: InteractionKind) -> CharacterActionIntent {
        let semantic: CharacterAnimationSemantic
        let fallback: CharacterAnimationSemantic?
        switch interaction {
        case .open:
            semantic = .openDoor; fallback = .look
        case .close:
            semantic = .closeDoor; fallback = .openDoor
        case .unlock:
            semantic = .unlockDoor; fallback = .openDoor
        case .lockpick, .crackSafe:
            semantic = .lockpick; fallback = .look
        case .toggleSwitch:
            semantic = .pressButton; fallback = .pullLever
        case .inspect, .search, .hack, .takeLoot, .extract:
            semantic = .look; fallback = nil
        }
        return CharacterActionIntent(
            phase: .interacting,
            animation: semantic,
            fallbackAnimation: fallback
        )
    }

    public static let idle = CharacterActionIntent(
        phase: .idle,
        animation: .idle,
        loops: true
    )

    private static func turn(
        _ phase: CharacterActionPhase,
        animation: CharacterAnimationSemantic,
        character: CharacterProfile
    ) -> CharacterActionIntent {
        // The shared lower-body source performs a 180-degree weight-transfer
        // turn in 47 frames at 30 fps (~114.9 degrees/second). Entity yaw owns
        // the actual direction; scale the footwork to finish with the exact
        // mission-time turn instead of playing the clip slower as turn speed
        // increases.
        let sourceAngularRate = 180.0 / (47.0 / 30.0)
        let turnRate = Float(character.maximumTurnRateDegrees / sourceAngularRate)
        return CharacterActionIntent(
            phase: phase,
            animation: animation,
            fallbackAnimation: .walk,
            playbackSpeed: max(0.5, min(3.0, turnRate))
        )
    }
}
