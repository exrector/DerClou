# DerClou: Unity-first production architecture

Status: canonical engineering policy  
Updated: 2026-08-28  
Editor: Unity 6000.5.9f1

This document is the authority for choosing Unity systems, packages and custom
code. Older Swift/RealityKit notes are historical reference only. If another
document contradicts this one for the Unity port, this document wins.

## 1. Standard Gate: mandatory before implementation

Every feature, bug fix and refactor must pass this sequence before custom code
is written:

1. Check the built-in Unity component or API in the project's current editor.
2. Check an official released Unity package already installed in the project.
3. If absent, check the current official Unity package registry and its manual.
4. Reproduce the intended behavior in an isolated live Game-view fixture.
5. Integrate the standard feature through a thin DerClou adapter.
6. Write custom infrastructure only for deterministic DerClou rules or after
   documenting the missing standard capability.

Compilation and EditMode tests are not visual acceptance. Camera motion,
animation contacts, light, shadows, UI input and navigation must also be
verified in a foreground Game view. Performance changes require profiler data.

## 2. Architectural boundary

DerClou is a deterministic 2D simulation presented as a 3D diorama.

```text
Authoring assets and Unity scene
              |
              v
     thin Unity adapters/views
              |
              v
pure C# fixed-step mission simulation
              |
              v
recorded state -> 3D presentation
```

The pure C# layer owns anything that must replay bit-for-bit: mission clock,
plans, action timing, actor state, patrol phase, alarms, evidence, perception
results, priorities and reservations. Unity owns rendering, asset import,
animation evaluation, camera composition, physical light/shadows, input
devices, NavMesh geometry authoring and editor tooling.

Unity `Transform`, physics contacts, `NavMeshAgent` timing and rendered lights
must never become hidden authorities for the deterministic mission result.

## 3. System ownership map

| Concern | Standard Unity owner | DerClou owner / adapter |
|---|---|---|
| Global walkable corridor | AI Navigation: `NavMeshSurface`, `NavMeshObstacle`, `NavMesh.CalculatePath` | Copy corners into an immutable corridor at a simulation decision point |
| Actor timing and replay | Unity PlayerLoop only calls the simulation | `MissionClock`, `FixedStepAccumulator`, plans and snapshots are authoritative |
| Dynamic topology | AI Navigation geometry and obstacle state | Local topology revision events; recompute only affected committed routes |
| Actor/actor priority | No nondeterministic runtime authority | Deterministic reservations and right-of-way in Core |
| Locomotion presentation | Animator Controller, Blend Trees, transitions | Speed/turn parameters copied from simulation state |
| Hands, feet, look and prop contact | Animation Rigging constraints | Rig-family profile, targets and weights; never ad-hoc world-space bone edits |
| Contact-pose authoring | Animation Rigging Bidirectional Motion Transfer, Animation Window, Timeline | Acceptance scene, then bake/export through Recorder + FBX Exporter when a reusable clip is required |
| Tactical camera | Cinemachine 3 camera + Brain + confinement/composition | Thin touch/joystick adapter; camera state never enters mission simulation |
| Player/UI input | Input System action asset + action maps + `InputSystemUIInputModule` | Convert actions into planning commands or presentation camera commands |
| Physical light/shadow | URP realtime Spot Light and shadow maps | Deterministic 2D perception solver remains separate and visible in technical overlay |
| Level/prop authoring | Scene/prefab workflow and ScriptableObject assets | Convert authored data once into immutable Core DTOs |
| Asset loading | Serialized prefab references now; Addressables only when content scale proves the need | Stable asset IDs in deterministic data, never asset paths as game rules |
| Profiling | Unity Profiler, Memory Profiler, Profile Analyzer | Frame, allocation and battery budgets with recorded baselines |
| Tests | Test Framework + Performance Testing | EditMode math, PlayMode live fixtures, deterministic replay and visual acceptance |

## 4. Character and animation standard

There is no universal animation compatibility merely because two assets came
from the Unity Asset Store. Compatibility is defined by rig family, hierarchy,
bindings, root-motion convention and the required contact precision.

### 4.1 Epic / UE5 Generic family

Use for VanillaLoop flashlight and other exact contact animations:

- character and animation must have the same Epic/UE5 transform hierarchy;
- character: `Generic / Create From This Model`;
- animation-only FBX: `Generic / Copy From Other Avatar` using that character;
- preserve finger, IK and weapon/socket tracks;
- attach the prop to the authored weapon/socket transform when one exists;
- use Animation Rigging only for a deliberate correction layer, not to repair
  an incompatible skeleton silently.

Unity permits a Generic Avatar to be reused only when the files use the same
bone structure. Therefore a Mixamo character is not a valid target for an
Epic contact clip merely because both depict humans.

### 4.2 Humanoid family

Use Humanoid for locomotion and broad reusable actions where muscle-space
retargeting is acceptable. It is not the default for exact hand-to-prop
contacts. Humanoid-specific APIs such as `HumanBodyBones` must live behind a
`HumanoidRigAdapter`; gameplay and prop code must not call them directly.

### 4.3 Common runtime contract

Every accepted character prefab exposes a `CharacterRigProfile`:

- rig family and compatible animation library ID;
- root and motion-root transforms;
- left/right hand and foot targets;
- prop sockets (`flashlight`, `tool`, `weapon_r`, etc.);
- optional look/aim target;
- calibrated model forward axis and scale;
- locomotion controller and contact-rig prefab.

`ActorView` consumes this profile. It does not guess bones by name, change the
rig type, generate a socket from screenshots, or modify the source FBX.

### 4.4 Acceptance gate

A character is not production-ready until the same prefab passes, in Play
Mode:

1. idle, walk, start, stop, left/right turn and 180-degree turn;
2. root-motion/in-place convention without foot sliding;
3. flashlight pose without the prop;
4. flashlight attached to the declared socket;
5. grip and arm contact over the full clip, not one frame;
6. walk/turn plus upper-body action blend;
7. materials, scale, silhouette and deformation review.

The current `HumanBodyBones` flashlight path in `ActorView` and the Humanoid
gallery are legacy code and must not be treated as the production Generic/Epic
pipeline.

## 5. Package policy

### Installed and mandatory now

- Universal RP 17.5.0: rendering, realtime spotlights and shadows.
- AI Navigation 2.0.14: NavMesh authoring and corridor queries.
- Animation Rigging 1.4.1: IK/contact/aim correction and motion transfer.
- Cinemachine 3.1.7: tactical camera composition and constraints.
- Input System 1.20.0: actions, touch, pointer and UI routing.
- FBX Exporter 5.1.6: FBX round-trip/export.
- Test Framework and Performance Testing: deterministic and performance tests.

### Added to the project baseline

- Recorder 5.1.7: record/bake evaluated Play Mode or Timeline animation before
  FBX export.
- Memory Profiler 1.1.12: memory snapshots and retained-object investigation.
- Profile Analyzer 1.4.0: compare captures and verify optimization claims.

### Deferred until a measured need

- Addressables: add before a large level/character library or remote content,
  not as an early abstraction.
- Behavior: optional authoring for non-authoritative high-level decisions; it
  must not replace the deterministic mission state machine.
- Splines: use only for authored cinematic/presentation paths. Actor gameplay
  paths continue to come from navigation plus deterministic smoothing.
- ProBuilder: unnecessary while UModeler X and the current greybox pipeline
  cover level authoring.
- DOTS/Burst: introduce only after profiling shows a real CPU bottleneck.

## 6. Confirmed project gaps

1. `ActorView` rejects Generic characters and directly requests
   `HumanBodyBones`; this contradicts the chosen Epic contact-animation path.
2. `LevelBuilder` still searches for `*ControllerHumanoid` and Avatar assets in
   `Resources`, so asset selection and rig policy are coupled to runtime code.
3. Animation Rigging is installed but no production `RigBuilder`/constraint
   pipeline is integrated.
4. Cinemachine is installed but `TacticalCamera` reimplements composition,
   orbit, zoom and bounds directly.
5. Input System is installed but the project has no canonical `.inputactions`
   asset; several runtime actions/UI objects are constructed in code.
6. Production HUD/dev tools still contain `OnGUI`.
7. Most validation is deterministic/EditMode. It does not prove visual contact,
   camera behavior, shadows or uninterrupted live movement.
8. Level and prop configuration is heavily code-generated instead of authored
   as reusable assets that compile into Core DTOs.

## 7. Migration order

### A. Character and Animation Foundation — immediate

1. Create `CharacterRigProfile` and `ICharacterRigAdapter`.
2. Add `GenericEpicRigAdapter` and isolate the legacy Humanoid adapter.
3. Create one Animation Rigging workbench scene with `RigBuilder`, Two Bone IK,
   hand orientation, optional finger/socket targets and bidirectional transfer.
4. Build an Epic flashlight acceptance fixture from the unchanged source clip.
5. Record the evaluated correction only when a reusable baked clip is needed.
6. Replace `ActorView.ConfigureFlashlight` bone guessing with the accepted
   profile/socket contract.

### B. Camera and Input Foundation

1. Put Cinemachine Brain on the single render camera.
2. Express the diorama camera as a Cinemachine camera and confinement profile.
3. Keep only a thin input adapter for orbit/peek/top reset.
4. Move touch, pointer, UI and camera controls into one `.inputactions` asset.

### C. Navigation Foundation

1. Keep AI Navigation as global geometry/corridor provider.
2. Keep Core as timing, reservation and priority authority.
3. Make topology changes event-driven and spatially scoped.
4. Add live fixtures for occupied nodes, narrow passages, crossing actors,
   removed/restored obstacles and interrupted patrols.

### D. Data-driven levels

1. Author rooms, doors, props, patrol routes and security links in Unity assets.
2. Compile them once into immutable Core data at load.
3. Replace runtime `Resources.Load` discovery with serialized references; move
   to Addressables only when the content library requires it.

## 8. Definition of done

A feature is complete only when all applicable checks pass:

- official Unity route and exact package/version recorded;
- no duplicate custom engine infrastructure introduced;
- deterministic tests pass;
- PlayMode fixture behaves correctly in a foreground Game view;
- required animation/contact/light/camera result is visually inspected;
- profiler comparison shows no regression for performance-sensitive work;
- canonical docs and package ownership map remain accurate.

