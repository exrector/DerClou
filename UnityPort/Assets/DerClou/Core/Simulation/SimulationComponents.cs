namespace DerClou.Core.Simulation
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;

    [System.Serializable]
    public struct PatrolNode
    {
        public WorldPoint position;
        public float waitDuration;
        public float facingYaw;        // degrees, -1 = keep current
        public string actionId;        // optional interaction at this node
    }

    [System.Serializable]
    public class PatrolRoute
    {
        public int actorId;
        public PatrolNode[] nodes;
        public bool loop = true;
        public float startTimeOffset;  // mission time when patrol begins

        public PatrolNode GetNode(int index) => nodes[index % nodes.Length];
        public int NodeCount => nodes.Length;
    }

    /// Renamed from `GuardComponent` in U2 step 2b — this is now genuinely
    /// live simulation state (`MissionState.Guards`), not the dead,
    /// never-read data it was before that step.
    [System.Serializable]
    public class GuardState
    {
        public int actorId;
        public PatrolRoute route;
        public int currentNodeIndex;
        public float nodeArrivalTime;
        public enum State { Moving, Waiting, Acting, Alert }
        public State state;
        public bool isAlerted;
        public float alertLevel;  // 0..1

        // U7 stimulus investigation: where the guard is walking while
        // isAlerted, and when it arrived (0 = not yet arrived). Falling
        // edge of isAlerted is still the single rejoin event handled by
        // GuardPatrolSystem.ResumeAtNearestPatrolNode.
        public WorldPoint investigateTarget;
        public float investigateArrivedTime;

        public WorldPoint CurrentTarget => route.GetNode(currentNodeIndex).position;
    }

    [System.Serializable]
    public class InteractableComponent
    {
        public string id;
        public InteractionKind[] interactions;
        public System.Collections.Generic.Dictionary<string, LevelValue> config = new();
    }

    /// Renamed from `DoorComponent` in U2 step 2d — live state in
    /// `MissionState.Doors`, not the dead, never-read data it was before.
    /// `openDurationSeconds`/`closeDurationSeconds` are separate (not one
    /// symmetric `openSpeed`) because the old `Door` MonoBehaviour genuinely
    /// opened and closed at different rates — `DoorSystem` preserves that.
    [System.Serializable]
    public class DoorState
    {
        public string id;
        // Authoritative 2D footprint. Closed doors use this same box for
        // navigation and deterministic vision occlusion; the Unity renderer
        // remains only the 3D presentation/shadow caster.
        public WorldBox footprint;
        public DoorHingeSide hingeSide;
        public float openAngleDegrees;
        public bool isOpen;         // target
        public float openProgress;  // 0..1, animated toward the target
        public float openDurationSeconds = 1f;
        public float closeDurationSeconds = 1f;
        public bool isLocked;
        public int lockDifficulty;
    }

    /// Renamed from `SecurityCameraComponent` in U2 step 2c — live state in
    /// `MissionState.Cameras`, not the dead, never-read data it was before.
    [System.Serializable]
    public class CameraState
    {
        public string id;
        public float range;
        public float fieldOfView;
        public float mountHeight;
        public float scanArc;
        public float scanPeriod;
        public float baseYaw;
        public bool powered = true;
        public float currentYaw;
        public float scanPhase;
    }

    [System.Serializable]
    public class AlarmComponent
    {
        public bool isTriggered;
        public float triggerTime;
        public string sourceId;
        public System.Collections.Generic.List<string> linkedDoors = new();
        public System.Collections.Generic.List<string> linkedCameras = new();
    }

    [System.Serializable]
    public class LaserComponent
    {
        public string id;
        public WorldPoint emitterPos;
        public WorldPoint receiverPos;
        public bool isActive = true;
        public bool isTripped;
        public float tripTime;
    }

    [System.Serializable]
    public class LootComponent
    {
        public string id;
        public int value;
        public float weight;
        public bool isCollected;
    }

    /// Renamed from `SafeComponent` in U2 step 2e — live state in
    /// `MissionState.Safes`, not the dead, never-read data it was before.
    /// Carries `position` (unlike the door/camera states, which never needed
    /// one) because `SafeSystem` itself now does the "is the cracking actor
    /// still close enough" check that used to compare two Transforms
    /// directly inside `InteractionSystem.Update()`.
    [System.Serializable]
    public class SafeState
    {
        public string id;
        public WorldPoint position;
        public bool isLocked = true;
        public int difficulty;
        public float crackProgress; // 0..1
        public bool isOpen;
        public float crackDurationSeconds = 20f;
        public bool isBeingCracked;
        public int crackingActorId = -1;
        public System.Collections.Generic.List<string> containedLootIds = new();
    }
}
