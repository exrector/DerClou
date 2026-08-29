namespace DerClou.Gameplay.Actors
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;

    /// <summary>
    /// Unity presentation of one actor. Renamed from <c>ActorEntity</c> as
    /// part of U2 step 2a (`docs/U2_SIMULATION_DESIGN.md`): this class no
    /// longer decides where the actor is. <see cref="Core.Systems.ActorMovementSystem"/>
    /// advances the actor's <see cref="ActorState"/> on a fixed simulation
    /// step; this class only reads that state back each frame and applies it
    /// to the Transform/Animator. <see cref="SetDestination"/>/<see cref="Stop"/>
    /// write into the state (via <see cref="PathFinder"/>, same as before)
    /// rather than mutating anything this class owns itself.
    /// </summary>
    [RequireComponent(typeof(Animator))]
    public class ActorView : MonoBehaviour
    {
        public int ActorId { get; private set; }
        public ActorRole Role { get; private set; }
        public CharacterProfile Profile { get; private set; }
        public string AppearanceKey { get; private set; }

        public Animator Animator { get; private set; }

        /// Instantaneous speed for animation purposes. Walking speed is
        /// intentionally constant (`README.md` — "Character walking speed is
        /// intentionally constant/simplified"), so this is just "moving or
        /// not", not a sampled velocity.
        public float CurrentSpeed =>
            SimulationService.Current != null
            && SimulationService.Current.Actors.TryGetValue(ActorId, out var s)
                ? s.CurrentSpeed : 0f;

        [Header("Flashlight")]
        public bool carryFlashlight = false;
        public Transform flashlightHandBone;
        public GameObject flashlightPrefab;
        private GameObject flashlightInstance;
        private Transform flashlightGripSocket;
        private Transform flashlightLightOrigin;
        private int flashlightLayerIndex = -1;
        private int flashlightGripLayerIndex = -1;

        public float flashlightPropScale = 1f;

        public Transform FlashlightVisualOrigin => flashlightLightOrigin;

        private int walkHash = Animator.StringToHash("Walk");
        private int idleHash = Animator.StringToHash("Idle");

        public void Initialize(int actorId, ActorRole role, CharacterProfile profile, string appearanceKey)
        {
            ActorId = actorId;
            Role = role;
            Profile = profile;
            AppearanceKey = appearanceKey;

            Animator = GetComponentInChildren<Animator>();

            var state = SimulationService.Current;
            if (state != null)
            {
                state.Actors[actorId] = new ActorState
                {
                    ActorId = actorId,
                    Role = role,
                    Profile = profile,
                    Position = new WorldPoint(transform.position.x, transform.position.y, transform.position.z),
                    FacingYawDegrees = transform.eulerAngles.y,
                    CurrentPath = null,
                    PathIndex = 0,
                    HasPath = false,
                    AvoidancePriority = role == ActorRole.Guard ? 10 : 50,
                    TrajectoryCommittedAt = float.PositiveInfinity
                };
            }

            // Supports authored prefabs that already opt into a flashlight.
            // Runtime level construction normally calls ConfigureFlashlight
            // after Initialize, once the guard vision source is known.
            if (carryFlashlight && flashlightPrefab != null && flashlightHandBone != null)
            {
                bool useLeftHand = flashlightHandBone == Animator.GetBoneTransform(HumanBodyBones.LeftHand);
                flashlightGripSocket = CreateFlashlightGripSocket(useLeftHand);
                flashlightInstance = Instantiate(flashlightPrefab, flashlightGripSocket);
                flashlightInstance.transform.localPosition = Vector3.zero;
                flashlightInstance.transform.localRotation = Quaternion.identity;
                flashlightInstance.transform.localScale = Vector3.one * flashlightPropScale;
                flashlightLightOrigin = CreateFlashlightLightOrigin();
            }
        }

        public void SetDestination(Vector3 worldPos)
        {
            // Thin wrapper — `ActorMovementSystem.RequestPath` is the single
            // shared implementation (also used by the pure-C#
            // `Systems.GuardPatrolSystem`), including the dedup guard that
            // used to live here as private fields.
            ActorMovementSystem.RequestPath(SimulationService.Current, ActorId, new WorldPoint(worldPos.x, 0, worldPos.z));
        }

        /// Snaps facing directly to `yawDegrees` (e.g. a patrol node's
        /// authored facing). Must go through state, not `transform.rotation`
        /// directly — `LateUpdate` re-applies `ActorState.FacingYawDegrees`
        /// every frame, so a direct Transform write would be silently
        /// overwritten the instant this actor next has (or doesn't have) a
        /// path.
        public void SetFacingYaw(float yawDegrees)
        {
            var state = SimulationService.Current;
            if (state == null || !state.Actors.TryGetValue(ActorId, out var current)) return;
            current.FacingYawDegrees = yawDegrees;
            state.Actors[ActorId] = current;
        }

        public void Stop() => ActorMovementSystem.Stop(SimulationService.Current, ActorId);

        private void LateUpdate()
        {
            var state = SimulationService.Current;
            if (state == null || !state.Actors.TryGetValue(ActorId, out var s)) return;

            transform.position = new Vector3(s.Position.x, s.Position.y, s.Position.z);
            transform.rotation = Quaternion.Euler(0, s.FacingYawDegrees, 0);
        }

        public void UpdateAnimation(float speed)
        {
            if (HasAnimatorController)
            {
                bool moving = speed > 0.1f;
                Animator.SetBool(walkHash, moving);
                Animator.SetBool(idleHash, !moving);
                Animator.SetFloat("Speed", speed / Mathf.Max(0.01f, Profile.walkSpeed));
            }
        }

        public void ApplyFlashlightPose()
        {
            if (!carryFlashlight || Animator == null) return;
            if (flashlightLayerIndex >= 0)
                Animator.SetLayerWeight(flashlightLayerIndex, 1f);
            if (flashlightGripLayerIndex >= 0)
                Animator.SetLayerWeight(flashlightGripLayerIndex, 1f);
        }

        public void RemoveFlashlightPose()
        {
            if (Animator != null && flashlightLayerIndex >= 0)
                Animator.SetLayerWeight(flashlightLayerIndex, 0f);
            if (Animator != null && flashlightGripLayerIndex >= 0)
                Animator.SetLayerWeight(flashlightGripLayerIndex, 0f);
        }

        /// <summary>
        /// Attaches one visual flashlight and enables the authored upper-body
        /// IK pose. Returns the flashlight transform so the physical Unity
        /// Spot Light can originate from the held object instead of a floating
        /// proxy beside the actor.
        /// </summary>
        public Transform ConfigureFlashlight(GameObject prefab, bool useLeftHand = false)
        {
            if (Animator == null || !Animator.isHuman || prefab == null) return null;

            carryFlashlight = true;
            flashlightPrefab = prefab;
            flashlightHandBone = Animator.GetBoneTransform(
                useLeftHand ? HumanBodyBones.LeftHand : HumanBodyBones.RightHand);
            if (flashlightHandBone == null) return null;

            if (flashlightInstance == null)
            {
                flashlightGripSocket = CreateFlashlightGripSocket(useLeftHand);
                flashlightInstance = Instantiate(flashlightPrefab, flashlightGripSocket);
                flashlightInstance.name = "HeldFlashlight";
                flashlightInstance.transform.SetLocalPositionAndRotation(Vector3.zero, Quaternion.identity);
                flashlightInstance.transform.localScale = Vector3.one * flashlightPropScale;
                flashlightLightOrigin = CreateFlashlightLightOrigin();
            }

            // The animation pack supplies a Humanoid right-arm hold clip and
            // an authored weapon_r track. Use the standard Animator layer;
            // do not add a competing procedural IK solver.
            flashlightLayerIndex = Animator.GetLayerIndex("Flashlight Hold");
            flashlightGripLayerIndex = Animator.GetLayerIndex("Flashlight Grip");
            if (flashlightLayerIndex >= 0)
                Animator.SetLayerWeight(flashlightLayerIndex, 1f);
            if (flashlightGripLayerIndex >= 0)
                Animator.SetLayerWeight(flashlightGripLayerIndex, 1f);

            return flashlightLightOrigin;
        }

        private Transform CreateFlashlightLightOrigin()
        {
            if (flashlightLightOrigin != null) return flashlightLightOrigin;

            var originObject = new GameObject("FlashlightLightOrigin");
            flashlightLightOrigin = originObject.transform;
            flashlightLightOrigin.SetParent(flashlightInstance.transform, false);
            // The matching SK_Flashlight prefab is authored along local Y;
            // its front cap is approximately 0.152 m from the root.
            flashlightLightOrigin.localPosition = new Vector3(0f, 0.155f, 0f);
            flashlightLightOrigin.localRotation = Quaternion.identity;
            return flashlightLightOrigin;
        }

        /// <summary>
        /// Creates the target-avatar socket. Its final local transform is
        /// captured after Mecanim has evaluated the standard hold animation.
        /// </summary>
        private Transform CreateFlashlightGripSocket(bool useLeftHand)
        {
            if (flashlightGripSocket != null) return flashlightGripSocket;

            var socketObject = new GameObject("FlashlightGripSocket");
            flashlightGripSocket = socketObject.transform;
            flashlightGripSocket.SetParent(flashlightHandBone, false);
            flashlightGripSocket.SetLocalPositionAndRotation(Vector3.zero, Quaternion.identity);
            return flashlightGripSocket;
        }

        public void SetFlashlightActive(bool active)
        {
            if (flashlightInstance != null) flashlightInstance.SetActive(active);
        }

        private bool HasAnimatorController => Animator != null && Animator.runtimeAnimatorController != null;
    }
}
