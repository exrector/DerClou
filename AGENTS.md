# AGENTS.md — Codex onboarding

This repository is a native Apple game project. Before doing nontrivial work, read:

- `README.md`
- `CLAUDE.md`
- `docs/GAME_DESIGN.md`
- `docs/TECHNICAL_ARCHITECTURE.md`
- `docs/ART_DIRECTION.md`
- `docs/ORIGINAL_GAMES_RESEARCH.md`
- `docs/IP_AND_LEGAL_BOUNDARIES.md`
- `docs/CAMPAIGN_PLAN.md`
- `docs/PLATFORM_COMPATIBILITY.md`
- `docs/ROADMAP.md`

## Project summary

Build a polished **top-down / 2.5D burglary-planning puzzle game** for iPhone, inspired by the planning/execution mechanics of *Der Clou! 2 / The Sting!* but using entirely original IP and levels.

## Fixed technical choices

- **iOS 18+**. **(Старый вариант: iOS 27+.)**
- Swift
- SwiftUI
- RealityKit
- Reality Composer Pro 3
- Xcode
- native Apple runtime stack only; external DCC tools and legally usable asset
  sources are allowed in the offline art pipeline
- true 3D world with a fixed high top-down tactical camera
- use SwiftUI `RealityView` with a virtual RealityKit camera and `OrthographicCameraComponent` for the intended tactical projection
- tap-to-move pathfinding must use a project-owned navigation abstraction backed by GameplayKit graph/pathfinding APIs or a validated deterministic custom A* implementation. **(Старый вариант: RealityKit Navigation Mesh / `NavigationController` from iOS 27.)**

Do not migrate the project to Godot, Unity, SpriteKit, SceneKit or a web stack without an explicit owner decision.

Supporting iOS 18 is an API-coverage decision, **not** a reason to reduce visual quality, animation quality, materials, lighting, level complexity or gameplay. If older supported hardware needs adaptation, use measured quality/performance tiers while preserving the production art direction.

## Fixed gameplay choices

- full-screen tactical building view
- no virtual joystick
- tap floor/corridor/room to navigate there
- tap objects for contextual interaction
- constant base walking speed in the initial design
- deterministic, learnable guard patrols
- security cameras, alarms, lasers, switches, doors, safes, containers and loot form the puzzle
- skills/tools mainly change what an actor can do, how long it takes, how much noise/damage it creates, and what can be carried
- planning and execution are separate phases
- execution should be deterministic enough that a corrected plan reliably produces a corrected outcome
- game is not intended to become a reflex shooter/stealth action game

## Graphics

Use reusable 3D models, not rendered sprite variants.

Examples:

- one desk model can be rotated to any orientation;
- camera rotates as a 3D object;
- doors animate on hinges;
- characters use skeletal Idle/Walk/interact animations;
- lasers and alarm LEDs are material/shader/effect animations;
- real lighting/shadows preserve the volumetric look while the camera reads like a tactical 2D map.

## Agent behavior

- Check the repository before asking the owner to repeat context.
- Check current Apple documentation and the installed SDK before assuming API availability/behavior.
- Use Xcode build/test feedback as part of implementation.
- Prefer small, reusable RealityKit components and systems over level-specific scripts.
- Do not create elaborate abstractions before the vertical slice needs them.
- Keep core gameplay rules in maintainable Swift/data structures even when Reality Composer Pro visual graphs are used for authoring.
- Surface blockers immediately.
- Never silently simplify the game merely to retain the iOS 18 deployment floor. Report the exact blocker first.
- Preserve IP separation from the original games.
- `docs/IP_AND_LEGAL_BOUNDARIES.md` is mandatory project policy for levels, characters, story, UI, assets, naming and any use of original-game research.
- Extract abstract mechanics from the originals, then independently redesign geometry, timings, security graphs, story context and visual expression. Do not reconstruct specific original missions.

## Immediate product goal

A polished first vertical slice containing:

1. high-quality top-down orthographic 3D room layout;
2. one playable thief;
3. deterministic tap-to-move pathfinding using the project navigation layer; **(Старый вариант: RealityKit Navigation Mesh.)**
4. one deterministic patrol guard + vision;
5. one rotating security camera;
6. one interactive door;
7. one alarm/laser/switch dependency;
8. one safe/loot objective;
9. extraction;
10. minimal plan → commit → execute → retry loop.

For more detail, `CLAUDE.md` is currently the most complete implementation brief.
