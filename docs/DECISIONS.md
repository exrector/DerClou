# Decision log

Purpose: prevent future Claude/Codex sessions from reopening settled questions without new evidence.

## D-001 — Project type

**Decision:** Build a burglary-planning puzzle/strategy game inspired by *Der Clou! 2 / The Sting!*.

**Reason:** The planning/recording/execution mechanic remains distinctive on iPhone and is better suited to a small indie project than competing with studios on content-heavy action games.

**Do not reinterpret as:** generic stealth action, shooter, idle heist game or narrative-only robbery game.

## D-002 — Spiritual successor, not remake

**Decision:** Use the original games as design research only.

Production content must have original:

- title;
- characters;
- story;
- dialogue;
- maps;
- missions;
- art;
- audio;
- code.

The repository name `DerClou` is an internal codename.

## D-003 — Primary platform

**Decision:** Apple ecosystem first; initial game target is iPhone.

Current minimum target: **iOS 18+**.

**(Старый вариант: iOS 27+.)**

Reason for revision: the project does not need the iOS 27 RealityKit Navigation Mesh stack to implement tap-to-move. The iOS 18 floor preserves the desired `RealityView` + true `OrthographicCameraComponent` rendering architecture while navigation can be supplied by GameplayKit graph/pathfinding APIs or a deterministic custom implementation.

## D-004 — Engine / framework

**Decision:** Native Apple stack:

- Swift
- SwiftUI
- RealityKit
- Reality Composer Pro 3
- Xcode

### Rejected alternatives

**Godot:** technically excellent and agent-friendly, but rejected because the project is Apple-only and we want one native Swift/Xcode codebase with RealityKit/RCP3 capabilities and Xcode agent integration.

**Unity:** unnecessary complexity/runtime for this project.

**SpriteKit:** initially considered for 2D, rejected after deciding that the desired visual style is volumetric 3D and should reuse real 3D objects rather than rendered sprites.

**SceneKit:** not the chosen modern Apple path; RealityKit is the target.

Do not propose changing engines again unless a concrete blocker appears in the native stack.

## D-005 — 3D instead of fake-3D 2D

**Decision:** Build the world as true 3D.

Reasoning:

- generated 2D top-down art looked good, but animation/angle consistency would create many sprite variants;
- the visual target already implies volume, tilt, lighting and shadows;
- a real 3D object can simply be rotated/reused in any mission;
- doors/cameras/safes/characters animate naturally;
- RealityKit's orthographic camera can preserve tactical top-down readability.

Examples:

- desk: one model, arbitrary yaw;
- security camera: one model, animated scan;
- door: hinge rotation;
- laser: dynamic geometry/material;
- guard: skeletal animation and arbitrary facing.

## D-006 — Camera

**Decision:** high, fixed tactical top-down camera using a **true `OrthographicCameraComponent`** in the primary iOS 18+ `RealityView` path.

A small tilt may be tested because the desired look has visible volume and side faces. Tactical readability takes priority.

**(Старый fallback idea: support older iOS through `ARView(.nonAR)` plus a narrow-FOV `PerspectiveCamera`. This is not the current production path because Apple documents non-AR ARView as using a perspective camera, which would approximate rather than preserve true orthographic projection.)**

## D-007 — Input

**Decision:** no joystick.

- tap floor/room/corridor -> actor pathfinds there;
- tap object -> contextual interaction;
- character movement is automatic after tap.

This directly matches the original sequel's click-to-go planning control and fits iPhone.

## D-008 — Movement speed

**Decision:** start with one constant base walking speed.

Reason: simplifies planning/timing and removes unnecessary stat complexity.

Crew differences should first come from skills/action durations/carrying/tool access.

May be revisited only if playtesting proves varied movement speed adds valuable strategy.

## D-009 — Guard behavior

**Decision:** deterministic, learnable patrols.

No random AI wandering as core difficulty.

The player must be able to observe a patrol, infer timing, plan around it and reliably improve a failed plan.

## D-010 — Core game difficulty

**Decision:** difficulty comes from interaction of systems:

- timing;
- patrols;
- visibility;
- noise;
- evidence;
- doors;
- tools;
- cameras;
- alarms;
- lasers;
- switches;
- dependency chains;
- multiple actors.

Avoid difficulty via randomness or opaque detection.

## D-011 — Animation

**Decision:** do not use frame-by-frame rendered sprites for normal world animation.

- character -> skeletal animation;
- camera -> transform rotation;
- door -> hinge transform;
- laser -> material/geometry effect;
- keypad/alarm -> emissive/material state;
- safe/container -> articulated 3D animation.

Reality Composer Pro 3 animation/material tooling can support this, but exact generated/runtime features must be checked against the iOS 18 floor before becoming mandatory.

## D-012 — Graphics quality

**Decision:** first mission should already target commercial-quality visuals.

Internal grey-boxes are allowed only while implementing systems. Do not design the first released level as a minimalist technical placeholder.

Visual target:

- dark top-down interiors;
- detailed but readable props;
- semi-realistic/stylized PBR;
- soft real shadows;
- restrained tactical overlays;
- premium rather than cartoon/F2P aesthetic.

Supporting iOS 18 does **not** lower this target. If older supported devices require adaptation, use measured capability/performance tiers for expensive rendering features instead of simplifying the overall art direction or gameplay.

## D-013 — Asset reuse

**Decision:** build a reusable 3D prop/environment library.

Levels are assembled from reusable objects and environment kits. Do not render each mission as a unique AI image.

Exact modeling/generation workflow remains open; avoid recurring paid AI asset services by default.

## D-014 — Reality Composer Pro 3 role

**Decision:** RCP3 is the visual authoring environment for scenes/assets/materials/animation behavior and level metadata.

Core durable game logic remains understandable in Swift rather than being scattered through unique one-off graphs.

Use custom RCP3 Swift components/systems/plugins when this makes authoring reusable, but every runtime feature must respect the iOS 18 deployment floor.

**(Старый вариант: RCP3 navigation mesh and newest runtime graph features could be adopted directly because the whole game targeted iOS 27.)**

## D-015 — Coding agents

**Decision:** Claude Code / Claude Agent begins implementation because usage is currently available to the owner. Codex will be connected later.

Both agents should work against the same GitHub/Xcode project.

Xcode 26.3+ agentic coding/MCP integration is part of the intended workflow.

The repository must contain enough context that neither agent requires the owner to repeat the premise.

## D-016 — First engineering goal

**Decision:** polished vertical slice, not full campaign and not a disposable throwaway prototype.

Minimum functional slice:

- top-down 3D room layout;
- player thief;
- tap-to-move;
- deterministic guard;
- security camera;
- door;
- switch/security dependency;
- alarm/laser;
- safe/loot;
- extraction;
- planning/commit/execution/retry loop.

## D-017 — Original source-code research

**Decision:** First game's COSP/open-source lineage is useful as reference but GPLv2 implications mean no automatic copying into commercial code.

No legitimate public source-code release for the second game was located as of 2026-08-16.

The second game's manual + all-18-mission walkthrough are sufficient for independent game-design analysis.

## D-018 — What matters from Der Clou! 2

Preserve as abstract inspiration:

- plan recording;
- plan execution;
- predictable patrol windows;
- guard inspections;
- tool noise/damage/speed tradeoffs;
- specialists;
- security cause/effect;
- timed switches;
- cross-linked alarms;
- multi-character coordination;
- mission progression that teaches one concept then combines concepts.

Do not preserve literal content.

## D-019 — Market hypothesis

**Decision:** treat the project as a niche premium tactical/puzzle opportunity, not as a direct attempt to outspend mobile studios.

Door Kickers is an adjacent proof that touch-oriented top-down tactical planning can sell on iPhone. It is not the same loop.

The absence of a clear modern Der-Clou-style iPhone leader is a working hypothesis, not guaranteed demand.

## D-020 — Do not derail into unrelated “new Apple API” gimmicks

Earlier ideation explored many novel iPhone mechanics. For this project, technology must serve the heist game.

Do not add AR, live camera, random new-sensor gimmicks or Wi-Fi Aware merely because Apple exposes them.

The innovation is the polished mobile resurrection/evolution of the burglary planning loop using modern Apple-native tools.

## D-021 — Navigation implementation is not tied to RealityKit iOS 27 APIs

**Decision:** tap-to-move uses a project-owned navigation abstraction.

Allowed backends:

- GameplayKit `GKGraph` / `GKGridGraph`;
- `GKObstacleGraph`;
- `GKMeshGraph`;
- deterministic custom A* where justified by actual level geometry and dynamic-door requirements.

Apple documents GameplayKit graph classes as pathfinding tools for game worlds and `GKGraph.findPath(from:to:)` as computing a shortest traversal.

**(Старый вариант: use RCP3 Navigation Mesh + RealityKit `NavigationController`, which pushed the project to iOS 27.)**

The chosen implementation must preserve deterministic route selection for the planning/execution loop.

## D-022 — Deployment floor must not drive visual downgrades

**Decision:** iOS 18 is a compatibility floor, not an art target.

Do not simplify rendering, materials, animation, lighting, level density or gameplay merely because iOS 18 includes older hardware. Profile on real supported devices and introduce explicit quality tiers only where measured performance requires them.

If retaining iOS 18 creates a concrete blocker that would materially harm the intended game, surface that blocker before changing the design or raising the deployment target.
