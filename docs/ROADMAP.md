# Roadmap

This roadmap is intentionally ordered to reduce architectural risk before content production.

## Phase 0 — project bootstrap

Goal: establish a clean native Apple project that both Claude and Codex can understand and build.

Tasks:

- create iOS 27+ Xcode project;
- SwiftUI app shell;
- RealityKit game view embedded correctly;
- Reality Composer Pro 3 content package/project wired into Xcode;
- basic folder/module structure;
- source control clean;
- build and run on simulator/device;
- add minimal unit-test target;
- document any RCP3 plugin setup required.

Acceptance:

- clean build;
- app launches;
- one RCP-authored 3D scene renders on iPhone;
- coding agent can build/test without manual intervention.

## Phase 1 — prove the tactical camera

Goal: establish the final camera philosophy early.

Tasks:

- create a small office room with real 3D walls/floor/props;
- use RealityKit `OrthographicCameraComponent`;
- tune scale/framing for iPhone landscape;
- test optional small tilt vs strict top-down;
- implement camera pan/zoom only if needed;
- verify taps still project accurately into world space.

Acceptance:

- scene looks volumetric and polished enough to validate the visual direction;
- desk/door/camera models can rotate without needing alternate sprites;
- navigation targets can be selected reliably.

## Phase 2 — tap-to-move

Goal: prove the most important basic interaction.

Tasks:

- selectable player actor;
- RCP3 navigation mesh;
- screen tap → world hit point;
- `NavigationController` path request;
- move actor along path at constant speed;
- Idle/Walk animation state;
- route preview;
- arrival tolerance and cancellation/re-targeting.

Acceptance:

- tap anywhere valid in a room/corridor and actor gets there reliably;
- actor walks around walls/obstacles;
- no joystick;
- path and ETA are deterministic enough for planning.

## Phase 3 — generic interaction framework

Goal: avoid bespoke tap logic for every object.

Tasks:

- stable entity IDs;
- `InteractableComponent` or equivalent;
- tap entity → available contextual actions;
- approach point / interaction anchor;
- actor walks to correct location then interacts;
- explicit interaction duration;
- event/log output.

First objects:

- unlocked door;
- locked door;
- switch/panel;
- safe/loot container.

Acceptance:

- new object type can be added without rewriting input/navigation architecture.

## Phase 4 — door state and animation

Goal: first real world-state puzzle primitive.

Tasks:

- door hinge/pivot correct in RCP3;
- open/closed animation;
- locked/unlocked;
- navigation/collision updates when opened;
- contextual open/lockpick interaction;
- optional damage/evidence state placeholder.

Acceptance:

- pathfinding and interaction behave correctly across door state changes.

## Phase 5 — deterministic guard

Goal: prove a fair patrol puzzle.

Tasks:

- guard entity with Idle/Walk;
- fixed waypoint route;
- deterministic waits/turns;
- guard path loops exactly;
- configurable route in level content;
- debugging visualization for route/timestamps.

Acceptance:

- repeating patrol is stable across retries.

## Phase 6 — vision

Goal: the visible stealth rule equals actual detection.

Tasks:

- guard range/FOV;
- line-of-sight geometry/raycast;
- visible cone driven by same config;
- detection event;
- simple mission fail/alert state;
- test walls/doors occlude correctly.

Acceptance:

- no cases where player appears outside the visible cone but is detected, or clearly inside and not detected, except explicitly documented edge rules.

## Phase 7 — security camera

Goal: reusable animated security device.

Tasks:

- one 3D camera model;
- smooth yaw scan between configurable angles;
- view cone derived from real detection config;
- enabled/disabled state;
- linked alarm/detection event;
- status LED/material state.

Acceptance:

- same camera asset can be placed and rotated anywhere in the mission;
- no frame-by-frame graphics required.

## Phase 8 — switch / laser / security graph

Goal: prove the central dependency-puzzle architecture.

Tasks:

- `Switch` state;
- `Laser` state and visual beam;
- dependency link;
- switch disables laser/camera;
- timed switch option;
- generic security event propagation.

Acceptance scenario:

```text
player reaches panel -> disables laser for 8 seconds -> crosses -> laser reactivates
```

Failure must be deterministic if crossing is late.

## Phase 9 — safe + loot + extraction

Goal: complete the physical heist loop.

Tasks:

- locked safe/container;
- crack/open action duration;
- objective item;
- pickup;
- carried inventory state;
- extraction trigger;
- success criteria.

Acceptance:

- player can enter, bypass security, steal objective and leave.

## Phase 10 — planning recorder

Goal: convert free tactical interaction into the defining game mechanic.

Tasks:

- record semantic actions from player planning;
- per-action start/end times;
- movement duration based on actual path length;
- visible timeline;
- plan reset/rewind;
- ability to inspect action sequence;
- serialize plan data.

Acceptance:

- a complete successful free-play route can be represented as a semantic plan.

## Phase 11 — commit / deterministic playback

Goal: game becomes the actual product concept.

Tasks:

- save canonical initial mission state;
- reset mission;
- execute recorded plan without user steering;
- guards/security run from same deterministic timeline;
- success/failure result;
- failure timestamp and cause;
- return to editable plan.

Acceptance:

- same plan gives same result on repeated runs;
- change one action/timing and result changes predictably.

## Phase 12 — first polished vertical slice

Goal: a small mission that looks and feels shippable.

Suggested content:

- 3–5 rooms;
- office-style environment;
- one thief;
- one guard;
- one rotating camera;
- one locked door;
- one switch/security dependency;
- one laser or alarm;
- one safe;
- mission objective;
- extraction;
- polished lighting/materials/animation;
- proper HUD;
- sound effects;
- failure/retry UX.

This is not a grey-box milestone. It is the first slice used to decide whether the game is genuinely fun.

## Phase 13 — noise and evidence

Goal: add the original-series mechanic that actions have delayed consequences.

Tasks:

- noise events;
- guard hearing;
- quiet vs noisy tool tradeoffs;
- broken/forced door state;
- open container state;
- guard inspection routine;
- delayed alarm if evidence discovered.

Acceptance:

- plan can fail because a guard later finds evidence even though nobody saw the thief directly.

## Phase 14 — tools and skills

Goal: turn interactions into crew/loadout decisions.

Tasks:

- lock difficulty;
- safe difficulty;
- security difficulty;
- actor skill model;
- tool modifiers;
- action-time calculation;
- noise/damage/weight properties;
- simple tool-selection UI.

Keep formulas transparent and data-driven.

## Phase 15 — second playable actor

Goal: prove synchronized planning.

Tasks:

- actor selection;
- separate timeline tracks;
- concurrent movement/actions;
- actor A controls remote security for actor B;
- synchronized execution;
- failure diagnostics across actors.

Acceptance mission primitive:

```text
A activates timed switch at 00:20
B must cross barrier by 00:27
```

## Phase 16 — level authoring workflow

Goal: creating Level 2 should be dramatically faster than Level 1.

Tasks:

- reusable RCP prototypes/assets;
- reusable custom components;
- inspector configuration;
- stable IDs;
- security graph authoring;
- patrol authoring;
- objective authoring;
- validation tool/checks if needed.

Measure how much custom Swift is required per mission. Target: almost none for ordinary levels.

## Phase 17 — campaign design

Only after the vertical slice and authoring workflow work.

Use `docs/ORIGINAL_GAMES_RESEARCH.md` as inspiration for complexity progression, but create original maps and mission stories.

Suggested campaign progression:

1. patrol + simple theft;
2. hiding + inspection;
3. noise/tool tradeoff;
4. safe specialist;
5. alarm;
6. camera + switch;
7. timed laser;
8. evidence cleanup;
9. multi-actor remote assistance;
10. cross-linked systems;
11. key/keycard dependency chain;
12. museum/gallery-style multi-stage security;
13. bank-like large heist;
14. rescue objective;
15. sabotage objective;
16. advanced multi-team mission;
17. near-finale systems remix;
18. integrated final mission.

Number of shipping missions is not fixed.

## Phase 18 — metagame

Evaluate only after core heists are fun.

Potential features:

- crew recruitment;
- tool purchase/upgrades;
- target selection;
- loot sale;
- reputation;
- narrative hub;
- cars/getaway capacity.

Do not recreate slow city walking just because the original had it. Mobile pacing should prioritize the heists.

## Phase 19 — productization

- save/progress;
- Game Center if useful;
- achievements;
- accessibility;
- localization;
- performance pass;
- audio/music;
- onboarding;
- App Store screenshots/video;
- monetization decision;
- TestFlight;
- analytics only if useful and privacy-appropriate.

## Immediate next instruction to Claude

Claude should begin with **Phase 0**, then perform the smallest viable experiments for Phases 1–2 before building broader game architecture.

Do not generate dozens of placeholder systems or missions before the RealityKit camera/navigation path is proven on-device.