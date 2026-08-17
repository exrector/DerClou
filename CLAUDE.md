# CLAUDE.md — DerClou project instructions

This file is the authoritative fast-start context for Claude/Claude Code.

## Read first

Before changing architecture or gameplay, read:

1. `README.md`
2. `docs/GAME_DESIGN.md`
3. `docs/TECHNICAL_ARCHITECTURE.md`
4. `docs/ART_DIRECTION.md`
5. `docs/ORIGINAL_GAMES_RESEARCH.md`
6. `docs/IP_AND_LEGAL_BOUNDARIES.md`
7. `docs/CAMPAIGN_PLAN.md`
8. `docs/PLATFORM_COMPATIBILITY.md`
9. `docs/ROADMAP.md`

Do not ask the owner to re-explain facts already written there.

## Project in one sentence

Build a polished native iPhone top-down/2.5D heist-planning puzzle game inspired by the **planning/execution grammar** of *Der Clou! 2 / The Sting!*, with original IP, using Swift + SwiftUI + RealityKit + Reality Composer Pro 3.

## Hard decisions already made

- Target Apple ecosystem first.
- Current deployment target: **iOS 18+**. This is the lowest target that preserves the intended modern RealityKit architecture with `RealityView` and a true `OrthographicCameraComponent` without falling back to a perspective-camera approximation. **(Старый вариант: target iOS 27+.)**
- Native technology stack only: **Swift, SwiftUI, RealityKit, Reality Composer Pro 3, Xcode**.
- Claude works inside the Xcode/native project. Codex will later work on the same codebase.
- Do not migrate to Unity, Godot, SpriteKit, SceneKit or a web stack.
- This is a **real 3D scene viewed from above**, not a sprite game.
- Main tactical rendering path: **SwiftUI `RealityView` + virtual RealityKit camera + `OrthographicCameraComponent`**. **(Старый вариант: iOS 27 was selected partly to use the newest RealityKit navigation stack.)**
- No virtual joystick.
- Player interaction: tap floor/room/corridor to move; tap world objects to interact.
- Pathfinding must be independent of iOS 27 Navigation Mesh APIs. **Settled 2026-08-17 and implemented:** a project-owned deterministic grid A* in `HeistCore` (`NavGrid` + `PathFinder`), built from the blueprint's own geometry. GameplayKit was evaluated and not needed — the custom layer gives exact control of the obstacle dilation radius, guaranteed determinism and unit tests with no simulator. **(Старый вариант: use RealityKit Navigation Mesh / `NavigationController` on iOS 27.)**
- Player-character walking speed is intentionally constant in the first implementation.
- Differences between crew members should primarily be skills, permitted actions, carrying capacity and action duration.
- Guards/patrols are deterministic and learnable. Randomness must not invalidate careful planning.
- The planning/commit/execution loop is central. Do not turn the game into a reflex stealth/action game.
- Production visual quality matters from the first playable mission. A grey-box is acceptable internally only while implementing a feature, never as the target art direction.
- **Supporting iOS 18 must not simplify the intended art direction, level complexity, animation quality, lighting, materials or gameplay.** The deployment floor is an API-compatibility decision, not a visual-quality target. If weaker devices require scaling, use capability/performance tiers rather than lowering the production design.

## What the game is NOT

- not AR/VR gameplay;
- not a camera game;
- not a Hitman clone;
- not a shooter;
- not a roguelike built around random patrols;
- not a 2D sprite sheet game;
- not a literal remake of Der Clou! 2;
- not a project that copies original maps, story, characters, art or dialogue.

## Core gameplay model

The building is effectively a time-dependent graph:

- rooms and corridors define navigation;
- guards traverse deterministic patrol routes;
- doors and obstacles gate paths;
- security devices create visibility/alarm constraints;
- switches/keys/panels create dependency chains;
- character actions consume known amounts of time;
- tools can alter time/noise/damage tradeoffs;
- loot/objectives add route and carrying constraints;
- multiple characters later create synchronization problems.

A good mission can be solved through understanding, timing and coordination.

## Critical gameplay systems to implement incrementally

1. Top-down RealityKit scene and orthographic camera.
2. Tap/raycast from screen to floor.
3. Deterministic navigation graph/pathfinding and selected-character movement. **(Старый вариант: RealityKit navigation mesh.)**
4. Interactable component + contextual interaction dispatch.
5. Door component/state/animation.
6. Guard deterministic patrol.
7. Guard vision test with geometry occlusion.
8. Security camera scan + view cone + detection.
9. Alarm state and feedback.
10. Laser/tripwire barrier.
11. Loot/safe/container interactions.
12. Noise events and hearing.
13. Plan recording/model.
14. Deterministic playback/execution.
15. Multi-character plan synchronization.

Do not build 15 before 1–8 are solid.

## Reality Composer Pro 3 role

RCP3 is the visual scene/asset/level authoring tool, not a replacement for maintainable Swift architecture.

Use it for:

- building mission scenes;
- placing reusable 3D assets;
- materials, lights, shadows;
- authoring level geometry and navigation metadata/anchors consumed by our navigation layer;
- animation graphs where their runtime availability matches the iOS 18 deployment floor;
- skeletal animation blending;
- selected Behavior Trees / Script Graph workflows only when their generated/runtime dependencies remain compatible with iOS 18;
- visual effects via Shader/Compute Graph only after checking the deployment requirement of the exact generated feature.

**(Старый вариант: RCP3 Navigation Mesh and other newest RCP3 runtime graphs could be used directly because the whole game targeted iOS 27.)**

Keep durable game rules and data models accessible from Swift. Avoid burying core game logic in opaque one-off visual graphs that coding agents cannot reason about efficiently.

RCP3 supports extension through custom Swift components/systems and custom Script Graph nodes. Prefer reusable components over duplicated per-level behavior, but every runtime dependency must respect the iOS 18 floor.

## Swift / RealityKit architectural guidance

Favor data-driven RealityKit ECS-style design:

- small `Component` types for entity state/config;
- reusable `System` types for runtime behavior;
- mission definition data separate from generic engine behavior;
- explicit state machines over scattered booleans;
- deterministic simulation-friendly clocks/timers;
- dependency injection/testable pure Swift logic for planning where feasible.

Potential components:

- `CharacterComponent`
- `GuardComponent`
- `InteractableComponent`
- `DoorComponent`
- `SecurityCameraComponent`
- `AlarmComponent`
- `LaserComponent`
- `LootComponent`
- `SafeComponent`
- `SwitchComponent`
- `NoiseEmitterComponent`
- `PlanActorComponent`

Potential systems:

- `NavigationSystem`
- `InteractionSystem`
- `GuardPatrolSystem`
- `VisionSystem`
- `NoiseSystem`
- `SecuritySystem`
- `AnimationStateSystem`
- `PlanningSystem`
- `PlanExecutionSystem`

These names are suggestions. Do not create empty architecture merely to match this list.

## Determinism requirement

Planning must be trustworthy.

Given the same mission state and same plan, execution should produce the same relevant result unless the game explicitly introduces a documented deterministic variable.

Avoid:

- frame-rate-dependent gameplay timing;
- uncontrolled physics affecting critical paths;
- random guard pauses;
- navigation paths that unpredictably change because of cosmetic simulation;
- hidden probabilities in lockpicking/detection.

The player must be able to say: “I failed because I was 1.2 seconds late,” fix the plan and expect the fix to matter.

## Time model

Do not tie mission logic directly to rendering frames. Use a simulation timeline / elapsed time model.

Actions should have explicit durations, for example:

- walk: distance / constant movement speed;
- open unlocked door: fixed short duration;
- lockpick: character skill + lock difficulty + tool modifier;
- safe cracking: skill + safe difficulty + tool modifier;
- alarm bypass: electronics skill + device difficulty + tool modifier;
- loot pickup: small fixed/weight-based duration.

Exact formulas are not finalized. Keep them configurable rather than hard-coded through UI code.

## Guard perception

Vision should be understandable:

1. range;
2. field-of-view angle;
3. facing direction;
4. line-of-sight occlusion by walls/doors/geometry;
5. optional reaction delay later.

Hearing should similarly use explicit noise events with magnitude/range and geometry rules. Do not fake perception with arbitrary trigger volumes unless used only as an implementation optimization that preserves the visible rules.

## Security dependencies

Security devices should support graph-like relationships such as:

```text
Switch A -> Camera 1 power
Switch B -> Laser 2
Alarm panel C -> Door D alarm state
Timed switch E -> corridor barrier for 10 seconds
Key K -> secure office door -> panel P -> warehouse alarm -> objective
```

This dependency grammar is central to level design. Build it data-first and reusable.

## Asset / animation rules

The game uses reusable 3D assets.

- A desk is one 3D model rotated as needed.
- A security camera is one model with transform animation.
- A door uses hinge animation.
- Characters use skeletal animation.
- Lasers, alarm lights and highlights use materials/shaders/procedural effects.
- Avoid generating a separate rendered image for each angle/state.

Visual target: dark, polished, tactical, readable, semi-realistic/stylized PBR. See `docs/ART_DIRECTION.md`.

## Original-game research rules

The original games are research references only.

`docs/IP_AND_LEGAL_BOUNDARIES.md` is mandatory project policy. If any level, character, story element, UI, asset, title, marketing idea or code use conflicts with that document, the legal-boundary document wins until the owner explicitly changes the policy after review.

Do not copy:

- maps;
- mission layouts;
- character names;
- plot/dialogue;
- artwork/audio;
- sequel implementation;
- GPL code from the first game's open-source lineage into proprietary production code without an explicit licensing decision.

Do study:

- progression of puzzle concepts;
- security dependency patterns;
- patrol timing;
- noise vs tool tradeoffs;
- guard inspection behavior;
- multi-character synchronization;
- plan-record/execute feedback loop.

When inspired by a specific original mission, extract the abstract mechanic first, then independently redesign geometry, patrol topology, timing values, security graph, objective context, names and visual expression. Do not reconstruct a recognizable original mission with replacement art.

`docs/ORIGINAL_GAMES_RESEARCH.md` contains verified links and all 18 sequel mission names.

## Working with the owner

- The owner is driving product/game design and does not want to spend time hand-writing routine code.
- Claude should act as implementation engineer, not repeatedly ask basic programming questions that can be resolved from the repository or Apple documentation.
- When a technical uncertainty exists, verify against current Apple documentation and/or build a minimal experiment.
- State blockers early. Do not spend a long response celebrating an approach and only later reveal that it cannot work.
- Do not silently change already-selected technologies.
- If supporting an older deployment target appears to require reducing art/gameplay quality, stop and report the concrete API or performance blocker. Do not silently simplify the game.

## First implementation target

Create a polished vertical slice, not a disposable demo:

- full-screen game view using `RealityView`;
- top-down orthographic 3D scene using `OrthographicCameraComponent`;
- floor/walls/rooms with real materials and lighting;
- one selectable thief;
- tap-to-move using the project navigation abstraction (GameplayKit graph or validated custom A*); **(Старый вариант: RealityKit Navigation Mesh.)**
- one deterministic guard;
- one rotating camera;
- door interaction;
- alarm/laser or equivalent security dependency;
- safe/loot objective;
- extraction;
- minimal planning → execute → retry loop.

The architecture should support adding new levels mostly by placing/configuring reusable components rather than writing bespoke code for every mission.

## Deployment floor vs visual target

**iOS 18 is an API floor, not an art budget.**

Do not simplify rendering, art direction, level complexity, lighting, materials,
animations or gameplay in order to support iOS 18. Scale *up* on capable hardware
instead: `RenderQuality` in `HeistKit` picks a tier from the device and adjusts
light counts and shadow cost. The baseline tier is still the full visual target.

Principle for API choices, set by the owner on 2026-08-17:

> Use the oldest stable Apple API that solves the problem well. Reach for the
> newest RealityKit APIs only when they give a substantial advantage that cannot
> reasonably be had otherwise.
