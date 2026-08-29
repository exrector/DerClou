namespace DerClou.Gameplay.Navigation
{
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using Unity.AI.Navigation;
    using UnityEngine;
    using UnityEngine.AI;

    /// <summary>
    /// Thin U5 adapter over Unity AI Navigation. Unity owns spatial corridor
    /// generation from the scene's real colliders; callers receive a copied
    /// WorldPoint array that can be frozen into deterministic simulation.
    /// No NavMeshAgent is allowed to move a gameplay actor.
    /// </summary>
    public sealed class UnityNavMeshWorld : MonoBehaviour, DerClou.Core.Navigation.ISpatialCorridorProvider
    {
        public NavMeshSurface Surface { get; private set; }
        public int SuccessfulParityLegs { get; private set; }
        public int FailedParityLegs { get; private set; }

        public void Build(LevelBlueprint blueprint)
        {
            Surface = gameObject.GetComponent<NavMeshSurface>()
                ?? gameObject.AddComponent<NavMeshSurface>();
            Surface.collectObjects = CollectObjects.Volume;
            Surface.useGeometry = NavMeshCollectGeometry.PhysicsColliders;
            Surface.layerMask = ~0;

            Bounds bounds = CalculateBounds(blueprint);
            Surface.center = transform.InverseTransformPoint(bounds.center);
            Surface.size = bounds.size;
            Surface.BuildNavMesh();
        }

        public bool TryCalculateFrozenCorridor(
            WorldPoint start,
            WorldPoint destination,
            out WorldPoint[] corridor)
        {
            corridor = System.Array.Empty<WorldPoint>();
            if (!TrySample(start, out var sampledStart)
                || !TrySample(destination, out var sampledDestination)) return false;

            var path = new NavMeshPath();
            if (!NavMesh.CalculatePath(
                    sampledStart, sampledDestination, NavMesh.AllAreas, path)
                || path.status != NavMeshPathStatus.PathComplete
                || path.corners == null || path.corners.Length == 0) return false;

            int first = path.corners.Length > 1
                && (path.corners[0] - sampledStart).sqrMagnitude < 0.01f ? 1 : 0;
            var frozen = new WorldPoint[path.corners.Length - first];
            for (int i = first; i < path.corners.Length; i++)
                frozen[i - first] = new WorldPoint(path.corners[i].x, 0f, path.corners[i].z);
            frozen[^1] = destination;
            corridor = frozen;
            return true;
        }

        public bool TryFindCorridor(
            WorldPoint start,
            WorldPoint destination,
            out WorldPoint[] corridor)
            => TryCalculateFrozenCorridor(start, destination, out corridor);

        public void ValidateAuthoredRoutes(LevelBlueprint blueprint)
        {
            SuccessfulParityLegs = 0;
            FailedParityLegs = 0;
            foreach (var actor in blueprint.actors)
            {
                if (actor.route == null || actor.route.Count < 2) continue;
                for (int i = 0; i < actor.route.Count; i++)
                {
                    var from = CellToWorld(blueprint, actor.route[i]);
                    var to = CellToWorld(blueprint, actor.route[(i + 1) % actor.route.Count]);
                    if (TryCalculateFrozenCorridor(from, to, out _)) SuccessfulParityLegs++;
                    else FailedParityLegs++;
                }
            }

            if (FailedParityLegs == 0)
                Debug.Log($"[U5 NavMesh parity] {SuccessfulParityLegs} authored patrol legs reachable.");
            else
                Debug.LogError($"[U5 NavMesh parity] {FailedParityLegs} patrol legs unreachable; "
                    + $"{SuccessfulParityLegs} reachable.");
        }

        private static bool TrySample(WorldPoint point, out Vector3 sampled)
        {
            var query = new Vector3(point.x, 0f, point.z);
            if (NavMesh.SamplePosition(query, out var hit, 1.25f, NavMesh.AllAreas))
            {
                sampled = hit.position;
                return true;
            }
            sampled = default;
            return false;
        }

        private static WorldPoint CellToWorld(LevelBlueprint blueprint, CellPoint cell)
        {
            // ActorSpec/route coordinates are historical CellPoint values but
            // are authored and consumed as world metres throughout the port.
            return new WorldPoint(cell.x, 0f, cell.y);
        }

        private static Bounds CalculateBounds(LevelBlueprint blueprint)
        {
            bool hasBounds = false;
            float minX = 0f, maxX = 0f, minZ = 0f, maxZ = 0f;
            foreach (var floor in blueprint.floors)
            {
                float halfX = floor.width * 0.5f, halfZ = floor.depth * 0.5f;
                float floorMinX = floor.centerX - halfX, floorMaxX = floor.centerX + halfX;
                float floorMinZ = floor.centerZ - halfZ, floorMaxZ = floor.centerZ + halfZ;
                if (!hasBounds)
                {
                    minX = floorMinX; maxX = floorMaxX;
                    minZ = floorMinZ; maxZ = floorMaxZ;
                    hasBounds = true;
                }
                else
                {
                    minX = Mathf.Min(minX, floorMinX); maxX = Mathf.Max(maxX, floorMaxX);
                    minZ = Mathf.Min(minZ, floorMinZ); maxZ = Mathf.Max(maxZ, floorMaxZ);
                }
            }
            if (!hasBounds) return new Bounds(Vector3.zero, new Vector3(10f, 5f, 10f));
            var center = new Vector3((minX + maxX) * 0.5f, 1.5f, (minZ + maxZ) * 0.5f);
            var size = new Vector3(maxX - minX + 1f, 5f, maxZ - minZ + 1f);
            return new Bounds(center, size);
        }
    }
}
