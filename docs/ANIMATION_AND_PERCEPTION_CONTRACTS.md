# Animation and perception contracts

This document is the boundary between deterministic gameplay, authored assets
and RealityKit presentation. Do not bypass it with per-level animation calls,
hard-coded cone meshes or physics-driven patrol movement.

## Character animation vocabulary

Gameplay refers only to `CharacterAnimationSemantic`:

```text
Idle
StartWalking
Walk
TurnLeft
TurnRight
TurnAround
OpenDoor
CloseDoor
Lockpick
PressButton
PullLever
Look
```

Asset filenames, Blender action suffixes and RealityKit-generated names are
adapter details. `CharacterAnimationLibrary` maps them to this vocabulary.
`CharacterAnimationPlayback` is the only general entry point for playing a
semantic clip. Simulation never waits for an animation callback and animation
never determines distance, facing, interaction completion or mission time.

Current accepted runtime coverage:

- `Idle`, `StartWalking`, `Walk`, `TurnLeft`, `TurnRight`, `TurnAround`,
  `OpenDoor`, `PressButton`, `PullLever` and `Look`: extracted and verified for
  every office actor;
- the turn source contributes only hips/leg footwork. Its torch-specific upper
  body curves, all downloaded meshes and its root yaw are discarded; entity
  yaw remains authoritative;
- `StopWalking`, `ShortStep`, `CloseDoor`, `UnlockDoor` and `Lockpick`: runtime
  semantic slots and explicit fallbacks exist, but no accepted clean source
  clip has yet been assigned;

Every actor uses the same orchestration sequence:

```text
Idle -> Turn/Pivot? -> StartWalking -> Walk -> Brake -> Stop/Aligned
     -> Interaction? -> StartWalking -> Traverse/Continue -> Brake -> Idle
```

`AgentNavigationTask` owns turn, acceleration, cruise, braking, short-step and
arrival time. `AgentLocomotionSystem` maps those phases onto named clips for any
entity with `AgentNavigationComponent`; it contains no guard/thief branches.
While `ActiveInteractionComponent` is present, locomotion holds the settled pose
and cannot replace the door/tool one-shot with Idle or resume a guard patrol.

Each downloaded FBX is treated as an untrusted scene. The pipeline verifies its
single armature/action and critical humanoid bones, retargets only the action,
then deletes all imported objects and recursively purges orphaned meshes,
materials and images. RealityKit exposes only the animation bound in a loaded
USD scene, so the runtime resources include one named, non-displayed carrier per
semantic; the carrier uses the target character rig and is never attached as a
second visible model.

## Animation acquisition

The runtime remains native Swift/RealityKit, but source motions are not limited
to Apple-authored assets. The accepted acquisition source is the authenticated
Adobe Mixamo catalog. `ArtSource/Tools/mixamo_selective_download.py` searches
that catalog and exports one selected motion at a time for the account's active
character, without skin, at 30 fps. It never stores the access token and writes
a provenance receipt beside every FBX.

Do not use a mirrored raw Mixamo archive as the production source and do not
commit or redistribute downloaded raw FBX files outside the project team.
Adobe permits Mixamo animations in commercial video games, while raw animation
files may not be redistributed as an asset library. The Hugging Face mirror is
therefore not part of this pipeline. Third-party harvesters may inform adapter
maintenance, but their all-characters/all-motions behavior, token files and
concurrent export monitoring are not accepted production behavior.

Candidate discovery is driven by
`ArtSource/Animations/mixamo-search-plan.json`. Search results are not accepted
automatically: every clip still passes `audit_action_fbx.py`, a rendered motion
preview, semantic/style review and `apply_animation.py`. Imported meshes,
materials, cameras and lights are discarded.

The downloaded folder contains `Opening Door Inwards`, but no independent
closing clip and no clean unarmed left/right turn pair. Closing may use a
purpose-authored clip or a deliberately validated reversed opening clip; this
must be an asset decision, not a runtime name hack.

## Locomotion and patrol

`PatrolRoute.state(at:)` is authoritative. It returns position, facing and one
of three activities: `turning`, `waiting`, `walking`. Turns occupy deterministic
mission time and interpolate the shortest yaw. `AgentLocomotionSystem` only applies
that state to RealityKit.

Patrol guards intentionally have no RealityKit `CollisionComponent` or physics
body. Their character-radius capsules still participate in the authoritative
navigation world, so actors avoid one another without letting physics impulses
take control of planned motion.
Their route cannot be stopped by their vision display, a wall collider or
another render entity. Route validity belongs to level validation; movement is
not resolved by runtime collision response.

## Perception profiles

All observers use `VisionSourceComponent` plus the pure `VisionSolver`.

```text
Guard:  range 10 m, FOV 70 degrees — farther and narrower
Camera: range  6 m, FOV 120 degrees — shorter and wider
```

These are catalog defaults, not level-specific code. Instances may override
them through config. Cameras additionally use a deterministic scan arc and
period. Detection and the displayed mesh consume the same profile, facing,
mission time and occluder boxes.

The visible region is sampled and clipped against full 3D wall/door volumes.
Sight does not bend around a corner. Space beyond a corner becomes visible only
when rotation or movement produces a real line of sight through an opening.
Door lintels do not block a ray passing below them.

The vision mesh is presentation only. It has no collision shape and never
participates in navigation.

Detection is also observation only. A `DetectionEvent`, an occlusion hit, a
displayed ray or a cone reaching a wall may update diagnostics, suspicion or an
alarm state, but none may pause mission time, cancel a route, stop an animation
or mutate navigation. Only an explicit mission-control command may start, pause,
seek or reset the clock. A later playback policy may *report* a terminal outcome
while simulation continues for replay analysis; perception itself never owns that
policy.

## Hinged doors

Doors are identified by `PropPrototype.mechanic == .hingedDoor`, never by a
prototype ID string. `DoorTransition` owns deterministic open fraction over
mission time. `DoorGeometry` rotates the live leaf volume around the authored
hinge. `DoorPresentationSystem` applies the same fraction to the RealityKit
hinge child.

Supported semantic interactions are `open`, `close`, `unlock` and `lockpick`. Their
logical state is written by `InteractionResolver`; the door animation is only
the presentation of that state transition. A moving door leaf participates in
vision occlusion at its current angle.

Routes detect the first closed door as a smart traversal gate. A guard uses the
`actor.can.unlock` key affordance, a thief uses `actor.can.lockpick`, and the
approach planner is constrained to the actor's current side so it cannot route
through the closed leaf to reach its interaction slot. After the timed action,
the original semantic destination is replanned and resumed.

## Asset acceptance rule

Every newly exported character must pass a runtime contract test against all
semantic clips claimed by its manifest. A carrier contains exactly one audited
semantic, so its sole RealityKit resource may be assigned that manifest name;
the combined visible character may never select among actions through
`availableAnimations.first`. Missing clips may use an explicit, documented
presentation fallback.
