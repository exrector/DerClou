namespace DerClou.Core.Simulation
{
    using DerClou.Core.Data;
    using DerClou.Core.Navigation;
    using UnityEngine;

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

        public WorldPoint CurrentTarget => route.GetNode(currentNodeIndex).position;
    }

    [System.Serializable]
    public class VisionComponent
    {
        public int sourceId;
        public VisionSourceKind kind;
        public VisionConfig config;
        public float eyeHeight;
        public float baseFacingYaw;
        public float currentFacingYaw;
        public float scanArc;
        public float scanPeriod;
        public float scanPhase;
        public bool isEnabled = true;
        public WorldPoint[] occluderBounds; // simplified AABB of walls

        public bool CanSee(WorldPoint targetPos, float targetHeight, out float distance)
        {
            distance = Vector3.Distance(new Vector3(targetPos.x, targetHeight, targetPos.z),
                                        new Vector3(0, eyeHeight, 0)); // simplified
            return distance <= config.range;
        }
    }

    [System.Serializable]
    public class InteractableComponent
    {
        public string id;
        public InteractionKind[] interactions;
        public System.Collections.Generic.Dictionary<string, LevelValue> config = new();
    }

    [System.Serializable]
    public class DoorComponent
    {
        public string id;
        public WorldBox closedBox;
        public DoorHingeSide hingeSide;
        public float openAngleDegrees;
        public bool isOpen;
        public float openProgress; // 0..1
        public float openSpeed;    // degrees per second
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

    [System.Serializable]
    public class SafeComponent
    {
        public string id;
        public bool locked = true;
        public int difficulty;
        public float crackProgress; // 0..1
        public bool isOpen;
        public System.Collections.Generic.List<string> containedLootIds = new();
    }
}