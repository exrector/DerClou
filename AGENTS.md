# AGENTS.md — Codex onboarding

This repository is a native Apple game project. Before doing nontrivial work, read:

- `README.md`
- `CLAUDE.md`
- `docs/GAME_DESIGN.md`
- `docs/TECHNICAL_ARCHITECTURE.md`
- `docs/ART_DIRECTION.md`
- `docs/ORIGINAL_GAMES_RESEARCH.md`
- `docs/ROADMAP.md`

## Project summary

Build a polished **top-down / 2.5D burglary-planning puzzle game** for iPhone, inspired by the planning/execution mechanics of *Der Clou! 2 / The Sting!* but using entirely original IP and levels.

## Fixed technical choices

- iOS 27+
- Swift
- SwiftUI
- RealityKit
- Reality Composer Pro 3
- Xcode
- native Apple stack only
- true 3D world with a fixed high top-down tactical camera
- prefer RealityKit `OrthographicCameraComponent`
- use RealityKit navigation mesh / `NavigationController` for tap-to-move where suitable

Do not migrate the project to Godot, Unity, SpriteKit, SceneKit or a web stack without an explicit owner decision.

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
- Check current Apple documentation before assuming API availability/behavior.
- Use Xcode build/test feedback as part of implementation.
- Prefer small, reusable RealityKit components and systems over level-specific scripts.
- Do not create elaborate abstractions before the vertical slice needs them.
- Keep core gameplay rules in maintainable Swift/data structures even when Reality Composer Pro visual graphs are used for authoring.
- Surface blockers immediately.
- Preserve IP separation from the original games.

## Immediate product goal

A polished first vertical slice containing:

1. high-quality top-down 3D room layout;
2. one playable thief;
3. tap-to-move pathfinding;
4. one deterministic patrol guard + vision;
5. one rotating security camera;
6. one interactive door;
7. one alarm/laser/switch dependency;
8. one safe/loot objective;
9. extraction;
10. minimal plan → commit → execute → retry loop.

For more detail, `CLAUDE.md` is currently the most complete implementation brief.