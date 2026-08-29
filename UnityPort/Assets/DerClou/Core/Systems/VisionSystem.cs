namespace DerClou.Core.Systems
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;

    /// Evaluates every enabled watcher against every thief in stable ID order.
    /// The first detection becomes the mission's immutable failure event.
    public static class VisionSystem
    {
        public static void Tick(MissionState state)
        {
            if (state == null) return;

            var sourceIds = state.VisionSourceIdScratch;
            sourceIds.Clear();
            foreach (var id in state.VisionSources.Keys) sourceIds.Add(id);
            sourceIds.Sort();

            // Facing is shared presentation state, not a consequence of
            // detection. Planning mode disables failure checks, but cameras
            // and guards must still carry their current deterministic yaw so
            // the visible cone follows them.
            foreach (int sourceId in sourceIds)
            {
                var source = state.VisionSources[sourceId];
                if (source.kind == VisionSourceKind.GuardActor
                    && state.Actors.TryGetValue(source.actorId, out var actor))
                    source.currentFacingYaw = actor.FacingYawDegrees;
                else if (source.kind == VisionSourceKind.SecurityCamera
                    && state.Cameras.TryGetValue(source.sourceLabel, out var camera))
                    source.currentFacingYaw = camera.currentYaw;
                state.VisionSources[sourceId] = source;
            }

            if (!state.DetectionEnabled || state.MissionComplete || state.Failure.HasValue) return;

            var actorIds = state.ActorIdScratch;
            actorIds.Clear();
            foreach (var id in state.Actors.Keys) actorIds.Add(id);
            actorIds.Sort();

            foreach (int sourceId in sourceIds)
            {
                var source = state.VisionSources[sourceId];
                if (!source.isEnabled) continue;
                WorldPoint observer;
                if (source.kind == VisionSourceKind.GuardActor)
                {
                    if (!state.Actors.TryGetValue(source.actorId, out var observerActor)) continue;
                    observer = new WorldPoint(observerActor.Position.x, 0f, observerActor.Position.z);
                }
                else if (source.kind == VisionSourceKind.SecurityCamera)
                {
                    if (!state.Cameras.TryGetValue(source.sourceLabel, out var camera) || !camera.powered) continue;
                    observer = new WorldPoint(source.fixedPosition.x, 0f, source.fixedPosition.z);
                }
                else continue;

                foreach (int targetId in actorIds)
                {
                    var target = state.Actors[targetId];
                    if (target.Role != ActorRole.Thief || targetId == source.actorId) continue;
                    var targetEye = new WorldPoint(target.Position.x, 0f, target.Position.z);
                    var result = VisionSolver.Evaluate(
                        observer, source.currentFacingYaw, targetEye, source.config, state.VisionOccluders);
                    if (!result.IsVisible) continue;

                    state.Failure = new FailureEvent
                    {
                        time = state.CurrentTime,
                        actorId = targetId,
                        source = string.IsNullOrEmpty(source.sourceLabel) ? sourceId.ToString() : source.sourceLabel,
                        reason = "Seen",
                        position = target.Position
                    };
                    return;
                }
            }
        }
    }
}
