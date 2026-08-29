# DerClou — Unity Port

This is the active production implementation of the DerClou top-down
heist-planning puzzle game. The Swift/RealityKit implementation remains in the
repository as a frozen behavioral reference; Unity is the shipping target.

Canonical engineering policy: [`../docs/UNITY_FIRST_ARCHITECTURE.md`](../docs/UNITY_FIRST_ARCHITECTURE.md).
Every implementation must pass its Unity Standard Gate before custom engine
infrastructure is written.

## Quick Start

1. Open `UnityPort` in **Unity 6000.5.9f1 / Unity 6.5.9f1**
2. Open `Assets/DerClou/Scenes/SampleScene.unity`
3. Press Play (`GameBootstrap` is already present and builds the greybox level)
4. The thief is selected automatically. Tap/click the floor to add a movement
   action, then press **ВЫПОЛНИТЬ ПЛАН** in the in-game panel.

Planning taps intentionally do not move the actor immediately: they build the
route that is replayed after Execute. The panel shows the queued action count,
failure source/time, Retry and Back to Plan. Keyboard equivalents in Game View:
Enter = Execute, Escape = Back to Plan, R = repeat after a result.

For the diorama view in the Game tab, use horizontal two-finger trackpad scroll
(or Option + left drag/right drag). On iPhone/iPad use a horizontal two-finger
drag. `DerClou > Diorama > Apply Scene View to Game Camera` copies the current
Scene View to Game; the adjacent `Live Sync Scene View to Game` command keeps
them synchronized.

## Architecture Overview

### Core (Pure C#, no Unity dependencies)
```
Assets/DerClou/Core/
├── Data/           # CharacterProfile, PropCatalog, LevelBlueprint, PropPrototype
├── Navigation/     # NavGrid, BakedNavigationMesh, PathRequest/Response
├── Time/           # MissionClock, FixedStepAccumulator
├── Simulation/     # MissionState, actor/guard/door/camera/safe state, VisionSolver
├── Systems/        # Fixed-step movement, patrol, vision, doors, cameras, safes
├── Planning/       # PlanAction, ActorPlan, MissionPlan, IActionDurationProvider
└── Events/         # (to be added)
```

### Gameplay (Unity-specific)
```
Assets/DerClou/Gameplay/
├── Actors/         # ActorView and GuardView (presentation only)
├── Lighting/       # WorldSpotlightView shared by cameras and flashlights
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
| Navigation | Custom grid + baked polygon navmesh | Pure-C# custom grid/A* (gameplay authority) |
| Time | `MissionClock` + `FixedStepAccumulator` | Same classes |
| Camera | `OrthographicCameraComponent` + custom projection | `TacticalCamera` (orthographic, top-down) |
| Animation | RealityKit `AnimationResource` + additive layers | Unity Animator + layers (Base=0, Flashlight=1) |
| Input | Tap on `RealityView` | `InputManager` raycasting |
| Determinism | Fixed-step accumulator | Pure-C# fixed-step simulation driven by `GameController` |

### Character rigs and flashlight contact

Rig families are explicit compatibility boundaries. Epic/UE5 contact clips use
Generic avatars with the same hierarchy and authored prop sockets. Humanoid is
reserved for locomotion and actions where muscle-space retargeting is
acceptable. The current Humanoid flashlight code is legacy and is scheduled
for replacement by `CharacterRigProfile` plus Animation Rigging; it is not the
production asset workflow. See the canonical architecture document.

### Importing Assets

Place your USDZ/FBX models in:
```
Assets/DerClou/Resources/Characters/
  <empty until a character passes visual, rig and live-animation acceptance>

Assets/DerClou/Resources/Props/
  Door.fbx
  Camera.fbx
  Safe.fbx
  ...
```

The `LevelBuilder` loads them via `Resources.Load<GameObject>($"Characters/{assetKey}")`.

### Navigation

The custom pure-C# `NavGrid` + A* pathfinder is the current gameplay authority
for both player actors and guards. Do not replace it with `NavMeshAgent` local
avoidance as authoritative simulation; Unity physics/navigation may only be
used for presentation or debug verification.

### Deterministic Execution

- `MissionClock` drives all timing
- `FixedStepAccumulator` ensures fixed-step simulation
- `PlanAction` durations are computed by `IActionDurationProvider`
- Same plan + same seed = same result
- Guard detection uses pure-C# range/FOV/box occlusion and reports exact
  mission time, source and reason
- Cameras and guard flashlights share one native realtime Unity Spot Light.
  It produces the actual floor spot and URP soft shadows; no procedural cone
  mesh is generated.

### Next Steps

- [ ] Implement `BakedNavigationMesh` baker + funnel algorithm
- [ ] Add the `CharacterRigProfile` + Animation Rigging contact pipeline
- [ ] Build Planning UI (timeline, action queue, scrubber)
- [ ] Add Security dependency graph (Switch → Camera → Laser → Door)
- [x] Implement deterministic guard vision + matching visible occluded cone
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
