# DerClou — working repository

> **Internal working name only.** The commercial game must use an original title, characters, story, levels, art and text. `DerClou` is the repository codename because the project is a spiritual successor to **Der Clou! / The Clue!** and especially **Der Clou! 2 / The Sting! (2001)**.

## What this project is

A native Apple-platform **top-down / 2.5D heist-planning puzzle game** inspired by the planning/execution loop of *Der Clou! 2 / The Sting!*.

The game is **not** intended to be a clone. We reuse the high-level design grammar: reconnaissance, deterministic patrols, doors, cameras, alarms, switches, tools, specialists, loot, timing and multi-character coordination. All production content must be original.

The core fantasy is:

**Study the building → build a precise burglary plan → commit → watch the plan execute → learn from failure → improve the plan.**

The game should feel like a living security-system puzzle, not an action game.

## Non-negotiable product decisions

- Apple ecosystem first.
- Current target: **iOS 27+**.
- Native stack: **Swift + SwiftUI + RealityKit + Reality Composer Pro 3 + Xcode**.
- Use Xcode's agentic coding support with **Claude Agent / Claude Code now**, and **Codex later**.
- Do **not** switch the project to Unity, Godot, SpriteKit, SceneKit or a web engine unless the owner explicitly changes this decision.
- The world is real 3D rendered from a fixed high top-down camera. It should visually read like a polished 2D tactical map while retaining real depth, materials, lighting, shadows and animation.
- Prefer an **orthographic camera** for the tactical view. A slight camera tilt may be evaluated only if readability remains excellent.
- No joystick. Primary control is **tap-to-move / tap-to-interact**.
- Player taps a corridor, room or floor point; the selected character pathfinds there automatically.
- Character walking speed is intentionally **constant/simplified** unless later testing proves a strong gameplay reason to vary it.
- Character differentiation should come mainly from capabilities and action durations: lockpicking, safe cracking, electronics/alarm work, carrying capacity, special abilities, etc.
- Guards and security systems should be **deterministic and learnable**, not randomly chaotic. The player must be able to understand the system and improve a plan.
- Levels begin simple and add one or a small number of mechanics at a time.
- Visual quality matters from Level 1. Do not ship programmer-art as the intended production look.

## Core interaction model

The playable area should occupy essentially the whole iPhone screen.

Typical interactions:

- tap floor/corridor → character navigates to that point;
- tap door → approach + contextual open/lockpick/breach action;
- tap safe/locker/drawer/desk → approach + inspect/open/crack/take loot;
- tap camera/alarm/laser/keypad/switch → inspect relationships or interact if the selected character has the right tool/skill;
- tap character → select character;
- visible route and timing feedback during planning;
- pinch/drag camera gestures can be evaluated, but they must not fight the basic tap interaction.

## Game systems

The level is a graph of rooms, paths and security dependencies disguised as a believable building.

### Environment

- walls and collision volumes;
- corridors and rooms;
- normal / locked / alarmed doors;
- windows and alternate entries;
- stairs / multiple floors where useful;
- furniture and cover/hiding geometry;
- entry and extraction points.

### Security

- guards with fixed patrol routes;
- guard vision cones;
- hearing/noise detection;
- security cameras with rotating view cones;
- laser/tripwire barriers;
- alarms and linked alarm systems;
- keypads / control panels;
- switches;
- timed switches;
- electrical/security dependencies;
- cameras or barriers that can be disabled indirectly by switches elsewhere.

### Interactive objects / loot

- safes;
- cash registers;
- lockers;
- drawers;
- cabinets;
- crates;
- computers/terminals;
- paintings / valuables / cash / mission objects;
- optional loot vs mandatory objective loot.

### Tools / skills

Potential tool vocabulary inherited only as design inspiration from the originals:

- lockpick;
- crowbar;
- drill / safe-cracking tool;
- electronics/soldering tool;
- cutting/breaching tool;
- keys / keycards / mission-specific devices.

Each tool can trade off **action time, noise, visible damage and weight**. This is more interesting than simply making one tool universally better.

### Persistent observable state

An important design principle from the original games:

- a damaged door can later be noticed;
- an open door/locker can be noticed;
- a guard may inspect specific objects or doors;
- a clean lockpick action can be safer than a noisy destructive method;
- the player must think about what a guard will see **later**, not only whether the player is visible now.

## Planning and execution

The original *Der Clou! 2* had three broad modes: city/preparation, recording a plan, and executing the recorded plan. The official manual states that the recorded plan is then executed according to the recording and watched like a small film.

For this project, the central design value is the planning/execution separation. The exact metagame outside missions is still open.

Desired loop:

1. Select / inspect target.
2. Observe patrols and security relationships.
3. Choose characters/tools if the mission uses a crew.
4. Record or author actions and movement.
5. Validate timing and dependencies.
6. **Commit / Execute.**
7. Watch the deterministic plan play out.
8. If it fails, return to planning with useful information and edit the plan.

A major open design decision is how much intervention is permitted after execution begins. The default assumption is **little or none**, because commitment creates tension and makes planning meaningful.

## Movement and AI

Use RealityKit's navigation facilities on iOS 27 where appropriate:

- `NavigationMeshComponent` / navigation mesh authored in Reality Composer Pro 3;
- `NavigationController` path requests for tap-to-move;
- deterministic patrol waypoint/routine logic for guards;
- line-of-sight / ray tests for visibility;
- explicit hearing/noise model rather than opaque AI.

The player should be able to learn: “this guard repeats this route every N seconds” and design around it.

## Graphics: actual 3D, presented as top-down

Earlier 2D sprite approaches were rejected. The game should use reusable 3D assets.

Why:

- one desk model can be rotated to any angle;
- one camera model can physically rotate;
- one door can animate around its hinge;
- one safe can open in 3D;
- one character rig can walk and turn in arbitrary directions;
- lighting and shadows naturally respond to orientation;
- assets are reused across many missions without redrawing top/left/right variants.

RealityKit provides `OrthographicCameraComponent`, so the scene can retain 3D geometry while reading visually as a clean tactical plan.

### Animation philosophy

Do not use frame-by-frame sprite animation for ordinary world objects.

- Guard/thief: skeletal animation, at minimum Idle + Walk, later contextual interactions.
- Security camera: rotate the 3D entity smoothly.
- Door: hinge rotation.
- Safe/drawer/cabinet: articulated 3D animation.
- Laser: geometry/material/shader animation.
- Alarm/keypad lights: emissive/material animation.
- Route indicators, vision cones, interaction highlights: procedural/UI/RealityKit effects.

Reality Composer Pro 3 provides Animation Graph, Behavior Tree, Script Graph, Navigation Mesh, Sequencer, Compute Graph and Shader Graph tooling that may be used where they simplify authoring.

## Intended visual direction

The desired look is a polished, dark, readable heist/security-board aesthetic:

- high top-down view;
- dark architectural interiors;
- readable material separation;
- restrained realistic/stylized PBR rather than cartoon or pixel art;
- soft but visible shadows;
- clear interactive highlights;
- blue/neutral security camera cones;
- red alarm/laser states;
- green route/goal feedback only where useful;
- furniture and props detailed enough to make locations believable without sacrificing tactical readability.

A level should look finished from the first mission, not like a grey-box shipped as art.

## Technical stack

### Xcode / Swift

- Swift: game logic and data model.
- SwiftUI: menus, HUD, mission selection, inventory/crew UI, settings, overlays.
- RealityKit: runtime entities, rendering, transforms, animation playback, navigation, collision, ray tests, systems/components.
- Reality Composer Pro 3: visual level construction, reusable scene content, materials, animation graphs, behavior trees, navigation meshes and effects.

Xcode 26.3+ includes agentic coding support for Anthropic Claude Agent and OpenAI Codex, and exposes Xcode capabilities through MCP. Agents can build, test, inspect errors and search Apple documentation.

### Suggested code architecture

```text
DerClou/
├── App/
├── Game/
│   ├── Core/
│   ├── Components/
│   │   ├── CharacterComponent.swift
│   │   ├── GuardComponent.swift
│   │   ├── SecurityCameraComponent.swift
│   │   ├── DoorComponent.swift
│   │   ├── AlarmComponent.swift
│   │   ├── LaserComponent.swift
│   │   ├── LootComponent.swift
│   │   └── InteractableComponent.swift
│   ├── Systems/
│   │   ├── NavigationSystem.swift
│   │   ├── GuardPatrolSystem.swift
│   │   ├── VisionSystem.swift
│   │   ├── NoiseSystem.swift
│   │   ├── SecuritySystem.swift
│   │   ├── InteractionSystem.swift
│   │   └── PlanExecutionSystem.swift
│   ├── Planning/
│   ├── Missions/
│   └── UI/
├── RealityKitContent/
└── Tests/
```

This is a proposed organization, not a demand to create empty abstractions before the first vertical slice. Keep the architecture data-driven and component-oriented.

## First vertical slice

Do not attempt 18–30 missions immediately. First prove the complete game loop in one visually polished small mission.

Suggested Level 1 ingredients:

- 3–5 rooms + corridor;
- 1 playable thief;
- 1 deterministic guard patrol;
- 1 rotating security camera;
- 1 locked door;
- 1 laser barrier or simple alarm dependency;
- 1 switch/control panel;
- 1 safe or high-value target;
- entry/extraction point;
- tap-to-move;
- selectable interactive objects;
- visible camera/guard detection feedback;
- planning/commit/execution loop in minimal form.

Success criterion: after a failed execution, the player immediately understands what went wrong and wants to alter the plan and retry.

## Research on the original games

Detailed notes are in [`docs/ORIGINAL_GAMES_RESEARCH.md`](docs/ORIGINAL_GAMES_RESEARCH.md).

Key references:

### Der Clou! / The Clue! (1994)

- Clou! Open Source Project (COSP): https://sourceforge.net/projects/cosp/
- COSP files: https://sourceforge.net/projects/cosp/files/
- Open SDL source-port files: https://sourceforge.net/projects/cosp/files/Open%20SDL%20Port/
- Preserved original game-data releases: https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/
- Discussion of the originally released Neo source and missing original archives: https://sourceforge.net/p/cosp/discussion/25891/thread/5e2dd6b92b/
- Modern detailed walkthrough/reference for The Clue!: https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/introduction

COSP is GPLv2 and contains a modified/restructured open-source lineage based on the first game. Do **not** automatically copy code into this commercial project; treat it as research unless licensing implications are deliberately reviewed.

### Der Clou! 2 / The Sting! (2001)

- Official German manual hosted by THQ Nordic: https://www.ds.thqnordic.com/support/Clou2_Handbuch.pdf
- English manual scan: https://www.gamewholesale.com/downloads/Sting_Manual.pdf
- Kasey Chang's extensive 2001 strategy guide / walkthrough, including all 18 jobs: https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/14674
- Secondary walkthrough mirror: https://www.mogelpower.de/cheats/loesung.php?id=38954
- MobyGames historical metadata/covers/screenshots: https://www.mobygames.com/game/4295/the-sting/

As of research on **2026-08-16**, no publicly available source-code release for *Der Clou! 2 / The Sting!* was located. Do not waste time assuming the sequel source is available. The official manuals and walkthrough are sufficient to reconstruct the game's design grammar without copying its implementation.

## The 18 Der Clou! 2 jobs as design research

The walkthrough documents these jobs in order:

1. Gas Station
2. Grocery Store
3. Cinema
4. Hotel
5. Greenhouse / Arboretum
6. Boxing Club
7. Printing Office
8. Undertaker / Funeral Home
9. Mausoleum
10. Spam Factory
11. The Villa
12. Neo Office
13. Museum
14. Bank
15. Barracks
16. Harbor
17. Power Plant
18. Ministry of Light

We are interested in **how complexity is introduced**, not in recreating their layouts.

The progression teaches roughly:

- patrol timing and noise;
- hiding and guard inspection behavior;
- safe cracking and specialist roles;
- multiple actors and carrying constraints;
- first alarm systems;
- switches and indirect dependencies;
- timed barriers;
- cross-linked security;
- cameras and alternate routes;
- simultaneous teams;
- chained dependencies (key → room → switch → alarm → objective);
- synchronized switches in separated locations;
- rescue/non-loot objectives;
- final integrated multi-team security puzzles.

Use this as a **level-design grammar** to create original missions.

## Market positioning / comparison

The closest proven iPhone adjacency found so far is **Door Kickers**, a premium top-down tactical planning game with touch-oriented route planning. It is not the same game: Door Kickers is SWAT/action and supports reactive tactical intervention. Our differentiator is burglary planning, security-system puzzles and commitment to a recorded plan.

App Store reference: https://apps.apple.com/us/app/door-kickers/id975683986

The current opportunity hypothesis is that there is no obvious modern iPhone leader delivering a full *Der Clou! 2*-style burglary planning/execution simulator. This is a hypothesis to keep validating, not a guarantee of commercial success.

## Apple references

- RealityKit `OrthographicCameraComponent`: https://developer.apple.com/documentation/realitykit/orthographiccameracomponent
- RealityKit `NavigationController`: https://developer.apple.com/documentation/realitykit/navigationcontroller
- Reality Composer Pro 3 workflow / Animation Graph / Behavior Tree / Navigation Mesh / Script Graph: https://developer.apple.com/videos/play/wwdc2026/393/
- No-code game design with Reality Composer Pro 3: https://developer.apple.com/videos/play/wwdc2026/252/
- Extending Reality Composer Pro 3 with custom Swift components/systems: https://developer.apple.com/videos/play/wwdc2026/281/
- Xcode 26.3 agentic coding release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes
- Xcode agentic coding / MCP Tech Talk: https://developer.apple.com/videos/play/tech-talks/111428/

## Agent onboarding

Before making architectural decisions, coding agents must read:

1. [`CLAUDE.md`](CLAUDE.md) or [`AGENTS.md`](AGENTS.md)
2. [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md)
3. [`docs/TECHNICAL_ARCHITECTURE.md`](docs/TECHNICAL_ARCHITECTURE.md)
4. [`docs/ART_DIRECTION.md`](docs/ART_DIRECTION.md)
5. [`docs/ORIGINAL_GAMES_RESEARCH.md`](docs/ORIGINAL_GAMES_RESEARCH.md)
6. [`docs/ROADMAP.md`](docs/ROADMAP.md)

Do not ask the owner to re-explain the basic premise if these files answer the question.

## Legal/IP boundary

This project is a **spiritual successor**, not a remake.

Do not ship:

- original `Der Clou!` / `The Sting!` names as the game title;
- Matt Tucker or other original characters;
- original dialogue/story text;
- copied maps/mission layouts;
- original graphics/audio/models;
- code copied from GPL sources into proprietary code without an explicit licensing decision.

Permitted design inspiration includes general game mechanics, genre conventions, abstract systems, timing concepts and independently created levels based on the same broad type of puzzle.

## Current status

Repository initialized as a design/engineering knowledge base on **2026-08-16**. Claude Code is expected to start implementation first; Codex will be connected later. The first engineering goal is a polished native vertical slice, not a throwaway prototype and not a full campaign.