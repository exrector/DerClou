namespace DerClou.Core.Planning
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
    using DerClou.Core.Systems;

    /// U3 (`docs/U3_PLANNING_LOOP_DESIGN.md`): plumbing only, not detection —
    /// U4 (vision) is what actually reports a guard seeing the thief.
    /// `PlanExecutor` itself only ever raises the one case already in its own
    /// scope: a `MoveTo` that resolves to no path.
    public struct FailureEvent
    {
        public float time;
        public int actorId;
        public string source;
        public string reason;
        public WorldPoint position;
    }

    /// <summary>
    /// Turns a compiled <see cref="MissionPlan"/> into things actually
    /// happening, in mission-clock time, deterministically. Ticked explicitly
    /// from <c>GameController.Update()</c> only during <c>GamePhase.Execution</c>
    /// — unlike the always-live U2 systems (<see cref="SimulationStep"/>),
    /// which keep running underneath regardless of phase and do the actual
    /// continuous work (arrival, door swing, safe crack progress) once an
    /// action here starts it.
    /// </summary>
    public class PlanExecutor
    {
        private List<PlanAction> sortedActions;
        private bool[] fired;

        public FailureEvent? LastFailure { get; private set; }

        public void Begin(MissionPlan plan)
        {
            sortedActions = new List<PlanAction>(plan.AllActionsSortedByTime());
            fired = new bool[sortedActions.Count];
            LastFailure = null;
        }

        public void Tick(MissionState state, float currentTime)
        {
            if (sortedActions == null) return;

            for (int i = 0; i < sortedActions.Count; i++)
            {
                if (fired[i] || sortedActions[i].earliestStart > currentTime) continue;
                fired[i] = true;
                Dispatch(state, sortedActions[i]);
            }
        }

        private void Dispatch(MissionState state, PlanAction action)
        {
            switch (action.type)
            {
                case PlanActionType.MoveTo:
                    ActorMovementSystem.RequestPath(state, action.actorId, action.targetPos);
                    // The one failure case in this milestone's own scope —
                    // everything else (a guard seeing the thief) is U4's.
                    if (state.Actors.TryGetValue(action.actorId, out var moved) && !moved.HasPath)
                    {
                        LastFailure = new FailureEvent
                        {
                            time = state.CurrentTime,
                            actorId = action.actorId,
                            source = "Pathfinding",
                            reason = "NoPath",
                            position = moved.Position
                        };
                    }
                    break;

                case PlanActionType.OpenDoor:
                    // Queued as "toggle" (same as the old click-to-open UX,
                    // docs/U3_PLANNING_LOOP_DESIGN.md) — flips whatever the
                    // door's current simulated state is, not a fixed target.
                    if (state.Doors.TryGetValue(action.targetId, out var d) && !d.isLocked)
                    {
                        DoorSystem.SetOpen(state, action.targetId, !d.isOpen);
                    }
                    break;

                case PlanActionType.Hack:
                case PlanActionType.ToggleSwitch:
                    if (TryGetString(action.parameters, "controlsCameraId", out var camId)
                        && state.Cameras.TryGetValue(camId, out var cam))
                    {
                        cam.powered = !cam.powered;
                        state.Cameras[camId] = cam;
                    }
                    break;

                case PlanActionType.CrackSafe:
                    SafeSystem.StartCracking(state, action.targetId, action.actorId);
                    break;

                case PlanActionType.TakeLoot:
                    bool gated = TryGetString(action.parameters, "requiresSafeId", out var requiredSafeId)
                        && !string.IsNullOrEmpty(requiredSafeId)
                        && state.Safes.TryGetValue(requiredSafeId, out var safe) && !safe.isOpen;
                    if (!gated)
                    {
                        state.HasLoot = true;
                        state.CollectedLootIds.Add(action.targetId);
                    }
                    break;

                case PlanActionType.Extract:
                    if (state.HasLoot) state.MissionComplete = true;
                    break;

                case PlanActionType.Wait:
                default:
                    // Wait's only job is occupying time on the actor's own
                    // track via earliestStart/duration — nothing to dispatch.
                    break;
            }
        }

        private static bool TryGetString(Dictionary<string, LevelValue> parameters, string key, out string value)
        {
            value = null;
            if (parameters == null || !parameters.TryGetValue(key, out var v) || v.type != LevelValue.Type.String)
                return false;
            value = v.stringValue;
            return true;
        }
    }
}
