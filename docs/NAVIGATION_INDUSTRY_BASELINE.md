# Navigation Industry Baseline

Status: accepted, 2026-08-22.

DerClou does not define character movement from individual bug reports. Its
navigation stack follows the separation provided by Apple's native game stack:

1. global planning finds a polygon corridor to the semantic destination;
2. corridor optimization removes unnecessary links without changing the goal;
3. local steering chooses a collision-safe short-horizon motion;
4. a bounded speed/curvature profile turns that motion into a trajectory;
5. RealityKit presents the authoritative mission-time pose and blends clips.

GameplayKit provides separate graph/pathfinding APIs and agent/goal/behavior
APIs, while RealityKit owns ECS presentation, animation and scene geometry.
The verified adoption matrix and iOS availability gate are normative in
`APPLE_GAMEPLAY_FRAMEWORK_AUDIT.md`.
The exhaustive equivalence-class gate for commands, angles, actor encounters
and repeated world mutations is `CHARACTER_MOVEMENT_SCENARIO_MATRIX.md`.

## DerClou contracts

- A semantic goal is never cancelled by a sight ray, collision callback,
  animation event or temporary obstacle.
- A patrol detour targets the next available authored node. An occupied node is
  skipped; it is a route marker, not a mandatory parking pose.
- A stationary body receives a longer look-ahead and causes one disposable
  detour. The body is never instructed or pushed aside by navigation.
- Two moving trajectories are negotiated when the later route is committed.
  Runtime safety may brake the lower-priority actor at its last safe pose, but
  may not rewrite either committed destination.
- A replacement path is published atomically from the actor's live pose,
  heading and speed. It begins with a grid-validated cubic heading join and
  then follows the rounded corridor.
- Explicit turn clips are used for real pivots in place. Curved walking uses the
  walk cycle while the authoritative body follows the trajectory tangent.
- Every output remains a deterministic function of mission time, command data
  and navigation-world revision so recording, replay and scrubbing agree.
- A world revision is stale-result metadata, not a global replan signal. A new
  obstacle affects only still-untravelled actor corridors that intersect its
  expanded bounds. Removal, an obstacle behind the actor, animation and other
  non-navigation changes leave the committed path and its time origin intact.

## Apple-only production decision

- retain DerClou's pure mission-time trajectory and priority contracts;
- keep global planning and local steering behind project-owned interfaces;
- benchmark GameplayKit graph and agent adapters on the mandatory regressions
  before replacing an already tested backend;
- never couple RealityKit entities or animation controllers to path ownership.

## Mandatory regression scenarios

1. A cube appears on a patrol leg: one detour to the next authored node.
2. A stationary thief appears ahead: early smooth bypass without moving thief.
3. A thief occupies the next patrol node: skip to the following node.
4. Two committed trajectories cross: first commitment keeps right of way.
5. A replacement route begins while walking: no exposed blocked state, no speed
   reset and no pivot unless the requested change is a near reversal.
6. Every inserted curve chord stays inside eroded walkability.
7. After an actor passes a temporary cube, removing and replacing that cube
   behind it does not change the remaining path, speed or trajectory start.
