# DerClou — Unity Port

This is a complete Unity port of the DerClou top-down heist-planning puzzle game.
All game design, architecture, and data structures are ported from the original Swift/RealityKit implementation.

## Quick Start

1. Open `UnityPort` in **Unity 2022.3 LTS** or newer
2. Open the sample scene: `Assets/DerClou/Scenes/SampleScene.unity` (create one if missing)
3. Add a `GameBootstrap` component to an empty GameObject in the scene
4. Press Play

## Architecture Overview

### Core (Pure C#, no Unity dependencies)
```
Assets/DerClou/Core/
├── Data/           # CharacterProfile, PropCatalog, LevelBlueprint, PropPrototype
├── Navigation/     # NavGrid, BakedNavigationMesh, PathRequest/Response
├── Time/           # MissionClock, FixedStepAccumulator
├── Simulation/     # PatrolRoute, GuardComponent, VisionComponent, DoorComponent, etc.
├── Planning/       # PlanAction, ActorPlan, MissionPlan, IActionDurationProvider
└── Events/         # (to be added)
```

### Gameplay (Unity-specific)
```
Assets/DerClou/Gameplay/
├── Actors/         # ActorEntity, GuardPatrolSystem
├── Props/          # Interactable, Door, SecurityCamera, Safe
├── Level/          # LevelBuilder, Level01Builder
├── Camera/         # TacticalCamera (orthographic top-down)
├── Input/          # InputManager (tap-to-move, selection)
├── UI/             # (to be added: planning timeline, HUD)
└── GameController  # Main coordinator
```

### Key Design Decisions (ported from Swift)

| System | Swift (RealityKit) | Unity Port |
|--------|-------------------|------------|
| Navigation | Custom grid + baked polygon navmesh | Unity NavMesh + custom `BakedNavigationMesh` data |
| Time | `MissionClock` + `FixedStepAccumulator` | Same classes |
| Camera | `OrthographicCameraComponent` + custom projection | `TacticalCamera` (orthographic, top-down) |
| Animation | RealityKit `AnimationResource` + additive layers | Unity Animator + layers (Base=0, Flashlight=1) |
| Input | Tap on `RealityView` | `InputManager` raycasting |
| Determinism | Fixed-step accumulator | Same + Unity `FixedUpdate` |

### Guard with Flashlight (Guard03)

The third guard (`appearance: "guard03"`) automatically gets a flashlight pose:

```csharp
// In LevelBuilder.SpawnActor():
if (proto.actorRole == ActorRole.Guard && spec.appearance == "guard03")
{
    actor.carryFlashlight = true;
    actor.flashlightPrefab = flashlightPrefab;
    actor.rightHandBone = animator.GetBoneTransform(HumanBodyBones.RightHand);
    actor.ApplyFlashlightPose();
}
```

**Requirements for the flashlight to work:**
1. Guard model uses **Humanoid rig** (Unity will map bones automatically)
2. `flashlightPrefab` assigned in `LevelBuilder` (simple Point Light + mesh)
3. Animator has an **Additive** clip named `"FlashlightPose"` on **Layer 1** targeting only:
   - RightShoulder
   - RightArm
   - RightForeArm
   - RightHand
4. The clip should hold a constant pose (`from == to`) and be marked **Additive** in import settings

### Importing Assets

Place your USDZ/FBX models in:
```
Assets/DerClou/Resources/Characters/
  Thief.fbx
  Guard01.fbx
  Guard02.fbx
  Guard03.fbx
  Civilian01.fbx

Assets/DerClou/Resources/Props/
  Door.fbx
  Camera.fbx
  Safe.fbx
  ...
```

The `LevelBuilder` loads them via `Resources.Load<GameObject>($"Characters/{assetKey}")`.

### Navigation

Two options:
1. **Unity NavMesh** (quick): Bake at runtime via `NavMeshBuilder` or in Editor
2. **Custom Baked Mesh** (production): Implement `BakedNavigationMesh` baker (Recast/Detour or custom) that outputs polygon corridor + funnel paths

The `GuardPatrolSystem` currently uses `NavMeshAgent` for simplicity. Swap to custom path-following when ready.

### Deterministic Execution

- `MissionClock` drives all timing
- `FixedStepAccumulator` ensures fixed-step simulation
- `PlanAction` durations are computed by `IActionDurationProvider`
- Same plan + same seed = same result

### Next Steps

- [ ] Implement `BakedNavigationMesh` baker + funnel algorithm
- [ ] Add `SkeletalPosesComponent`-style procedural upper-body system
- [ ] Build Planning UI (timeline, action queue, scrubber)
- [ ] Add Security dependency graph (Switch → Camera → Laser → Door)
- [ ] Implement `VisionComponent` with proper occlusion (raycast against walls)
- [ ] Add multi-actor synchronization in plan execution
- [ ] Build HUD: mission timer, alert state, actor portraits

## Porting Notes

| Swift Feature | Unity Equivalent |
|---------------|------------------|
| `@MainActor` | MonoBehaviour / main thread |
| `struct` with value semantics | `struct` (same) |
| `enum` with associated values | `enum` + `class` for payload |
| `Protocol` | `interface` |
| `@discardableResult` | just ignore return |
| `AnimationResource.generate()` | `AnimationClip` (imported) |
| `RealityKit Entity` | `GameObject` + components |
| `Async/await` | `UniTask` or coroutines |

## License

Same as parent project.