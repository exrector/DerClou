namespace DerClou.Core.Data
{
    [System.Serializable]
    public struct WorldPoint { public float x; public float y; public float z; public WorldPoint(float x, float y, float z) { this.x = x; this.y = y; this.z = z; } }

    [System.Serializable]
    public struct CellPoint { public float x; public float y; public CellPoint(float x, float y) { this.x = x; this.y = y; } }

    [System.Serializable]
    public struct WorldBox
    {
        public float centerX, centerZ, width, depth, height, yaw;
        // Most level boxes stand on the floor, so zero remains the authored
        // default. Keeping the lower edge explicitly lets vision represent a
        // doorway lintel (or any elevated occluder) without inventing Unity
        // colliders on the presentation side.
        public float bottomY;
        public string sourceID;
        public float centerY => bottomY + height * 0.5f;
    }

    [System.Serializable]
    public struct LevelMetrics
    {
        public float cellSize;
        public float wallHeight;

        // Explicit constructor, not field initializers: this project compiles
        // at the C# 9 language level (Unity's default), where a struct cannot
        // initialize its own fields inline — that needs C# 10. Default
        // parameter values here keep `new LevelMetrics()` giving the same
        // (0.5, 2.5) defaults the field initializers would have.
        public LevelMetrics(float cellSize = 0.5f, float wallHeight = 2.5f)
        {
            this.cellSize = cellSize;
            this.wallHeight = wallHeight;
        }

        // System.MathF, not UnityEngine.Mathf: Core is pure C# by design.
        public int CellsFromMeters(float m) => (int)System.MathF.Round(m / cellSize);
        public float MetersFromCells(int c) => c * cellSize;
    }

    [System.Serializable]
    public class ActorSpec
    {
        public string id;
        public string prototypeId;       // e.g. "actor.guard"
        public CellPoint position;
        public float yaw;
        // Patrol waypoints in cell coordinates, authored order. Empty/null
        // for actors that don't patrol (the thief, civilians standing still).
        public System.Collections.Generic.List<CellPoint> route;
        public System.Collections.Generic.Dictionary<string, LevelValue> config = new();
        public string appearance => config.TryGetValue("appearance", out var v) && v.type == LevelValue.Type.String ? v.stringValue : null;
    }

    [System.Serializable]
    public class PlacedProp
    {
        public string id;
        public string prototypeId;
        public WorldBox box;
        public float yaw;
        public System.Collections.Generic.Dictionary<string, LevelValue> config = new();
        public PropPrototype prototype;  // resolved at build time
        public CharacterProfile character; // resolved at build time
        public string appearance => config.TryGetValue("appearance", out var v) && v.type == LevelValue.Type.String ? v.stringValue : null;
    }

    [System.Serializable]
    public class LevelBlueprint
    {
        public string id;
        public LevelMetrics metrics = new LevelMetrics();
        public System.Collections.Generic.List<WorldBox> floors = new();
        public System.Collections.Generic.List<WorldBox> walls = new();
        public System.Collections.Generic.List<PlacedProp> props = new();
        public System.Collections.Generic.List<ActorSpec> actors = new();
        public System.Collections.Generic.List<RoomSpec> rooms = new();
        public System.Collections.Generic.List<PortalSpec> portals = new();
    }

    [System.Serializable]
    public struct VisionConfig
    {
        public float range;
        public float fieldOfViewDegrees;
    }

    public enum VisionSourceKind { GuardActor, SecurityCamera, LaserTripwire }

    public static class VisionProfiles
    {
        // Human guards see farther but through a narrower cone; fixed cameras
        // cover a shorter, wider slice. Return the exact config type consumed
        // by solver and presentation — no parallel "profile" representation.
        public static VisionConfig guardActor => new VisionConfig { range = 20f, fieldOfViewDegrees = 28f };
        public static VisionConfig securityCamera => new VisionConfig { range = 14f, fieldOfViewDegrees = 60f };
    }
}
