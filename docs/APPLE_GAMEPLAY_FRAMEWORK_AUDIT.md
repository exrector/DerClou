# Apple Gameplay Framework Audit

Status: normative architecture gate, 2026-08-22.

DerClou production code uses only frameworks shipped by Apple with the
supported platform SDK. Before implementing a foundational game subsystem, we
must check the installed stable SDK, the installed beta SDK, current Apple
documentation, and relevant Apple sample code. A framework is adopted only
when it preserves the game's deterministic mission timeline and iOS 18 floor.

## Movement and navigation

### GameplayKit agents: adopt behind a deterministic adapter

`GKAgent2D`, `GKGoal`, `GKBehavior`, and `GKPath` are the Apple-native steering
toolbox for a game constrained to the floor plane. They are candidates for:

- seeking a short-horizon target;
- following/staying on a corridor path;
- reaching a target speed;
- avoiding agents and polygon obstacles;
- producing natural acceleration changes.

They are not a replacement for global pathfinding, doors, semantic goals, or
right-of-way policy. `GKAgent2D.update(deltaTime:)` mutates iterative agent
state. DerClou therefore must not let a render-frame-driven agent become the
authoritative simulation. The allowed integration is:

1. build immutable steering input from the current mission snapshot;
2. run GameplayKit at a fixed simulation step;
3. sample the result into an immutable mission-time trajectory;
4. publish that trajectory atomically after checking world revision;
5. record the published result for replay and scrubbing.

The adapter must pass the existing stationary-body, moving-crossing,
first-committed-right-of-way, occupied-patrol-node, narrow-door, and repeated-
simulation tests before replacing the current local steering implementation.

Implementation result (2026-08-22): the fixed-step adapter and guarded
`AppleNavigationPlanner` entry point exist. Repeated runs are deterministic,
but a direct stationary-body fixture showed that `GKGoal(toAvoid:)` may enter
the project's hard capsule-clearance margin. This is expected of weighted
steering: it is a preference, not a collision certificate. The adapter is
therefore accepted only as an optional curve candidate. Every sampled chord is
validated against walkability and body clearance; rejection preserves the
existing deterministic route. It is not yet used as production locomotion.

Apple reference:
<https://developer.apple.com/documentation/gameplaykit/gkagent2d>
<https://developer.apple.com/documentation/gameplaykit/gkgoal>
<https://developer.apple.com/documentation/gameplaykit/gkbehavior>
<https://developer.apple.com/documentation/gameplaykit/gkpath>

### GameplayKit pathfinding: benchmark behind NavigationPlanner

`GKGridGraph`, `GKObstacleGraph`, and `GKMeshGraph` are valid Apple-native
global-planning backends. They remain behind the project-owned planning
interface because level clearance, door state, dynamic world revision, and
path replay are game contracts. `GKMeshGraph`/`GKObstacleGraph` will be
benchmarked against the current baked polygon-corridor planner on the same
level fixtures; no call may rebuild the world synchronously during a tap.

Apple reference:
<https://developer.apple.com/documentation/gameplaykit/gkgraph>
<https://developer.apple.com/documentation/gameplaykit/gkmeshgraph>
<https://developer.apple.com/documentation/gameplaykit/gkobstaclegraph>

### RealityKit NavigationController: future backend, not iOS 18 production

The installed Xcode 26.6 SDK cannot compile `NavigationController`. The
installed Xcode 27 beta SDK declares it available from iOS 27, macOS 27,
visionOS 27, tvOS 27, and Mac Catalyst 27. DerClou targets iOS 18, so this API
may be added later as a conditionally available backend but cannot replace the
current production navigation layer.

Apple reference:
<https://developer.apple.com/documentation/realitykit/navigationcontroller>

## Character state and animation

### GKStateMachine: use for explicit mode transitions, not locomotion math

`GKStateMachine` is a reusable finite-state-machine container. We still define
the states, valid transitions, and enter/update/exit behavior. It does not
automatically rotate a character, choose animation clips, or infer
`Idle -> Walk -> Interact` rules.

It is appropriate for coarse AI/mode orchestration where object identity and
mutable state do not harm replay. The authoritative movement sequence remains
the value-type `AgentNavigationTask`, because it supports direct evaluation at
arbitrary mission time. Animation states consume that result; they never own
world transforms or gameplay timing.

Apple reference:
<https://developer.apple.com/documentation/gameplaykit/gkstatemachine>

### RealityKit animation: already adopted

`CharacterAnimationPlayback` already calls
`playAnimation(..., transitionDuration:)`, and `WalkAnimationSync` already sets
`AnimationPlaybackController.speed` from the actor's walk speed divided by the
measured source-clip speed. The reusable semantic vocabulary includes idle,
start, walk, stop, short step, left/right/around turns, and interactions.

Presentation smoothing must follow authoritative trajectory facing. Adding an
independent render-only `simd_slerp` would make the visible facing disagree with
vision and interaction rules. Quaternion interpolation is allowed only inside
the shared mission-time trajectory calculation or for a purely cosmetic child
whose orientation has no gameplay meaning.

Apple reference:
<https://developer.apple.com/documentation/realitykit/entity/playanimation(_:transitionduration:startswithpaused:)>
<https://developer.apple.com/documentation/realitykit/animationplaybackcontroller>

## Guard decisions

- `GKRuleSystem` is a candidate for data-driven/fuzzy scoring of facts such as
  noise, an unexpectedly open secured door, alarm state, and visibility.
- `GKDecisionTree` is useful only when a manually authored or trained question
  tree is clearer than the alert/routine model.
- `GKMinmaxStrategist` targets turn-based game-model move search. It is not the
  default solution for real-time guard reactions or path planning.

The alert model remains explicit data until a GameplayKit version demonstrates
better authoring without weakening deterministic replay or debuggability.

Apple reference:
<https://developer.apple.com/documentation/gameplaykit/gkrulesystem>
<https://developer.apple.com/documentation/gameplaykit/gkdecisiontree>
<https://developer.apple.com/documentation/gameplaykit/gkminmaxstrategist>

## RealityKit ECS and Apple sample baseline

Apple's “Bringing your SceneKit projects to RealityKit” sample is the current
structural reference: modular Swift packages, data-only components, systems
that own behavior, a `CharacterMovementComponent`, and an `AgentComponent`
using GameplayKit goals. We reuse its separation of concerns, not its joystick
or platformer-specific movement rules.

The downloaded sample source also defines the boundary clearly:

- `AgentSystem` calls `GKAgent3D.update(deltaTime: context.deltaTime)` from the
  rendering system and writes the entity transform immediately;
- `CharacterMovementSystem` integrates velocity from render `deltaTime`;
- both movement systems use `simd_slerp` with a constant per-frame fraction;
- its character state transitions are explicit switches in
  `CharacterStateComponent`, not an automatic `GKStateMachine` solution.

Those choices are suitable for the sample's responsive platformer, but not for
DerClou's record/scrub/replay contract. We adopt the ECS/package boundaries and
GameplayKit goal construction while replacing render-time authority with the
fixed-step sampled-trajectory adapter described above.

Apple reference:
<https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit>

## Asset and visual-authoring tools

- Reality Composer Pro remains the Apple visual authoring environment for
  scenes, custom component properties, materials, lighting, Shader Graph, and
  content-level animation/sequencing supported by the deployment target.
- RealityKit collision shapes, scene queries/raycasts, and input targeting are
  presentation/geometry services. A ray hit never cancels an actor's semantic
  goal.
- Reality Converter is a separate Apple application, not proof that arbitrary
  source rigs and actions will retarget correctly.
- `usdzconvert` is not present in the installed Xcode 26.6 toolchain;
  `/usr/bin/usdzip` is present, but it packages USD and does not replace the
  project's audited skeletal-animation import/retarget pipeline.

No architecture document may claim that an Apple tool is bundled or solves a
gameplay contract until that exact API/tool is verified in the installed SDK.
