import RealityKit

/// Starts, stops and speed-matches a character's baked "Walk" clip.
///
/// Shared by every system that moves an actor — `PathFollowingSystem` for the
/// player-tapped Thief, `GuardPatrolSystem` for patrolling guards — so a
/// walking actor looks the same regardless of which system is driving its
/// position. Before this existed, only `PathFollowingSystem` called anything
/// like this: `GuardPatrolSystem` set a guard's position directly from
/// `PatrolRoute.state(at:)` (a pure lookup, by design — see that type's own
/// docs) and never touched animation at all, so a guard's model stayed
/// frozen on whatever frame `LevelSceneBuilder` had paused it on at load time
/// while its position kept moving: it slid across the floor rather than
/// walking. The owner caught this directly ("вор... нормально ходит... а
/// почему тогда охранник скользит по полу?") and was right that the two
/// should follow the same rule — they just didn't yet, because only one of
/// the two systems that move an actor had ever been taught to play a clip.
@MainActor
public enum WalkAnimationSync {
    /// The real-world pace the current "Walk" clip (Standard Walk.fbx,
    /// retargeted onto every character by ArtSource/Tools/apply_animation.py)
    /// was actually captured at — measured, not assumed: the clip's Hips
    /// bone travels 174.23 raw Blender units (== 1.7423 m once the standard
    /// Mixamo-import 0.01 object scale is applied) over 35 frames at the
    /// file's own 30 fps, i.e. 1.167 s, giving 1.7423 / 1.167 ≈ 1.49 m/s.
    /// `AnimationPlaybackController.speed` is a rate multiplier, not a
    /// duration, so this is what every `walkSpeed` gets divided by to find
    /// how much faster or slower than its own capture rate the clip should
    /// play — see `startWalking(for:walkSpeed:)`.
    public static let referenceWalkSpeed: Float = 1.49

    /// The clip name every character's walk cycle is exported under —
    /// `ArtSource/Tools/apply_animation.py`'s `action_name` argument.
    public static let clipName = "Walk"

    public static func startWalking(for entity: Entity, walkSpeed: Float) {
        guard let anim = CharacterAnimationLibrary.animation(named: clipName, on: entity) else { return }
        let rate = walkSpeed / referenceWalkSpeed
        for child in entity.children {
            let controller = child.playAnimation(anim.repeat(), transitionDuration: 0.15)
            controller.speed = rate
        }
    }

    public static func stopWalking(for entity: Entity) {
        guard let anim = CharacterAnimationLibrary.animation(named: clipName, on: entity) else {
            for child in entity.children {
                child.stopAllAnimations()
            }
            return
        }
        for child in entity.children {
            let controller = child.playAnimation(anim, transitionDuration: 0.15)
            controller.time = 0.0
            controller.pause()
        }
    }
}
