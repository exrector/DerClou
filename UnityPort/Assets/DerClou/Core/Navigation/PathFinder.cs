namespace DerClou.Core.Navigation
{
    using DerClou.Core.Data;
    using System;
    using System.Collections.Generic;

    /// <summary>
    /// Grid A* over <see cref="NavGrid"/>. This is the "2D simulation" half of
    /// the 2D-simulation/3D-presentation split: pure C#, no Unity types, no
    /// dependency on any rendering/physics engine — the same shape the Swift
    /// version's own grid pathfinder had. Presentation code (Unity's
    /// <c>ActorEntity</c>) only ever sees the returned waypoints; it never
    /// needs to know the grid exists.
    /// </summary>
    public static class PathFinder
    {
        private static readonly (int dx, int dy, float cost)[] Neighbors =
        {
            (1, 0, 1f), (-1, 0, 1f), (0, 1, 1f), (0, -1, 1f),
            (1, 1, 1.41421356f), (1, -1, 1.41421356f), (-1, 1, 1.41421356f), (-1, -1, 1.41421356f)
        };

        /// Deterministic: same grid + same start/goal always returns the same
        /// waypoints. Returns an empty array if no path exists.
        public static WorldPoint[] FindPath(NavGrid grid, WorldPoint start, WorldPoint goal)
        {
            var startCell = NearestWalkable(grid, grid.WorldToCell(start));
            var goalCell = NearestWalkable(grid, grid.WorldToCell(goal));
            if (startCell == null || goalCell == null) return Array.Empty<WorldPoint>();

            var (sx, sy) = startCell.Value;
            var (gx, gy) = goalCell.Value;

            // Every waypoint below comes from `CellToWorld`, which snaps to
            // a cell *center* — up to half a cell short of the point that
            // was actually requested. That is fine for an intermediate
            // waypoint, but as the *final* one it silently redefined
            // "arrived" as "within half a cell", which was smaller than
            // `GuardPatrolSystem`'s own 0.2 m arrival tolerance whenever a
            // patrol leg landed the guard in the same or an adjacent cell as
            // its target: the guard would walk up to the cell center, call
            // that arrival, and never close the last few centimeters its own
            // patrol logic was still waiting for — freezing forever one
            // node into the route, deterministically, every run. Use the
            // exact requested goal as the last waypoint whenever the goal
            // cell itself was walkable (not silently snapped to a different
            // walkable cell nearby).
            var requestedGoalCell = grid.WorldToCell(goal);
            bool goalCellIsExact = (int)requestedGoalCell.x == gx && (int)requestedGoalCell.y == gy;
            var finalWaypoint = goalCellIsExact ? goal : grid.CellToWorld(new CellPoint(gx, gy));

            if (sx == gx && sy == gy) return new[] { finalWaypoint };

            var gScore = new Dictionary<(int, int), float> { [(sx, sy)] = 0f };
            var cameFrom = new Dictionary<(int, int), (int, int)>();
            var open = new List<(int, int)> { (sx, sy) };
            var openF = new Dictionary<(int, int), float> { [(sx, sy)] = Heuristic(sx, sy, gx, gy) };
            var closed = new HashSet<(int, int)>();

            while (open.Count > 0)
            {
                int bestIndex = 0;
                for (int i = 1; i < open.Count; i++)
                    if (openF[open[i]] < openF[open[bestIndex]]) bestIndex = i;
                var current = open[bestIndex];
                open.RemoveAt(bestIndex);

                if (current == (gx, gy))
                {
                    var cells = ReconstructPath(grid, cameFrom, current);
                    cells[cells.Count - 1] = finalWaypoint;
                    return Simplify(grid, cells);
                }

                closed.Add(current);

                foreach (var (dx, dy, stepCost) in Neighbors)
                {
                    int nx = current.Item1 + dx, ny = current.Item2 + dy;
                    if (!grid.InBounds(nx, ny) || !grid.Get(nx, ny).walkable) continue;
                    if (dx != 0 && dy != 0)
                    {
                        // Disallow cutting a diagonal across a solid corner —
                        // both orthogonal cells adjacent to the diagonal step
                        // must also be walkable, or the path would visually
                        // clip through a wall corner.
                        if (!grid.Get(current.Item1 + dx, current.Item2).walkable) continue;
                        if (!grid.Get(current.Item1, current.Item2 + dy).walkable) continue;
                    }
                    var neighbor = (nx, ny);
                    if (closed.Contains(neighbor)) continue;

                    float tentativeG = gScore[current] + stepCost;
                    if (!gScore.TryGetValue(neighbor, out var existingG) || tentativeG < existingG)
                    {
                        cameFrom[neighbor] = current;
                        gScore[neighbor] = tentativeG;
                        openF[neighbor] = tentativeG + Heuristic(nx, ny, gx, gy);
                        if (!open.Contains(neighbor)) open.Add(neighbor);
                    }
                }
            }

            return Array.Empty<WorldPoint>();
        }

        private static float Heuristic(int x, int y, int gx, int gy)
        {
            int dx = Math.Abs(x - gx), dy = Math.Abs(y - gy);
            int diag = Math.Min(dx, dy), straight = Math.Abs(dx - dy);
            return diag * 1.41421356f + straight;
        }

        private static List<WorldPoint> ReconstructPath(
            NavGrid grid, Dictionary<(int, int), (int, int)> cameFrom, (int, int) goal)
        {
            var cells = new List<(int, int)> { goal };
            var current = goal;
            while (cameFrom.TryGetValue(current, out var parent))
            {
                cells.Add(parent);
                current = parent;
            }
            cells.Reverse();

            var path = new List<WorldPoint>(cells.Count);
            foreach (var (x, y) in cells) path.Add(grid.CellToWorld(new CellPoint(x, y)));
            return path;
        }

        /// Collapses runs of cells that a straight line can cross without
        /// leaving walkable ground — otherwise every path looks like a
        /// staircase of single-cell steps, since raw A* only ever moves
        /// between adjacent cells.
        private static WorldPoint[] Simplify(NavGrid grid, List<WorldPoint> path)
        {
            if (path.Count <= 2) return path.ToArray();

            var result = new List<WorldPoint> { path[0] };
            int anchor = 0;
            for (int i = 1; i < path.Count; i++)
            {
                if (i == path.Count - 1)
                {
                    result.Add(path[i]);
                    break;
                }
                if (!HasLineOfSight(grid, path[anchor], path[i + 1]))
                {
                    result.Add(path[i]);
                    anchor = i;
                }
            }
            return result.ToArray();
        }

        private static (int, int)? NearestWalkable(NavGrid grid, CellPoint cell)
        {
            int cx = (int)cell.x, cy = (int)cell.y;
            if (grid.InBounds(cx, cy) && grid.Get(cx, cy).walkable) return (cx, cy);

            // Spiral outward — handles a click one cell into a wall, or an
            // actor standing exactly on a boundary cell, without failing the
            // whole path request.
            for (int radius = 1; radius <= 8; radius++)
            {
                for (int dx = -radius; dx <= radius; dx++)
                for (int dy = -radius; dy <= radius; dy++)
                {
                    if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != radius) continue;
                    int nx = cx + dx, ny = cy + dy;
                    if (grid.InBounds(nx, ny) && grid.Get(nx, ny).walkable) return (nx, ny);
                }
            }
            return null;
        }

        public static bool HasLineOfSight(NavGrid grid, WorldPoint from, WorldPoint to)
        {
            float dist = MathF.Sqrt((to.x - from.x) * (to.x - from.x) + (to.z - from.z) * (to.z - from.z));
            int samples = Math.Max(2, (int)MathF.Ceiling(dist / (grid.cellSize * 0.5f)));
            for (int i = 0; i <= samples; i++)
            {
                float t = (float)i / samples;
                var p = new WorldPoint(from.x + (to.x - from.x) * t, 0, from.z + (to.z - from.z) * t);
                var cell = grid.WorldToCell(p);
                if (!grid.InBounds((int)cell.x, (int)cell.y) || !grid.Get((int)cell.x, (int)cell.y).walkable)
                    return false;
            }
            return true;
        }
    }
}
