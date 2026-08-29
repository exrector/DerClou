namespace DerClou.Core.Navigation
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;

    public struct RoomRoute
    {
        public string[] roomIds;
        public string[] portalIds;
        public string[] requiredDoorIds;
        public float cost;
        public bool IsValid => roomIds != null && roomIds.Length > 0;
    }

    /// Stable room-level graph above the local navigation grid. It answers
    /// which portals a goal needs; U6 will compile those portal requirements
    /// into open/unlock/traverse actions.
    public sealed class RoomPortalGraph
    {
        private readonly List<RoomSpec> rooms = new();
        private readonly List<PortalSpec> portals = new();
        private readonly Dictionary<string, uint> portalRevisions = new();

        public IReadOnlyList<RoomSpec> Rooms => rooms;
        public IReadOnlyList<PortalSpec> Portals => portals;

        public static RoomPortalGraph Build(LevelBlueprint blueprint)
        {
            var graph = new RoomPortalGraph();
            if (blueprint == null) return graph;
            graph.rooms.AddRange(blueprint.rooms);
            graph.portals.AddRange(blueprint.portals);
            graph.rooms.Sort((a, b) => string.CompareOrdinal(a.id, b.id));
            graph.portals.Sort((a, b) => string.CompareOrdinal(a.id, b.id));
            foreach (var portal in graph.portals) graph.portalRevisions[portal.id] = 0;
            return graph;
        }

        public string FindRoom(WorldPoint point)
        {
            foreach (var room in rooms)
            {
                var b = room.bounds;
                if (point.x >= b.centerX - b.width * 0.5f
                    && point.x <= b.centerX + b.width * 0.5f
                    && point.z >= b.centerZ - b.depth * 0.5f
                    && point.z <= b.centerZ + b.depth * 0.5f) return room.id;
            }
            return null;
        }

        public uint GetPortalRevision(string portalId) =>
            portalId != null && portalRevisions.TryGetValue(portalId, out uint revision) ? revision : 0;

        public bool TryGetPortal(string portalId, out PortalSpec portal)
        {
            foreach (var candidate in portals)
            {
                if (candidate.id != portalId) continue;
                portal = candidate;
                return true;
            }
            portal = default;
            return false;
        }

        public bool PublishDoorChange(string doorId)
        {
            bool changed = false;
            foreach (var portal in portals)
            {
                if (portal.doorId != doorId) continue;
                portalRevisions[portal.id] = GetPortalRevision(portal.id) + 1;
                changed = true;
            }
            return changed;
        }

        public bool TryFindRoute(
            WorldPoint start,
            WorldPoint goal,
            IReadOnlyDictionary<string, DoorState> doors,
            bool allowOperableClosedDoors,
            out RoomRoute route)
        {
            route = default;
            string startRoom = FindRoom(start);
            string goalRoom = FindRoom(goal);
            if (startRoom == null || goalRoom == null) return false;
            if (startRoom == goalRoom)
            {
                route = new RoomRoute
                {
                    roomIds = new[] { startRoom },
                    portalIds = Array.Empty<string>(),
                    requiredDoorIds = Array.Empty<string>(),
                    cost = 0f
                };
                return true;
            }

            var open = new List<string> { startRoom };
            var costs = new Dictionary<string, float> { [startRoom] = 0f };
            var previousRoom = new Dictionary<string, string>();
            var previousPortal = new Dictionary<string, PortalSpec>();

            while (open.Count > 0)
            {
                int bestIndex = 0;
                for (int i = 1; i < open.Count; i++)
                {
                    float candidate = costs[open[i]], best = costs[open[bestIndex]];
                    if (candidate < best - 0.0001f
                        || (MathF.Abs(candidate - best) <= 0.0001f
                            && string.CompareOrdinal(open[i], open[bestIndex]) < 0)) bestIndex = i;
                }
                string room = open[bestIndex];
                open.RemoveAt(bestIndex);
                if (room == goalRoom) break;

                foreach (var portal in portals)
                {
                    string next = portal.roomAId == room ? portal.roomBId
                        : portal.roomBId == room ? portal.roomAId : null;
                    if (next == null) continue;
                    bool requiresDoor = !string.IsNullOrEmpty(portal.doorId);
                    if (requiresDoor && doors != null && doors.TryGetValue(portal.doorId, out var door)
                        && !door.isOpen && (!allowOperableClosedDoors || door.isLocked)) continue;

                    float edgeCost = portal.baseCost > 0f ? portal.baseCost : 1f;
                    float nextCost = costs[room] + edgeCost;
                    if (costs.TryGetValue(next, out float oldCost) && oldCost <= nextCost + 0.0001f) continue;
                    costs[next] = nextCost;
                    previousRoom[next] = room;
                    previousPortal[next] = portal;
                    if (!open.Contains(next)) open.Add(next);
                }
            }

            if (!costs.TryGetValue(goalRoom, out float total)) return false;
            var reverseRooms = new List<string> { goalRoom };
            var reversePortals = new List<string>();
            var reverseDoors = new List<string>();
            string cursor = goalRoom;
            while (cursor != startRoom)
            {
                var portal = previousPortal[cursor];
                reversePortals.Add(portal.id);
                if (!string.IsNullOrEmpty(portal.doorId)) reverseDoors.Add(portal.doorId);
                cursor = previousRoom[cursor];
                reverseRooms.Add(cursor);
            }
            reverseRooms.Reverse();
            reversePortals.Reverse();
            reverseDoors.Reverse();
            route = new RoomRoute
            {
                roomIds = reverseRooms.ToArray(),
                portalIds = reversePortals.ToArray(),
                requiredDoorIds = reverseDoors.ToArray(),
                cost = total
            };
            return true;
        }

        public RoomPortalGraph Clone()
        {
            var clone = new RoomPortalGraph();
            clone.rooms.AddRange(rooms);
            clone.portals.AddRange(portals);
            foreach (var pair in portalRevisions) clone.portalRevisions[pair.Key] = pair.Value;
            return clone;
        }
    }

    public struct SpatialFootprint
    {
        public string id;
        public WorldBox bounds;
        public bool blocksMovement;
        public bool blocksVision;
    }

    /// Allocation-free-at-query spatial broad phase for nearby world facts.
    public sealed class SpatialHash2D
    {
        private readonly float cellSize;
        private readonly Dictionary<long, List<SpatialFootprint>> buckets = new();
        private readonly HashSet<string> querySeen = new();

        public SpatialHash2D(float cellSize = 2f) => this.cellSize = MathF.Max(0.25f, cellSize);

        public void Clear() => buckets.Clear();

        public void Insert(SpatialFootprint footprint)
        {
            Bounds(footprint.bounds, out int minX, out int maxX, out int minZ, out int maxZ);
            for (int z = minZ; z <= maxZ; z++)
            for (int x = minX; x <= maxX; x++)
            {
                long key = Key(x, z);
                if (!buckets.TryGetValue(key, out var bucket)) buckets[key] = bucket = new List<SpatialFootprint>();
                bucket.Add(footprint);
            }
        }

        public void Query(WorldBox area, List<SpatialFootprint> results)
        {
            results.Clear();
            Bounds(area, out int minX, out int maxX, out int minZ, out int maxZ);
            querySeen.Clear();
            for (int z = minZ; z <= maxZ; z++)
            for (int x = minX; x <= maxX; x++)
            {
                if (!buckets.TryGetValue(Key(x, z), out var bucket)) continue;
                foreach (var item in bucket)
                    if (querySeen.Add(item.id)) results.Add(item);
            }
            results.Sort((a, b) => string.CompareOrdinal(a.id, b.id));
        }

        private void Bounds(WorldBox box, out int minX, out int maxX, out int minZ, out int maxZ)
        {
            minX = (int)MathF.Floor((box.centerX - box.width * 0.5f) / cellSize);
            maxX = (int)MathF.Floor((box.centerX + box.width * 0.5f) / cellSize);
            minZ = (int)MathF.Floor((box.centerZ - box.depth * 0.5f) / cellSize);
            maxZ = (int)MathF.Floor((box.centerZ + box.depth * 0.5f) / cellSize);
        }

        private static long Key(int x, int z) => ((long)x << 32) ^ (uint)z;
    }

    public sealed class WorldTopology
    {
        public uint revision;
        public RoomPortalGraph rooms;
        public SpatialHash2D spatial;

        public static WorldTopology Build(LevelBlueprint blueprint, PropCatalog catalog)
        {
            var topology = new WorldTopology
            {
                revision = 1,
                rooms = RoomPortalGraph.Build(blueprint),
                spatial = new SpatialHash2D(2f)
            };
            if (blueprint == null) return topology;
            foreach (var wall in blueprint.walls)
                topology.spatial.Insert(new SpatialFootprint { id = wall.sourceID, bounds = wall, blocksMovement = true, blocksVision = true });
            foreach (var prop in blueprint.props)
            {
                var prototype = catalog?.Get(prop.prototypeId);
                if (prototype == null) continue;
                topology.spatial.Insert(new SpatialFootprint
                {
                    id = prop.id,
                    bounds = prop.box,
                    blocksMovement = prototype.blocksMovement,
                    blocksVision = prototype.blocksMovement && prototype.surface != SurfaceKey.Glass
                });
            }
            return topology;
        }

        public void PublishDoorChange(string doorId)
        {
            if (rooms != null && rooms.PublishDoorChange(doorId)) revision++;
        }

        public WorldTopology Clone() => new WorldTopology
        {
            revision = revision,
            rooms = rooms?.Clone(),
            spatial = spatial // immutable after level build; dynamic bodies remain separate
        };
    }
}
