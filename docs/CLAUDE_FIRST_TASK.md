# Claude Code — first implementation task

Use this file as the first concrete implementation brief.

## Before writing code

Read in this order:

1. `README.md`
2. `CLAUDE.md`
3. `docs/DECISIONS.md`
4. `docs/GAME_DESIGN.md`
5. `docs/TECHNICAL_ARCHITECTURE.md`
6. `docs/ART_DIRECTION.md`
7. `docs/ORIGINAL_GAMES_RESEARCH.md`
8. `docs/SOURCES.md`
9. `docs/ROADMAP.md`

Do not ask the owner to restate the project premise if these documents answer the question.

## Objective

Start the real native Apple project and prove the two highest-risk foundations:

1. a true 3D top-down tactical scene that visually reads correctly on iPhone;
2. tap-to-move navigation using the current iOS 27 RealityKit / Reality Composer Pro 3 APIs.

Do **not** attempt the entire game in this first task.

## Fixed stack

- iOS 27+
- Swift
- SwiftUI
- RealityKit
- Reality Composer Pro 3
- Xcode

No Unity, Godot, SpriteKit, SceneKit or paid third-party runtime/framework.

## Required work

### 1. Bootstrap the Xcode project

Create a clean iPhone application project suitable for the game.

Requirements:

- SwiftUI app shell;
- RealityKit scene hosted correctly inside the app;
- Reality Composer Pro 3 content integrated using the current recommended Apple workflow;
- landscape-first game presentation;
- basic test target;
- repository builds from a clean checkout.

Use the current installed Xcode/iOS 27 SDK signatures. If repository documentation and the SDK disagree, treat the installed SDK/current Apple documentation as authoritative and record the discrepancy.

### 2. Create a small real 3D test location

Create one small office-like test environment sufficient to evaluate the final rendering architecture:

- floor;
- several walls forming at least two rooms and a corridor;
- one doorway;
- a few simple 3D placeholder props such as desk/cabinet/safe/camera.

Temporary primitive geometry is acceptable for this engineering experiment only. Do not interpret primitive art as the final art direction.

Use real materials, lighting and shadows so the test actually exercises the 3D pipeline.

### 3. Implement the tactical camera

Use `OrthographicCameraComponent` if the current iOS 27 SDK supports it as expected.

Target behavior:

- high top-down tactical view;
- level reads almost like a 2D plan while retaining 3D volume and shadows;
- enough visible side faces/depth to avoid looking flat;
- stable framing in landscape;
- no AR session and no device-motion camera.

Test strict top-down versus a small fixed tilt if needed. Choose the most readable result and document the chosen transform/settings.

### 4. Implement tap-to-world

A tap on navigable floor must resolve to a correct world-space destination.

Requirements:

- ignore UI taps;
- reject/handle non-navigable hits cleanly;
- display a temporary destination marker for debugging;
- log the resolved world position in debug builds.

### 5. Implement navigation mesh and one playable actor

Use the current RealityKit / Reality Composer Pro 3 navigation workflow rather than inventing A* unless Apple's API proves unusable.

Requirements:

- author/generate navigation mesh for the test location;
- one playable actor entity;
- tapping navigable floor requests a path;
- actor walks around walls/obstacles to the target;
- constant movement speed;
- actor faces its movement direction;
- retapping a new destination updates/cancels the current movement safely;
- movement must not depend on dynamic physics forces.

If a rigged character is not yet available, a clearly identifiable 3D capsule/placeholder actor is acceptable for this navigation experiment. Keep the code ready for later skeletal Idle/Walk animation rather than coupling movement to the placeholder geometry.

### 6. Keep the implementation reusable

Do not put all code in one SwiftUI view.

Use the smallest sensible separation for:

- game scene/session setup;
- input/tap handling;
- selected actor/navigation state.

Do not create dozens of empty components/systems from the architecture document yet.

### 7. Build and test

Use Xcode agent/build tools to:

- compile the project;
- fix warnings/errors introduced by this work;
- run available tests;
- run the scene in Simulator and/or on an iPhone target if available;
- verify repeated navigation taps.

Do not finish with uncompiled pseudocode.

## Acceptance criteria

This task is complete only when:

- the repository contains a native iOS 27 Xcode project;
- the project builds successfully;
- launching it displays a real 3D office-like scene;
- the tactical camera gives the intended top-down/2.5D presentation;
- tapping valid floor sends the actor there through navigation mesh pathfinding;
- the actor routes around at least one obstacle/wall instead of walking straight through it;
- movement uses a constant configured speed;
- there is no joystick;
- no paid dependency/service has been introduced;
- architecture remains ready for the next systems: door, deterministic guard and vision.

## Deliverable report

At completion, write/update a short `docs/IMPLEMENTATION_STATUS.md` containing:

- what was implemented;
- exact Xcode/iOS SDK versions used;
- current project structure;
- which Apple navigation APIs actually worked;
- any API differences discovered versus our research notes;
- simulator/device build status;
- known technical problems;
- screenshots or capture references if practical;
- exact recommended next task.

## Stop conditions / blockers

If a fundamental current-SDK limitation prevents the planned RealityKit navigation or orthographic-camera approach:

1. verify it against current Apple documentation and the installed SDK;
2. build the smallest experiment necessary to confirm the blocker;
3. document the exact failure/API limitation;
4. do not silently replace the stack with another game engine;
5. propose the narrowest native Apple fallback.

The owner wants blockers surfaced immediately, not after a large amount of unrelated implementation work.