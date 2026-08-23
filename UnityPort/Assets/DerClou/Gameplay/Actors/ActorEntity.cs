namespace DerClou.Gameplay.Actors
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using DerClou.Core.Simulation;
    using DerClou.Core.Time;
    using DerClou.Gameplay.Level;
    using UnityEngine;

    /// <summary>
    /// Unity representation of an actor in the scene.
    /// <para>
    /// Movement is a grid path follower over <see cref="NavigationService.Grid"/>
    /// (<see cref="PathFinder"/>, pure C#), not <c>UnityEngine.AI.NavMeshAgent</c>.
    /// This matches how the Swift/RealityKit version split the project — a
    /// pure-Swift 2D/2.5D simulation layer feeding a 3D presentation layer —
    /// and was switched to deliberately: `NavMeshAgent`'s built-in local
    /// avoidance is not fully deterministic run to run, which conflicts with
    /// the game's own "same plan, same result" design requirement
    /// (`docs/GAME_DESIGN.md` §6), and a plain grid path is fully testable
    /// without the Editor at all.
    /// </para>
    /// </summary>
    [RequireComponent(typeof(Animator))]
    public class ActorEntity : MonoBehaviour
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
        public float CurrentSpeed => hasPath ? Profile.walkSpeed : 0f;

        [Header("Flashlight (Guard03)")]
        public bool carryFlashlight = false;
        public Transform rightHandBone;
        public GameObject flashlightPrefab;
        private GameObject flashlightInstance;

        private int walkHash = Animator.StringToHash("Walk");
        private int idleHash = Animator.StringToHash("Idle");
        private int flashlightLayerIndex = 1;

        private WorldPoint[] currentPath;
        private int pathIndex;
        private bool hasPath;
        private const float ArrivalTolerance = 0.05f;

        public void Initialize(int actorId, ActorRole role, CharacterProfile profile, string appearanceKey)
        {
            ActorId = actorId;
            Role = role;
            Profile = profile;
            AppearanceKey = appearanceKey;

            Animator = GetComponent<Animator>();

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

        private Vector3 lastRequestedDestination;
        private bool hasRequestedDestination;

        public void SetDestination(Vector3 worldPos)
        {
            // Callers (`GuardPatrolSystem.TickGuard` in particular) call this
            // every tick for as long as an actor is walking toward the same
            // node — without this check, that is a full A* solve every
            // frame for every walking actor, for a destination that hasn't
            // moved.
            if (hasPath && hasRequestedDestination
                && (worldPos - lastRequestedDestination).sqrMagnitude < 0.01f) return;

            lastRequestedDestination = worldPos;
            hasRequestedDestination = true;

            var grid = NavigationService.Grid;
            if (grid == null) { hasPath = false; return; }

            var start = new WorldPoint(transform.position.x, 0, transform.position.z);
            var goal = new WorldPoint(worldPos.x, 0, worldPos.z);
            var path = PathFinder.FindPath(grid, start, goal);
            if (path.Length == 0) { hasPath = false; return; }

            currentPath = path;
            pathIndex = 0;
            hasPath = true;
        }

        public void Stop()
        {
            hasPath = false;
            currentPath = null;
        }

        private void Update()
        {
            if (!hasPath || currentPath == null || pathIndex >= currentPath.Length) return;

            var wp = currentPath[pathIndex];
            var target = new Vector3(wp.x, transform.position.y, wp.z);
            var toTarget = target - transform.position;
            toTarget.y = 0f;
            float distance = toTarget.magnitude;

            if (distance <= ArrivalTolerance)
            {
                pathIndex++;
                if (pathIndex >= currentPath.Length)
                {
                    hasPath = false;
                    currentPath = null;
                }
                return;
            }

            var direction = toTarget / distance;
            float step = Profile.walkSpeed * Time.deltaTime;
            transform.position += direction * Mathf.Min(step, distance);

            if (Profile.maxTurnRateDegrees > 0f)
            {
                var targetRotation = Quaternion.LookRotation(direction, Vector3.up);
                transform.rotation = Quaternion.RotateTowards(
                    transform.rotation, targetRotation, Profile.maxTurnRateDegrees * Time.deltaTime);
            }
            else
            {
                transform.rotation = Quaternion.LookRotation(direction, Vector3.up);
            }
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
