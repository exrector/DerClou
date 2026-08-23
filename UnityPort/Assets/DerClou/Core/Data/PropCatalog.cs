namespace DerClou.Core.Data
{
    public enum SurfaceKey { Concrete, Plaster, Wood, Metal, DarkMetal, Glass, Fabric, Emissive }
    public enum InteractionKind { Inspect, Search, Open, Close, Unlock, Lockpick, CrackSafe, Hack, ToggleSwitch, TakeLoot, Extract }
    public enum PropMechanic { HingedDoor, SecurityCamera, Safe }
    public enum ActorRole { Thief, Guard, Civilian }
    public enum PropKind { Scenery, Architecture, Furniture, Security, Container, Loot, Actor, Marker }
    public enum DoorHingeSide { Left, Right }

    [System.Serializable]
    public struct CellSize { public int width; public int depth; public CellSize(int w, int d) { width = w; depth = d; } }

    [System.Serializable]
    public struct MetricSize3D { public float width; public float height; public float depth; public MetricSize3D(float w, float h, float d) { width = w; height = h; depth = d; } }

    [System.Serializable]
    public struct LevelValue
    {
        public enum Type { Bool, Int, Float, String }
        public Type type;
        public bool boolValue;
        public int intValue;
        public float floatValue;
        public string stringValue;

        public static LevelValue Bool(bool v) => new LevelValue { type = Type.Bool, boolValue = v };
        public static LevelValue Int(int v) => new LevelValue { type = Type.Int, intValue = v };
        public static LevelValue Float(float v) => new LevelValue { type = Type.Float, floatValue = v };
        public static LevelValue String(string v) => new LevelValue { type = Type.String, stringValue = v };
    }

    [System.Serializable]
    public struct PlacementContract
    {
        public enum PivotPolicy { BottomCenter, HingeLeft }
        public enum ScalePolicy { PreserveMeters, UniformFit }

        public int rotationSnapDegrees;
        public PivotPolicy pivot;
        public ScalePolicy scalePolicy;
    }

    /// <summary>
    /// Reusable object definition. One prototype authored once, instanced many times.
    /// </summary>
    [System.Serializable]
    public class PropPrototype
    {
        public string id;
        public PropKind kind;
        public CellSize footprint;
        public float height;
        public SurfaceKey surface;
        public bool blocksMovement = true;
        public InteractionKind[] interactions = System.Array.Empty<InteractionKind>();
        public System.Collections.Generic.Dictionary<string, LevelValue> defaults = new();
        public string asset;                    // Addressable key or Resources path
        public ActorRole? actorRole;
        public PropMechanic? mechanic;
        public PlacementContract? placement;

        public PlacementContract PlacementContract =>
            placement ?? new PlacementContract
            {
                rotationSnapDegrees = kind == PropKind.Architecture ? 90 : 15,
                pivot = mechanic == PropMechanic.HingedDoor ? PlacementContract.PivotPolicy.HingeLeft : PlacementContract.PivotPolicy.BottomCenter,
                scalePolicy = kind == PropKind.Actor ? PlacementContract.ScalePolicy.PreserveMeters : PlacementContract.ScalePolicy.UniformFit
            };

        public System.Collections.Generic.Dictionary<string, LevelValue> ResolvedConfig(System.Collections.Generic.Dictionary<string, LevelValue> overrides)
        {
            var merged = new System.Collections.Generic.Dictionary<string, LevelValue>(defaults);
            if (overrides != null) foreach (var kv in overrides) merged[kv.Key] = kv.Value;
            return merged;
        }

        public MetricSize3D CanonicalBounds => new MetricSize3D(footprint.width, height, footprint.depth);
    }

    [System.Serializable]
    public class PropCatalog
    {
        public System.Collections.Generic.List<PropPrototype> prototypes = new();

        public PropPrototype Get(string id) => prototypes.Find(p => p.id == id);

        public static PropCatalog Standard
        {
            get
            {
                var cat = new PropCatalog();
                cat.prototypes.AddRange(new[]
                {
                    // Architecture
                    new PropPrototype { id="door.single", kind=PropKind.Architecture, footprint=new CellSize(1,0), height=2.1f, surface=SurfaceKey.Wood, blocksMovement=false,
                        interactions=new[]{InteractionKind.Open,InteractionKind.Close,InteractionKind.Unlock,InteractionKind.Lockpick},
                        defaults=new(){ {"locked",LevelValue.Bool(false)},{"lockDifficulty",LevelValue.Int(1)},{"open",LevelValue.Bool(false)},{"hingeSide",LevelValue.String("Left")},{"openAngle",LevelValue.Float(90f)},{"openDuration",LevelValue.Float(1f)},{"closeDuration",LevelValue.Float(1f)},{"unlockDuration",LevelValue.Float(0.8f)},{"lockpickDuration",LevelValue.Float(4f)} },
                        mechanic=PropMechanic.HingedDoor },

                    // Scenery
                    new PropPrototype { id="tree.large", kind=PropKind.Scenery, footprint=new CellSize(2,2), height=5.5f, surface=SurfaceKey.Fabric },
                    new PropPrototype { id="tree.small", kind=PropKind.Scenery, footprint=new CellSize(2,2), height=3.4f, surface=SurfaceKey.Fabric },
                    new PropPrototype { id="hedge.block", kind=PropKind.Scenery, footprint=new CellSize(3,1), height=1.1f, surface=SurfaceKey.Fabric },
                    new PropPrototype { id="building.neighbour", kind=PropKind.Scenery, footprint=new CellSize(4,3), height=4.5f, surface=SurfaceKey.Concrete },

                    // Furniture
                    new PropPrototype { id="desk.office", kind=PropKind.Furniture, footprint=new CellSize(2,1), height=0.75f, surface=SurfaceKey.Wood, interactions=new[]{InteractionKind.Search}, defaults=new(){ {"searchDuration",LevelValue.Float(3f)},{"searched",LevelValue.Bool(false)} } },
                    new PropPrototype { id="chair.office", kind=PropKind.Furniture, footprint=new CellSize(1,1), height=1.0f, surface=SurfaceKey.Fabric, interactions=new[]{InteractionKind.Inspect}, defaults=new(){ {"inspectDuration",LevelValue.Float(1f)},{"inspected",LevelValue.Bool(false)} } },
                    new PropPrototype { id="cabinet.filing", kind=PropKind.Furniture, footprint=new CellSize(1,1), height=1.35f, surface=SurfaceKey.Metal, interactions=new[]{InteractionKind.Open,InteractionKind.TakeLoot} },
                    new PropPrototype { id="crate.storage", kind=PropKind.Container, footprint=new CellSize(1,1), height=0.9f, surface=SurfaceKey.Wood, interactions=new[]{InteractionKind.Open,InteractionKind.TakeLoot} },
                    new PropPrototype { id="plant.potted", kind=PropKind.Furniture, footprint=new CellSize(1,1), height=1.2f, surface=SurfaceKey.Fabric },

                    // Security
                    new PropPrototype { id="camera.ceiling", kind=PropKind.Security, footprint=new CellSize(1,1), height=0.25f, surface=SurfaceKey.DarkMetal, blocksMovement=false,
                        defaults=new(){ {"powered",LevelValue.Bool(true)},{"visionSource",LevelValue.String("SecurityCamera")},{"range",LevelValue.Float(8f)},{"fieldOfView",LevelValue.Float(90f)},{"scanArc",LevelValue.Float(90f)},{"scanPeriod",LevelValue.Float(8f)},{"mountHeight",LevelValue.Float(2.4f)} },
                        mechanic=PropMechanic.SecurityCamera },
                    new PropPrototype { id="panel.security", kind=PropKind.Security, footprint=new CellSize(1,1), height=0.45f, surface=SurfaceKey.DarkMetal, blocksMovement=false,
                        interactions=new[]{InteractionKind.Hack,InteractionKind.ToggleSwitch},
                        defaults=new(){ {"difficulty",LevelValue.Int(2)},{"mountHeight",LevelValue.Float(1.3f)},{"hackDuration",LevelValue.Float(6f)},{"toggleSwitchDuration",LevelValue.Float(0.5f)} } },

                    // Containers & Loot
                    new PropPrototype { id="safe.wall", kind=PropKind.Container, footprint=new CellSize(1,1), height=0.6f, surface=SurfaceKey.DarkMetal, interactions=new[]{InteractionKind.CrackSafe,InteractionKind.TakeLoot}, defaults=new(){ {"locked",LevelValue.Bool(true)},{"difficulty",LevelValue.Int(3)},{"crackSafeDuration",LevelValue.Float(20f)} }, mechanic=PropMechanic.Safe },
                    new PropPrototype { id="loot.cash", kind=PropKind.Loot, footprint=new CellSize(1,1), height=0.1f, surface=SurfaceKey.Fabric, blocksMovement=false, interactions=new[]{InteractionKind.TakeLoot}, defaults=new(){ {"value",LevelValue.Int(2500)},{"weight",LevelValue.Float(1.5f)} } },

                    // Actors
                    new PropPrototype { id="actor.thief", kind=PropKind.Actor, footprint=new CellSize(1,1), height=1.75f, surface=SurfaceKey.Fabric, blocksMovement=false, defaults=new(){ {"walkSpeed",LevelValue.Float(1.4f)} }, asset="Thief", actorRole=ActorRole.Thief },
                    new PropPrototype { id="actor.guard", kind=PropKind.Actor, footprint=new CellSize(1,1), height=1.8f, surface=SurfaceKey.Fabric, blocksMovement=false,
                        defaults=new(){ {"walkSpeed",LevelValue.Float(1.2f)},{"turnSpeed",LevelValue.Float(180f)},{"visionSource",LevelValue.String("GuardActor")},{"range",LevelValue.Float(7f)},{"fieldOfView",LevelValue.Float(70f)} },
                        asset="Guard01", actorRole=ActorRole.Guard },
                    new PropPrototype { id="actor.civilian", kind=PropKind.Actor, footprint=new CellSize(1,1), height=1.7f, surface=SurfaceKey.Fabric, blocksMovement=false, defaults=new(){ {"walkSpeed",LevelValue.Float(1.1f)} }, asset="Civilian01", actorRole=ActorRole.Civilian },

                    // Markers
                    new PropPrototype { id="marker.extraction", kind=PropKind.Marker, footprint=new CellSize(1,1), height=0.02f, surface=SurfaceKey.Emissive, blocksMovement=false, interactions=new[]{InteractionKind.Extract} }
                });
                return cat;
            }
        }
    }
}