# Foundational game algorithms

Status: architectural contract and implementation order, revised 2026-08-21.

This document answers one question: which reusable algorithms must exist so a
level author describes **what is in the building and what happened**, without
hand-authoring how every character gets there or writing object-specific Swift.

The target is not one hundred unrelated knobs. It is a small set of composable
algorithms whose data profiles can produce hundreds of characters, objects and
security arrangements.

## 1. Non-negotiable pipeline

```text
world fact / player tap / stimulus
            │
            ▼
goal selection (what and why)
            │
            ▼
action planning (which affordances and traversal links are required)
            │
            ▼
global navigation (where a legal route corridor exists)
            │
            ▼
trajectory (clearance, corner radii, facing and speed profile)
            │
            ▼
semantic animation + RealityKit presentation
```

Information flows downward. A ray, mesh, animation callback, collision shape or
wall hit may never pause time, cancel a goal or become the authority for world
state. Only mission control changes the mission clock. Only the decision layer
changes a goal. Only the navigation layer changes a route.

## 2. Character and navigation profile

Every character resolves one `CharacterProfile`, never scattered constants:

- physical width/radius and standing height;
- walk/run speeds and acceleration/deceleration;
- preferred wall clearance (comfort beyond collision radius);
- wall-clearance cost weight;
- preferred corner radius and maximum turn rate;
- arrival and interaction-slot tolerances;
- locomotion/animation set and foot-phase metadata;
- abilities/tags (`canOpen`, `canUnlock`, `canVault`, tools, access level);
- perception profile (eyes, hearing, reaction and memory);
- decision profile (priorities, alert thresholds, communication ability).

The body radius is a hard feasibility constraint. Preferred clearance is a soft
cost: a character may pass through a narrow door but should move toward the
middle of a wide corridor instead of scraping the shortest wall.

Implemented now:

- character radius erodes walkability;
- a deterministic octile distance transform computes remaining clearance;
- weighted A* trades a little path length for wall clearance;
- smoothing uses the same weighted cost and cannot undo the safe route;
- interaction candidates are evaluated by actual route length, not Euclidean
  distance through a wall.

## 3. Autonomous navigation stack

### 3.1 Spatial representation

DerClou permanently keeps **two related representations with different jobs**:

1. the invisible modular **authoring grid** is the contract for coordinates,
   snapping, procedural generation, canonical object sizes and level editing;
2. a **baked continuous polygon navigation mesh** is derived from grid-aligned
   geometry and object boundaries and owns runtime global routes.

This is not a choice between grid and navmesh. Unity-style grid snapping makes
arbitrary modular art interchangeable; Recast-style baking converts geometry
through a conservative walkability field into polygons. Actors never visibly
walk from cell centre to cell centre and input never rebuilds the static field.

Every `PropPrototype` now owns or inherits one placement contract:

- canonical metric width, height and depth plus a grid-footprint conversion;
- bottom/centre/hinge pivot policy;
- position and rotation snap increments;
- deterministic `preserveMeters`, `uniformFit` or `fitCanonicalBounds` import
  scale policy;
- separate collision, navigation, interaction, door-sweep and actor-separation
  margins.

Therefore replacing a grey cube with a Fab mesh changes presentation, not the
level's gameplay dimensions. The importer normalizes source bounds to the
prototype; validators and systems continue to read the prototype contract.

The Apple-native implementation contract is:

1. an authoring/build tool converts blueprint floor boundaries and polygonal
   obstacles to a triangulation (initial candidate: `GKMeshGraph`);
2. triangles, adjacency, portals, areas, clearance and a content hash are
   canonicalized and serialized into a baked level asset;
3. runtime `HeistCore` loads that asset and runs deterministic custom A* over
   polygon adjacency;
4. the funnel/string-pulling stage returns the shortest path contained in the
   corridor;
5. doors, stairs and special traversal are explicit portal/off-mesh links with
   state and affordance preconditions, not rasterized every frame;
6. only a material, persistent geometry change dirties a spatial tile. Tile
   rebuild happens on a worker and is atomically published as a new revision.

`GKMeshGraph` is an authoring candidate rather than runtime authority: Apple
documents it as a space-filling 2D navigation graph and exposes its triangles.
Baking removes OS-version triangulation from replay and lets tests validate one
canonical asset hash. If actual-level benchmarks show unsuitable topology or
tile seams, replace only the baker with a project-owned constrained
triangulation; runtime contracts do not change.

The existing `NavGrid` is the dense **bake/validation field**, not the permanent
level authoring grid and not the actor's runtime route. It must never be rebuilt
on tap. It remains useful for conservative erosion, clearance, reachability and
regression diagnostics; production queries consume `BakedNavigationMesh`.

Implemented safeguards during migration:

- **versioned immutable planning snapshots**;
- **`NavigationPlanRequest` / `NavigationPlanResponse`**: path queries carry
  actor ID, request ID and world revision and can run off the main/render actor;
- interactive taps return immediately; stale worker results cannot overwrite a
  newer command or a changed world;
- **`AgentNavigationTask`**: semantic goal plus disposable path, expressed as a
  pure function of mission time;
- thief, guard and future actors use one mission-time locomotion system;
- moving bodies use a local transient mask/right-of-way rule, never a full
  static-world rebuild;
- a patrol goal survives blockage and replanning.
- stable rectangle polygons, portal adjacency, corridor A* and funnel/string
  pulling are implemented behind `NavigationTopologySnapshot`;
- a persistent cube publishes a new topology revision and invalidates stale
  plans; shared-boundary and T-junction routes are validated against the baked
  polygon union.

Add next:

- **room/portal graph** above it: rooms are nodes; doors/passages are edges
  carrying state, access requirements and traversal cost;
- **connected-component cache** for immediate unreachable-goal diagnostics;
- **spatial hash** for nearby agents, stimuli and smart-object queries;
- spatially tiled persistent-obstacle rebuild and atomic revision publication.

### 3.2 Global route

- **A*** with stable tie-breaking — current grid backend and future polygon
  corridor backend;
- **clearance-weighted edge/area cost** — current and retained;
- **polygon corridor + funnel/string pulling** — implemented production backend;
- **room-level A*** followed by local polygon A* — next when missions grow;
- **D* Lite/LPA*** — only if frequent topology changes make full A* measurably
  expensive; opening one door is not enough reason;
- **SIPP (Safe Interval Path Planning)** — intended for a known moving guard,
  camera timing or planned actor occupying a corridor. It plans in safe time
  intervals and can deliberately insert a wait;
- **reservation table / Cooperative A*** — first multi-character solution;
- **Conflict-Based Search** — later only if several player characters require
  globally conflict-free optimal tracks and prioritized planning is inadequate.

Other actors are not baked obstacles. The implemented fixed-step layer uses two
explicit contracts: one disposable detour around a stationary capsule, or an
early crossing reservation that makes the lower-priority actor avoid the full
remaining steering segment of the right-of-way actor. It never commands a
stationary actor to yield. A truly sealed narrow portal remains a safe blocked
contact until a separate gameplay action (push/arrest) resolves it. During committed puzzle playback, temporal
reservations/SIPP remain authoritative so the same plan has the same outcome.
Local avoidance may refine presentation only inside the reserved safe corridor;
it may never silently change puzzle timing or cancel a goal.

### 3.3 Comfortable trajectory

A shortest polyline is not a human walking trajectory. The trajectory builder
now clearance-validates rounded quadratic corner samples and supplies a tangent
for facing. The complete trajectory contract is:

1. a legal corridor;
2. portals/door centres that the body capsule clears;
3. tangent points around each corner;
4. circular arcs or curvature-bounded spline segments whose radius fits the
   available clearance;
5. a trapezoidal or S-curve speed profile with acceleration, cruise, braking;
6. explicit turn-in-place when an arc cannot fit;
7. final position and facing from the selected interaction slot.

Clothoids are the mathematically strongest continuous-curvature option, but
humans are not nonholonomic cars. Start with clearance-constrained circular arcs
plus turn-in-place; add clothoids only if animation tests prove a visible gain.

## 4. Smart objects: doors, furniture, safes and panels

Every gameplay object is a `SmartObjectDefinition`, not a special tap handler.
It provides data; the actor owns execution.

```text
stable ID
world bounds
interaction slots (position + facing + side)
affordances
preconditions
effects
duration
noise signature
animation semantic
reservation capacity
navigation links
security/evidence state
```

Examples:

- desk: `inspect`, `search`, possible contents;
- filing cabinet: `open`, `search`, `take`, possible lock/alarm;
- safe: `inspect`, `crack`, `open`, `take`, alarm link;
- door: two-sided traversal link plus `open`, `close`, `unlock`, `lockpick`;
- panel: `inspect`, `hack`, `toggle`, linked security effects.

A tap ray resolves the topmost gameplay object. If it hits furniture, it must not
fall through semantically and become a floor-move command. The system queries
the object's currently valid affordances, selects/reserves a reachable slot,
paths there, aligns facing, performs the timed action, applies effects and emits
noise/evidence/security events.

Implemented now:

- all non-scenery props are tappable as objects even with no current action;
- `inspect` and `search` are reusable stateful affordances;
- furniture can declare them in the catalog;
- all usable sides are candidate slots with final facing;
- the shortest **reachable route** selects the slot;
- interaction begins only after arrival and alignment.

Next:

- explicit slot authoring/overrides for asymmetric art assets;
- slot reservation so two actors do not occupy the same drawer/door position;
- traversal links that insert `open door` automatically into a route;
- action precondition/effect planner, so a locked door becomes
  `use key → open → traverse`, `lockpick → open → traverse`, or `find another
  route`, according to actor abilities and total cost;
- contents as stable object IDs, not hard-coded rewards inside furniture;
- contextual action UI when more than one affordance is valid.

## 5. Guard goals and decisions

A patrol is a low-priority repeating goal, not the guard's movement algorithm.
The guard receives a goal and uses the same navigation/action stack as a thief.

```text
Patrol(routeID)
Investigate(stimulusID, location)
Pursue(targetID, lastKnownLocation)
Inspect(objectID)
Secure(objectID/location)
RaiseAlarm / CallBackup
ReturnToPost
```

Use a deterministic hierarchical state machine or compact behavior tree for
priority and interruption:

```text
direct threat > confirmed alarm > pursue > investigate > inspect anomaly > patrol
```

Do not use full GOAP for simple guard priority. Use an A*/GOAP-style action
planner only inside a chosen goal when the route may require doors, keys, panels
or alternative access. This keeps behavior explainable to the player.

The guard starts navigation from its live position. Level authors place patrol
destinations/routines, but never draw reaction routes from every possible room.

## 6. Perception and stimuli

All sensing produces typed `PerceptionStimulus` values:

- guard visual contact;
- camera visual contact;
- sound;
- forced entry/tamper;
- unexpected world state;
- security alarm.

### Vision

Broad phase: range and spatial query. Narrow phase: cone dot product, height-aware
line of sight against current wall/door volumes. The visible polygon/mesh uses
the same solver and is presentation only.

### Sound

Noise is not a circular collision radius. Each action emits a signature:

```text
kind + source location + base loudness + duration + frequency/tag
```

Propagation uses the room/portal graph with Dijkstra-style accumulated
attenuation. Walls block/attenuate; open and closed doors have different costs;
distance attenuates inside a room. A guard receives normalized intensity and
its hearing profile decides whether to ignore, become suspicious or investigate.
Keys, footsteps, a drawer, glass and a grinder therefore differ by data, not by
separate guard code.

### Memory and evidence

Guards remember a last known location and stimulus time. Inspectable invariants
generate evidence: a door expected closed but found open, a broken lock, missing
loot, disabled camera or moved object. Evidence is a stimulus; it does not
directly teleport the guard into an alarm animation.

## 7. Suspicion and facility alarm

Keep two related but distinct states:

- per-agent **suspicion**: calm → suspicious → investigating → alerted;
- facility **security state**: normal → warning → alarm → lockdown.

`AlertState` and `AlertPolicy` now provide deterministic accumulation, thresholds
and mission-time decay. Different stimulus types have data-driven weights. A
quiet sound may be ignored; a grinder creates an investigation; direct visual or
a wired trip may raise the facility state immediately.

Communication is explicit. A guard seeing a thief only changes the facility
alarm if the guard has a radio, reaches a panel, shouts within hearing range or
the level rule says visual contact is directly networked.

Indicator lights read the real security state:

- green: powered and not armed;
- red steady: armed;
- amber/blink: warning/tamper/countdown;
- red blink: triggered/alarm;
- dark: unpowered (not automatically safe; fail-secure devices may remain
  locked).

Never maintain a separate decorative boolean for the lamp.

## 8. Security graph

Devices form a typed directed graph:

```text
sensor/camera/door contact → controller/alarm zone → siren/lock/camera response
panel/switch/tool          → controller/device state change
```

Required algorithms:

- stable node and edge IDs;
- typed effects (`power`, `arm`, `disarm`, `unlock`, `trigger`);
- deterministic event queue ordered by mission time then stable ID;
- graph validation for missing nodes and illegal cycles;
- strongly connected component reporting for intentional feedback loops;
- transactional propagation: evaluate, validate, then commit state;
- timed effects via a priority queue, never ad-hoc frame timers;
- state-derived indicator presentation.

## 9. Locomotion and animation

Simulation supplies desired position, tangent, speed, turn rate and semantic
activity. Animation never supplies mission displacement.

Baseline state vocabulary:

```text
Idle → StartWalk → Walk → Stop
TurnLeft / TurnRight / TurnInPlace
OpenDoor / CloseDoor / Lockpick
Inspect / Search / UseTool / Carry
```

Algorithms/order:

1. choose semantic state from trajectory/activity;
2. synchronize clip playback speed to planned ground speed using authored clip
   distance and cycle duration (distance matching);
3. cross-fade/inertialize transitions;
4. use foot-contact markers to avoid switching on a planted foot;
5. optional RealityKit IK foot locking on uneven surfaces;
6. interaction-slot alignment before door/furniture animation;
7. optional motion warping adapter for imperfect authored reach, never changing
   authoritative end state.

Full motion matching is deferred. It needs a large coherent mocap database and
runtime feature search; downloaded isolated clips do not become a motion-matching
database. RealityKit's animation library/graph/IK are presentation tools around
the semantic contract, not replacements for it.

## 10. Deterministic simulation, planning and replay

- fixed 60 Hz mission step — implemented;
- variable render time accumulator — implemented;
- semantic commands, not transform recordings;
- immutable level definition + mutable world snapshot;
- event log with stable ordering;
- periodic snapshots for seek/rewind;
- state hash regression fixtures;
- deterministic seeded random stream only for explicitly authored randomness;
- temporal action intervals and precondition validation;
- SIPP/reservations for known moving obstacles;
- simulation outcomes recorded as data while playback may continue.

## 11. What not to install blindly

- no physics forces for patrol or planned locomotion;
- no collision collider on a vision cone/ray;
- no `ray hit → pause clock` or `detection → cancel route` coupling;
- no one behavior tree per level;
- no route authored from every guard position to every room;
- no prototype-ID switch statements for furniture/doors/security;
- no DetourCrowd/ORCA as the authority for deterministic plan execution;
- no D* Lite, CBS, clothoids or motion matching until the simpler predecessor
  is measured and shown insufficient.

## 12. Implementation order from here

1. Complete door policy with post-traversal close/alarm rules and multi-door
   room/portal planning; automatic unlock/open/resume is implemented.
2. Add interaction-slot reservations, then SIPP/reservations for converging
   actors and a deterministic replay fixture.
3. Import or author the missing clean locomotion/action clips, then extend with
   distance matching, cross-fades and interaction alignment.
4. Connect typed sound, guard goals, evidence and facility security state.
5. Build a visual Level Editor/import pipeline over the grid contract, then add
   reusable noir PBR material and lighting presets in the art layer.

## Primary and official references

- Apple RealityKit ECS systems and custom components:
  https://developer.apple.com/documentation/realitykit/ecs-systems
- Apple RealityKit entity animation, animation libraries and graphs:
  https://developer.apple.com/documentation/realitykit/game-development-entity-animations
- Apple character control, skeletons and inverse kinematics:
  https://developer.apple.com/documentation/realitykit/game-development-character-skeletons
- Recast/Detour official repository and module boundaries:
  https://github.com/recastnavigation/recastnavigation
- Recast agent-radius erosion rationale:
  https://github.com/recastnavigation/recastnavigation/blob/main/Docs/Extern/Recast_api.txt
- Detour path corridor and off-mesh connection model:
  https://github.com/recastnavigation/recastnavigation/blob/main/DetourCrowd/Source/DetourPathCorridor.cpp
- Hart, Nilsson, Raphael, A*:
  https://www.cs.auckland.ac.nz/courses/compsci709s2c/resources/Mike.d/astarNilsson.pdf
- Koenig and Likhachev, D* Lite:
  https://repository.gatech.edu/entities/publication/62caaf86-5cc2-4434-89b5-980d324a5302
- Phillips and Likhachev, Safe Interval Path Planning:
  https://publications.ri.cmu.edu/sipp-safe-interval-path-planning-for-dynamic-environments
- Silver, Cooperative Pathfinding:
  https://ocs.aaai.org/Papers/AIIDE/2005/AIIDE05-020.pdf
- Sharon et al., Conflict-Based Search:
  https://doi.org/10.1016/j.artint.2014.11.006
- Van den Berg et al., ORCA:
  https://emotion.inrialpes.fr/fraichard/safety2010/10-vandenberg-etal-icraw.pdf
- Reynolds, steering behaviors:
  https://www.red3d.com/cwr/papers/1999/gdc99steer.pdf
- Explicit Corridor Map / clearance-based character navigation:
  https://arxiv.org/abs/1701.05141
- Epic Smart Objects (slots, queries and reservations):
  https://dev.epicgames.com/documentation/unreal-engine/smart-objects-in-unreal-engine---overview
- Orkin, goal-oriented action planning in F.E.A.R.:
  https://madwomb.com/tutorials/gamedesign/prototyping/gdc2006_JeffOrkin_AI_FEAR.pdf
- Ubisoft motion matching foundation:
  https://www.gdcvault.com/play/1023280/Motion-Matching-and-The-Road
