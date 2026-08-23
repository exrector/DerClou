import Foundation
import RealityKit
import simd

@MainActor
public enum CharacterFlashlightPlayback {
    /// Adds a constant "holding flashlight" offset to the right-arm joints.
    ///
    /// Uses an additive animation with `by:` (the intended way for constant
    /// additive offsets). Targets short joint names as used by Mixamo rigs on
    /// the SkelRoot that owns the walk animation.
    @discardableResult
    public static func applyFlashlightPose(to skeletonOwner: Entity) -> Bool {
        // Short joint names as they appear on the SkelRoot animation owner.
        let joints = [
            "RightShoulder",
            "RightArm",
            "RightForeArm",
            "RightHand"
        ]

        // Additive delta: raise and bend the right arm forward.
        let shoulderRot = simd_quatf(angle: -0.3, axis: [1, 0, 0])
        let armRot = simd_quatf(angle: .pi / 3.0, axis: [1, 0, 0])   // ~60° forward
        let foreArmRot = simd_quatf(angle: .pi / 2.0, axis: [1, 0, 0]) // 90° elbow bend
        let handRot = simd_quatf(angle: 0, axis: [1, 0, 0])

        let delta = JointTransforms([
            Transform(rotation: shoulderRot),
            Transform(rotation: armRot),
            Transform(rotation: foreArmRot),
            Transform(rotation: handRot)
        ])

        // Constant additive offset via `by:` — the value `delta` is added
        // to the base (walk) pose every frame. Translation is zero → bone
        // lengths preserved. `duration` + `repeat()` keeps it alive.
        let animation = FromToByAnimation<JointTransforms>(
            jointNames: joints,
            name: "FlashlightPose",
            by: delta,
            duration: 1.0,
            isAdditive: true,
            bindTarget: .transform,
            blendLayer: 10
        )

        if let resource = try? AnimationResource.generate(with: animation) {
            _ = skeletonOwner.playAnimation(resource.repeat())
            return true
        }
        return false
    }
}