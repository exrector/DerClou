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
            && s.HasPath
                ? Profile.walkSpeed : 0f;

        [Header("Flashlight (Guard03)")]
        public bool carryFlashlight = false;
        public Transform rightHandBone;
        public GameObject flashlightPrefab;
        private GameObject flashlightInstance;

        private int walkHash = Animator.StringToHash("Walk");
        private int idleHash = Animator.StringToHash("Idle");
        private int flashlightLayerIndex = 1;

        public void Initialize(int actorId, ActorRole role, CharacterProfile profile, string appearanceKey)
        {
            ActorId = actorId;
            Role = role;
            Profile = profile;
            AppearanceKey = appearanceKey;

            Animator = GetComponent<Animator>();

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
                    HasPath = false
                };
            }

            // Flashlight setup for Guard03
            if (carryFlashlight && flashlightPrefab != null && rightHandBone != null)
            {
                flashlightInstance = Instantiate(flashlightPrefab, rightHandBone);
                flashlightInstance.transform.localPosition = Vector3.zero;
                flashlightInstance.transform.localRotation = Quaternion.identity;
            }

            // Ensure additive layer exists
            if (Animator != null && Animator.layerCount > flashlightLayerIndex)
            {
                Animator.SetLayerWeight(flashlightLayerIndex, 1f);
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
            if (Animator != null)
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

            // Use additive layer for right arm
            Animator.SetLayerWeight(flashlightLayerIndex, 1f);

            // The flashlight pose should be driven by an additive animation clip
            // named "FlashlightPose" on layer 1. Ensure the clip targets only:
            // RightShoulder, RightArm, RightForeArm, RightHand
            // and is marked Additive in the import settings.
            Animator.CrossFadeInFixedTime("FlashlightPose", 0.2f, flashlightLayerIndex);
        }

        public void RemoveFlashlightPose()
        {
            if (Animator != null)
            {
                Animator.SetLayerWeight(flashlightLayerIndex, 0f);
            }
        }

        public void SetFlashlightActive(bool active)
        {
            if (flashlightInstance != null) flashlightInstance.SetActive(active);
        }
    }
}
