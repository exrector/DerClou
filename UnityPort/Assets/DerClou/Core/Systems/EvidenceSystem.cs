namespace DerClou.Core.Systems
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;

    /// U7 evidence, first slice: a powered-off security camera the guard
    /// can actually see. Reuses VisionSolver — the exact same solver that
    /// decides thief detection — pointed at a static fact instead of the
    /// thief, so "the guard can see it" means the same thing everywhere in
    /// this project. Door/furniture/missing-item evidence are not here yet.
    public static class EvidenceSystem
    {
        public static void Tick(MissionState state)
        {
            if (state == null || state.VisionSources == null) return;

            var sourceIds = state.VisionSourceIdScratch;
            sourceIds.Clear();
            foreach (var id in state.VisionSources.Keys) sourceIds.Add(id);
            sourceIds.Sort();

            foreach (int sourceId in sourceIds)
            {
                var source = state.VisionSources[sourceId];
                if (source.kind != VisionSourceKind.GuardActor || !source.isEnabled) continue;
                if (!state.Guards.TryGetValue(source.actorId, out var guard) || guard.isAlerted) continue;
                if (!state.Actors.TryGetValue(source.actorId, out var observerActor)) continue;
                var observer = new WorldPoint(observerActor.Position.x, 0f, observerActor.Position.z);

                foreach (int candidateId in sourceIds)
                {
                    var candidate = state.VisionSources[candidateId];
                    if (candidate.kind != VisionSourceKind.SecurityCamera) continue;
                    if (!state.Cameras.TryGetValue(candidate.sourceLabel, out var camera) || camera.powered) continue;

                    var target = new WorldPoint(candidate.fixedPosition.x, 0f, candidate.fixedPosition.z);
                    var result = VisionSolver.Evaluate(
                        observer, source.currentFacingYaw, target, source.config, state.VisionOccluders);
                    if (!result.IsVisible) continue;

                    StimulusSystem.TriggerInvestigate(state, source.actorId, target);
                    break; // this guard is now busy; move to the next
                }
            }
        }
    }
}
