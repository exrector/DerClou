# Technical Architecture

Status: baseline architecture for first implementation.

The concrete algorithm selection, autonomous navigation stack and smart-object
contracts are maintained in `FOUNDATIONAL_GAME_ALGORITHMS.md`. That document is
normative when this older baseline uses a broader phrase such as "navigation" or
"behavior".

Apple framework selection and exact SDK availability are maintained in
`APPLE_GAMEPLAY_FRAMEWORK_AUDIT.md`. It is normative when this older baseline
mentions a framework or tool without an availability qualification.

## 1. Platform target

Primary target: **iPhone, iOS 18+**.

Lowered from iOS 27 on 2026-08-17. Reasons:

- iOS 27 is beta, so an iOS-27-only build reaches essentially no players;
- the only iOS 27 APIs the design needed were the navigation mesh ones. The
  project therefore owns its navigation abstraction and baked data; the current
  grid A* is a tested migration backend, while production navigation moves to a
  baked polygon corridor/funnel backend without raising the deployment target;
- iOS 18 is set by three APIs that *are* core to the look: `RealityView`,
  `RealityViewCameraContent` and `OrthographicCameraComponent`.

Going below 18 would mean `ARView(.nonAR)` plus a narrow-FOV perspective camera
faking the orthographic view. Rejected: the tactical plan view is exactly where
converging verticals read as wrong.

The floor is an API constraint, not a quality ceiling. See `RenderQuality`.

## 2. Technology stack

### Swift

Use for:

- game-state models;
- mission logic;
- planning data;
- timing/simulation;
- reusable RealityKit components/systems;
- persistence;
- tests.

### SwiftUI

Use for:

- app shell;
- menus;
- mission selection;
- HUD and overlays;
- crew/tool screens;
- settings;
- plan/timeline UI where a native overlay is better than 3D UI.

Do not build ordinary app UI as 3D scene geometry without a compelling reason.

### RealityKit

Use for:

- 3D world;
- entities/components/systems;
- models/materials;
- transforms;
- collision/input targeting;
- cameras;
- animation playback;
- navigation;
- line-of-sight/raycast behavior;
- lighting and shadows;
- interaction with RCP-authored scene content.

### Reality Composer Pro 3

Use as level/scene authoring environment:

- build rooms and mission scenes;
- place reusable object prototypes/assets;
- configure materials and lighting;
- generate/configure navigation meshes;
- create animation graphs;
- use Behavior Trees for authoring patrol/routine content where appropriate;
- use Script Graph for local event-driven scene interaction where appropriate;
- use Sequencer for cinematic/scene sequences where useful;
- Shader Graph / Compute Graph for visual effects.

### Xcode

Use for:

- Swift code;
- project configuration;
- build/run/test;
- profiling;
- device deployment;
- App Store pipeline;
- coding-agent integration.

Xcode 26.3 introduced agentic coding support for Anthropic Claude Agent and OpenAI Codex and exposes Xcode capabilities through MCP.

Official reference:

https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes

Tech Talk:

https://developer.apple.com/videos/play/tech-talks/111428/

## 3. Important Apple APIs / tools

### Orthographic tactical camera

`OrthographicCameraComponent`

https://developer.apple.com/documentation/realitykit/orthographiccameracomponent

Apple describes it as rendering without perspective depth, so distant objects do not appear smaller. This is ideal for a tactical top-down view while keeping the world fully 3D.

### Navigation

`NavigationController`

https://developer.apple.com/documentation/realitykit/navigationcontroller

The API can request/compute a path for an entity associated with navigation components.

Reality Composer Pro 3 WWDC26 session showing Navigation Mesh, Animation Graph, Behavior Trees and Script Graph:

https://developer.apple.com/videos/play/wwdc2026/393/

### RCP3 game scripting

No-code game design / Script Graph:

https://developer.apple.com/videos/play/wwdc2026/252/

RCP3 extension with custom Swift components/systems and custom Script Graph nodes:

https://developer.apple.com/videos/play/wwdc2026/281/

## 4. Architectural principles

### A. Content is data; engine behavior is reusable

A new mission should primarily define:

- scene geometry;
- placed devices;
- configuration values;
- patrol waypoints/routines;
- security links/dependencies;
- objectives;
- loot;
- starting positions.

It should not require a bespoke Swift file full of level-specific `if mission == 7` logic.

### B. Core rules stay inspectable in Swift

Reality Composer Pro graphs are excellent authoring tools, but important global rules should not disappear into dozens of unrelated visual graphs.

Keep these in maintainable Swift/data models:

- mission state;
- plan model;
- action timing;
- alarm logic;
- detection logic;
- objective evaluation;
- deterministic execution;
- save/progress state.

Use RCP graphs for content-level behavior when they improve authoring speed.

### C. Determinism over emergent physics

Do not use dynamic physics as the authoritative basis for critical puzzle timing.

Examples:

- walking follows computed paths, not physical pushing forces;
- doors have controlled animation/state transitions;
- guard timing uses simulation time;
- objective state changes through explicit actions/events.

Cosmetic physics can exist if it cannot alter puzzle outcomes unexpectedly.

## 5. Proposed runtime layers

```text
SwiftUI App/UI
      │
      ▼
GameSession / MissionController
      │
      ├── Planning model / timeline
      ├── Mission state / objectives
      ├── Security dependency graph
      └── Save/progression
      │
      ▼
RealityKit scene
      │
      ├── Character entities
      ├── Guards
      ├── Doors/containers
      ├── Cameras/lasers/alarms
      ├── Loot/objectives
      └── Environment
      │
      ▼
RealityKit Components + Systems
```

## 6. Suggested domain models

### MissionDefinition

Conceptual data:

```swift
struct MissionDefinition: Codable, Sendable {
    let id: MissionID
    let title: String
    let objectiveIDs: [ObjectiveID]
    let startingActorIDs: [ActorID]
    let extractionIDs: [ExtractionID]
    let rules: MissionRules
}
```

Exact implementation may differ depending on RCP content serialization.

### Plan

A plan should contain semantic commands:

```swift
struct HeistPlan: Codable, Sendable {
    var tracks: [ActorID: ActorPlan]
}

struct ActorPlan: Codable, Sendable {
    var actions: [PlannedAction]
}
```

Do not store the plan only as a recording of frame-by-frame transforms. Semantic actions allow:

- editing;
- deterministic resimulation;
- validation;
- UI descriptions;
- failure explanation;
- serialization.

### PlannedAction

Potential cases:

```swift
enum PlannedAction: Codable, Sendable {
    case move(destination: WorldPoint)
    case wait(duration: Duration)
    case interact(EntityID, InteractionKind)
    case takeLoot(LootID)
    case enterExtraction(ExtractionID)
}
```

Interaction detail can be decomposed later.

## 7. RealityKit components

Do not create all components on day one. Suggested target vocabulary:

### `CharacterComponent`

- actor ID;
- selected state or link to selection model;
- skills/loadout reference;
- current activity.

### `GuardComponent`

- patrol definition;
- perception config;
- current routine state;
- inspection behavior.

### `InteractableComponent`

- supported interaction kinds;
- interaction anchor/approach point;
- enabled state.

### `DoorComponent`

- open/closed;
- lock state;
- required key/skill/tool;
- damage/evidence state;
- linked alarm ID;
- interaction durations.

### `SecurityCameraComponent`

- enabled state;
- scan limits;
- scan speed/period;
- FOV/range;
- linked alarm.

### `LaserComponent`

- enabled state;
- linked alarm;
- dependency IDs.

### `AlarmComponent`

- armed/disabled/triggered;
- difficulty;
- global/local alarm consequences.

### `SwitchComponent`

- operation mode: toggle / one-shot / timed;
- target links;
- duration for timed effects.

### `LootComponent`

- value;
- weight/bulk;
- objective relation;
- evidence relation.

### `SafeComponent`

- locked/open;
- difficulty;
- contents;
- linked alarm.

## 8. Systems

### NavigationSystem

Responsibilities:

- screen tap → world destination;
- validate navigability;
- submit a versioned immutable path request without blocking MainActor;
- resolve through the selected baked navigation backend on a worker;
- snapshot older committed trajectories and reject predicted space-time
  intersections before a newly tapped route starts;
- preserve first-committed right of way, using actor role only to break an exact
  commitment-time tie;
- when a patrol leg is obstructed, discard its remainder and solve the smallest
  set of steering links directly to the next authored patrol node;
- discard stale responses after a newer command or world revision;
- command selected actor;
- move at constant configured speed;
- update animation state;
- expose estimated arrival time.

### InteractionSystem

Responsibilities:

- resolve tapped entity;
- determine available interactions;
- calculate approach point;
- queue/perform interaction;
- emit semantic action into plan recorder during planning.

### AgentLocomotionSystem

Responsibilities:

- present every actor from one mission-time navigation task;
- fall back to a guard's deterministic patrol routine;
- apply rounded position/facing and shared semantic animation;
- never use rays, physics contacts or render delta as movement authority.

### VisionSystem

Single source of truth for guard/camera detection.

Inputs:

- source transform/facing;
- FOV;
- range;
- player target bounds;
- scene occlusion/ray query;
- enabled/alert state.

The visible cone must be derived from the same values.

### NoiseSystem

Receives explicit noise events from interactions.

Possible flow:

```text
Door breach -> NoiseEvent(intensity: 0.8)
NoiseSystem -> affected guards
Guard state -> investigate/alert according to deterministic rules
```

### SecuritySystem

Own security graph state and propagation:

```text
switch event -> target effect -> camera/laser/alarm update
```

Avoid hard references to arbitrary scene names in mission logic when stable entity IDs or components can be used.

### PlanningSystem

- starts/stops plan recording;
- writes semantic actions;
- updates per-actor timeline;
- supports editing/rewind if design permits;
- validates preconditions.

### PlanExecutionSystem

- resets mission to known initial state;
- executes semantic commands against simulation timeline;
- records failure/result diagnostics;
- produces deterministic replay.

## 9. Planning timeline

The timeline is not just UI. It is the authoritative schedule of actions.

For each actor:

```text
00:00–00:04 Move corridor A -> door
00:04–00:10 Lockpick door
00:10–00:16 Move to panel
00:16–00:20 Disable camera
00:20–00:31 Move to safe
00:31–00:48 Crack safe
```

For multiple actors, tracks run in parallel.

This makes synchronization explicit and debuggable.

## 10. World reset / simulation snapshots

Planning and replay need a reliable reset mechanism.

The mission needs a canonical initial state containing at least:

- actor transforms;
- guard patrol phase;
- doors;
- security devices;
- containers/loot;
- alarm state;
- mission-object state.

Options to evaluate:

1. reload/reset mission scene from definition;
2. capture a structured initial state and restore components/transforms;
3. hybrid: reload scene + apply mission definition.

Choose the simplest reliable approach after a small experiment.

## 11. RCP3 authoring strategy

A level designer/agent should be able to:

1. create/open mission scene;
2. place floor/walls/doors;
3. place prefab/prototype camera/guard/safe/etc.;
4. set IDs/config in inspector;
5. author navigation mesh;
6. create patrol waypoint/routine data;
7. connect security dependencies;
8. place objectives/extraction;
9. run preview/build;
10. test deterministic plan.

The long-term goal: adding a mission requires mostly scene composition, not new engine code.

## 12. Asset identity

Every important gameplay entity should have a stable logical ID independent of display name.

Examples:

```text
level01.guard.01
level01.camera.eastHall
level01.switch.securityOffice
level01.safe.manager
```

Plan serialization and failure logs should use stable IDs.

## 13. Coordinate / unit conventions

Use RealityKit meters consistently.

Define conventions early:

- +Y vertical/up as RealityKit world convention;
- choose consistent building plane axes;
- character speed in meters/second;
- interaction radii in meters;
- camera ranges in meters;
- noise ranges in meters.

Do not mix arbitrary “tile units” with meters unless a clear conversion layer exists.

## 14. Rendering / camera

Recommended initial setup:

- orthographic camera;
- high position looking down;
- optional slight tilt evaluated visually;
- global directional/key light + localized practical lights as needed;
- PBR materials;
- shadow quality tuned for readability/performance;
- avoid excessive post-processing that obscures tactical state.

The camera may later support cinematic zoom/tilt during plan execution, but planning mode must remain readable.

## 15. Performance targets

Initial target: stable **60 fps** on the owner's current iPhone-class hardware while preserving visual quality.

Do not optimize prematurely, but design for:

- asset instancing/reuse;
- reasonable texture resolution;
- sensible light/shadow counts;
- occlusion/culling where useful;
- simple vision-cone visualization;
- no per-frame allocations in core systems;
- avoid one RealityKit entity per tiny decorative detail if unnecessary.

## 16. Testing strategy

### Pure Swift unit tests

Test:

- timing formulas;
- plan scheduling;
- security dependency propagation;
- objective evaluation;
- deterministic state transitions;
- save/load serialization.

### Runtime integration tests

Test:

- tap-to-world projection;
- path calculation;
- entity interactions;
- LOS occlusion;
- scene reset;
- animation state changes.

### Determinism regression

Create at least one known plan fixture:

```text
mission state + plan -> expected success/failure + timestamp
```

A code change should not silently shift mission timing without intentional review.

## 17. Agentic coding workflow

Claude/Codex should use Xcode's agent tools where possible to:

- inspect project structure;
- search current Apple docs;
- build;
- run tests;
- interpret compiler errors;
- iterate.

Do not ask the owner to manually copy compiler errors between tools if the agent can obtain build feedback itself.

Before using a newly introduced iOS 27 API, verify the current SDK signature in Apple documentation/Xcode because beta APIs may change.

## 18. Open technical experiments

Run these early rather than debating them abstractly:

1. `OrthographicCameraComponent` tactical scene on iPhone.
2. RCP3 navigation mesh + `NavigationController` tap-to-move.
3. Stable entity identification between RCP scene and Swift.
4. RCP3 custom component visible/configurable in inspector.
5. Character animation graph Idle ↔ Walk driven by Swift/navigation state.
6. Camera cone visualization tied to actual LOS logic.
7. Mission reset + deterministic replay.
8. Performance of one realistic small office level.

These experiments should produce real code and build results before large architecture expansion.
