namespace DerClou.Core.Planning
{
    using DerClou.Core.Data;
    using DerClou.Core.Time;
    using System.Collections.Generic;

    public enum PlanActionType
    {
        MoveTo,
        Align,
        TraversePortal,
        Wait,
        OpenDoor,
        CloseDoor,
        Lockpick,
        Unlock,
        Hack,
        ToggleSwitch,
        CrackSafe,
        TakeLoot,
        Hide,
        Extract,
        DisableAlarm,
        EnableAlarm
    }

    [System.Serializable]
    public struct PlanAction
    {
        public PlanActionType type;
        public int actorId;
        public string targetId;      // door, safe, switch, loot, etc.
        public WorldPoint targetPos; // for MoveTo
        // Immutable trajectory compiled during Planning. Execute installs a
        // copy and never asks NavMesh/A* to reinterpret the same action.
        public WorldPoint[] frozenTrajectory;
        public float duration;       // expected duration
        public float earliestStart;  // mission time when action can start
        // No field initializer: this project compiles at the C# 9 language
        // level (Unity's default), where a struct field initializer needs an
        // explicit constructor and C# 10. Nothing constructs a `PlanAction`
        // yet (planning/execution is still a TODO in GameController), so set
        // this explicitly at each construction site once that lands, the
        // same way `new ActorPlan { actorId = ... }` already does above.
        public System.Collections.Generic.Dictionary<string, LevelValue> parameters;

        public float EndTime => earliestStart + duration;
    }

    [System.Serializable]
    public class ActorPlan
    {
        public int actorId;
        public System.Collections.Generic.List<PlanAction> actions = new();
        public float totalDuration => actions.Count > 0 ? actions[^1].EndTime : 0f;

        public void AddAction(PlanAction action) => actions.Add(action);
        public void Clear() => actions.Clear();
    }

    [System.Serializable]
    public class MissionPlan
    {
        public int planId;
        public System.Collections.Generic.Dictionary<int, ActorPlan> actorPlans = new();
        public float estimatedDuration;

        public ActorPlan GetOrCreate(int actorId)
        {
            if (!actorPlans.TryGetValue(actorId, out var p))
            {
                p = new ActorPlan { actorId = actorId };
                actorPlans[actorId] = p;
            }
            return p;
        }

        public void RecalculateDuration()
        {
            estimatedDuration = 0f;
            foreach (var p in actorPlans.Values)
                if (p.totalDuration > estimatedDuration) estimatedDuration = p.totalDuration;
        }

        public IEnumerable<PlanAction> AllActionsSortedByTime()
        {
            var all = new List<PlanAction>();
            foreach (var p in actorPlans.Values) all.AddRange(p.actions);
            all.Sort((a, b) => a.earliestStart.CompareTo(b.earliestStart));
            return all;
        }
    }

    /// U3 (`docs/U3_PLANNING_LOOP_DESIGN.md`): where the *next* planned
    /// action for one actor starts from — not the actor's live position
    /// (which never moves during Planning), but the end of whatever was
    /// queued last. Without this, three consecutive floor taps would all
    /// plan from the actor's spawn point instead of chaining into a route.
    public struct PlanCursor
    {
        public WorldPoint Position;
        public float Time;
        public float FacingYawDegrees;
        public bool HasFacing;
    }

    public interface IActionDurationProvider
    {
        float GetDuration(PlanActionType type, CharacterProfile profile, System.Collections.Generic.Dictionary<string, LevelValue> parameters);
    }

    public class DefaultDurationProvider : IActionDurationProvider
    {
        public float GetDuration(PlanActionType type, CharacterProfile profile, System.Collections.Generic.Dictionary<string, LevelValue> parameters)
        {
            return type switch
            {
                PlanActionType.MoveTo => 0f, // computed from path distance
                PlanActionType.Align => parameters.TryGetValue("duration", out var ad) && ad.type == LevelValue.Type.Float ? ad.floatValue : 0.2f,
                PlanActionType.TraversePortal => 0f, // computed from slot distance
                PlanActionType.Wait => parameters.TryGetValue("duration", out var d) && d.type == LevelValue.Type.Float ? d.floatValue : 1f,
                PlanActionType.OpenDoor => parameters.TryGetValue("openDuration", out var od) && od.type == LevelValue.Type.Float ? od.floatValue : 1f,
                PlanActionType.CloseDoor => parameters.TryGetValue("closeDuration", out var cd) && cd.type == LevelValue.Type.Float ? cd.floatValue : 1f,
                PlanActionType.Lockpick => parameters.TryGetValue("lockpickDuration", out var ld) && ld.type == LevelValue.Type.Float ? ld.floatValue : 4f,
                PlanActionType.Unlock => parameters.TryGetValue("unlockDuration", out var ud) && ud.type == LevelValue.Type.Float ? ud.floatValue : 0.8f,
                PlanActionType.Hack => parameters.TryGetValue("hackDuration", out var hd) && hd.type == LevelValue.Type.Float ? hd.floatValue : 6f,
                PlanActionType.ToggleSwitch => parameters.TryGetValue("toggleSwitchDuration", out var td) && td.type == LevelValue.Type.Float ? td.floatValue : 0.5f,
                PlanActionType.CrackSafe => parameters.TryGetValue("crackSafeDuration", out var sd) && sd.type == LevelValue.Type.Float ? sd.floatValue : 20f,
                PlanActionType.TakeLoot => 0.5f,
                PlanActionType.Extract => 0.5f,
                PlanActionType.Hide => 0.5f,
                _ => 1f
            };
        }
    }
}
