namespace DerClou.Core.Navigation
{
    using DerClou.Core.Data;
    using System.Collections.Generic;

    [System.Serializable]
    public struct NavCell
    {
        public int x, y;
        public bool walkable;
        public float clearance;      // remaining distance to nearest wall/obstacle
        public byte area;            // area type for cost/filters
    }

    [System.Serializable]
    public class NavGrid
    {
        public int width, height;
        public float cellSize;
        public float originX, originZ;
        public NavCell[] cells;

        public int Index(int x, int y) => y * width + x;
        public bool InBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;
        public NavCell Get(int x, int y) => InBounds(x, y) ? cells[Index(x, y)] : default;
        public void Set(int x, int y, NavCell c) { if (InBounds(x, y)) cells[Index(x, y)] = c; }

        // System.MathF, not UnityEngine.Mathf: Core is pure C# by design.
        public CellPoint WorldToCell(WorldPoint wp) => new CellPoint(
            (int)System.MathF.Floor((wp.x - originX) / cellSize),
            (int)System.MathF.Floor((wp.z - originZ) / cellSize));

        public WorldPoint CellToWorld(CellPoint cp) => new WorldPoint(
            originX + (cp.x + 0.5f) * cellSize,
            0,
            originZ + (cp.y + 0.5f) * cellSize);

        /// Rasterizes a blueprint into a walkability grid: floors walkable,
        /// then walls and movement-blocking props carved out. Pure data in,
        /// pure data out — the "2D simulation" half of the project's
        /// simulation/presentation split. Needs `catalog` (not
        /// `PlacedProp.prototype`, which nothing in this codebase ever
        /// actually assigns) to resolve which props block movement.
        public static NavGrid BuildFromBlueprint(LevelBlueprint blueprint, PropCatalog catalog)
        {
            float cellSize = blueprint.metrics.cellSize > 0 ? blueprint.metrics.cellSize : 0.5f;

            float minX = float.MaxValue, maxX = float.MinValue, minZ = float.MaxValue, maxZ = float.MinValue;
            foreach (var f in blueprint.floors)
            {
                float hw = f.width * 0.5f, hd = f.depth * 0.5f;
                minX = System.MathF.Min(minX, f.centerX - hw);
                maxX = System.MathF.Max(maxX, f.centerX + hw);
                minZ = System.MathF.Min(minZ, f.centerZ - hd);
                maxZ = System.MathF.Max(maxZ, f.centerZ + hd);
            }

            int width = System.Math.Max(1, (int)System.MathF.Ceiling((maxX - minX) / cellSize) + 1);
            int height = System.Math.Max(1, (int)System.MathF.Ceiling((maxZ - minZ) / cellSize) + 1);
            var grid = new NavGrid
            {
                width = width,
                height = height,
                cellSize = cellSize,
                originX = minX,
                originZ = minZ,
                cells = new NavCell[width * height]
            };

            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    var world = grid.CellToWorld(new CellPoint(x, y));
                    bool walkable = false;
                    foreach (var f in blueprint.floors)
                    {
                        if (InsideBox(world, f)) { walkable = true; break; }
                    }
                    if (walkable)
                    {
                        foreach (var w in blueprint.walls)
                        {
                            if (InsideBox(world, w)) { walkable = false; break; }
                        }
                    }
                    if (walkable && catalog != null)
                    {
                        foreach (var p in blueprint.props)
                        {
                            var proto = catalog.Get(p.prototypeId);
                            if (proto == null || !proto.blocksMovement) continue;
                            if (InsideBox(world, p.box)) { walkable = false; break; }
                        }
                    }
                    grid.cells[grid.Index(x, y)] = new NavCell
                    {
                        x = x,
                        y = y,
                        walkable = walkable,
                        area = (byte)(walkable ? 0 : 1)
                    };
                }
            }

            return grid;
        }

        // Axis-aligned only (ignores `box.yaw`) — every box in the office
        // test level is axis-aligned already, and getting a rotated-box
        // point test wrong silently produces bad walkability data, which is
        // worse than a documented limitation. Revisit if a level ever
        // authors a rotated floor/wall.
        private static bool InsideBox(WorldPoint p, WorldBox box)
        {
            float hw = box.width * 0.5f, hd = box.depth * 0.5f;
            return p.x >= box.centerX - hw && p.x <= box.centerX + hw
                && p.z >= box.centerZ - hd && p.z <= box.centerZ + hd;
        }
    }

    [System.Serializable]
    public struct NavPolygon
    {
        public int[] vertices;       // indices into vertex pool
        public int[] neighbors;      // adjacent polygon indices (-1 = none)
        public int[] portals;        // portal edge vertex pairs
        public byte area;
        public float clearance;
    }

    [System.Serializable]
    public class BakedNavigationMesh
    {
        public WorldPoint[] vertices;
        public NavPolygon[] polygons;
        public uint contentHash;     // for revision checking

        public bool IsValid => polygons != null && polygons.Length > 0 && contentHash != 0;
    }

    public struct PathRequest
    {
        public int actorId;
        public int requestId;
        public uint worldRevision;
        public WorldPoint start, goal;
        public CharacterProfile profile;
    }

    public struct PathResponse
    {
        public int requestId;
        public bool success;
        public WorldPoint[] waypoints;  // funnel-smoothed path
        public float length;
    }

    public struct NavigationPlanRequest
    {
        public int actorId;
        public int requestId;
        public uint worldRevision;
        public WorldPoint start, goal;
        public CharacterProfile profile;
    }

    public struct NavigationPlanResponse
    {
        public int requestId;
        public bool success;
        public WorldPoint[] corridor;   // polygon corridor
        public WorldPoint[] path;       // funnel-smoothed path
        public float length;
    }
}