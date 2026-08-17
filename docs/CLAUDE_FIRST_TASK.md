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
9. `docs/PLATFORM_COMPATIBILITY.md`
10. `docs/ROADMAP.md`

Do not ask the owner to restate the project premise if these documents answer the question.

## Objective

Start the real native Apple project and prove the two highest-risk foundations:

1. a true 3D top-down tactical scene that visually reads correctly on iPhone;
2. deterministic tap-to-move navigation compatible with the **iOS 18 deployment floor**.

**(Старый вариант: prove tap-to-move using the current iOS 27 RealityKit / Reality Composer Pro 3 Navigation Mesh APIs.)**

Do **not** attempt the entire game in this first task.

## Fixed stack

- **iOS 18+**
- Swift
- SwiftUI
- RealityKit
- Reality Composer Pro 3
- Xcode

**(Старый вариант: iOS 27+.)**

No Unity, Godot, SpriteKit, SceneKit or paid third-party runtime/framework.

## Required work

### 1. Bootstrap the Xcode project

Create a clean iPhone application project suitable for the game.

Requirements:

- SwiftUI app shell;
- RealityKit scene hosted through the current iOS 18-compatible SwiftUI `RealityView` path;
- Reality Composer Pro 3 content integrated using a workflow whose runtime output remains compatible with iOS 18;
- landscape-first game presentation;
- basic test target;
- repository builds from a clean checkout.

Use the current installed Xcode SDK signatures while keeping the deployment target at iOS 18. If repository documentation and the SDK disagree, treat the installed SDK/current Apple documentation as authoritative and record the discrepancy.

### 2. Create a small real 3D test location

Create one small office-like test environment sufficient to evaluate the final rendering architecture:

- floor;
- several walls forming at least two rooms and a corridor;
- one doorway;
- a few simple 3D placeholder props such as desk/cabinet/safe/camera.

Temporary primitive geometry is acceptable for this engineering experiment only. Do not interpret primitive art as the final art direction.

Use real materials, lighting and shadows so the test actually exercises the 3D pipeline.

### 3. Implement the tactical camera

Use `OrthographicCameraComponent` with `RealityView` and a virtual RealityKit camera.

Target behavior:

- high top-down tactical view;
- level reads almost like a 2D plan while retaining 3D volume and shadows;
- enough visible side faces/depth to avoid looking flat;
- stable framing in landscape;
- no AR session and no device-motion camera.

Do not replace the orthographic camera with a perspective-camera approximation merely to support older OS versions. **(Старый fallback idea: ARView `.nonAR` + narrow-FOV perspective camera for iOS 17 or earlier.)**

Test strict top-down versus a small fixed tilt if needed. Choose the most readable result and document the chosen transform/settings.

### 4. Implement tap-to-world

A tap on navigable floor must resolve to a correct world-space destination.

Requirements:

- ignore UI taps;
- reject/handle non-navigable hits cleanly;
- display a temporary destination marker for debugging;
- log the resolved world position in debug builds.

### 5. Implement project-owned navigation and one playable actor

Do **not** make the vertical slice depend on iOS 27 `NavigationMesh*` / `NavigationController` APIs.

Build a thin `NavigationService` / equivalent abstraction and evaluate the smallest appropriate implementation using Apple GameplayKit (`GKGridGraph`, `GKObstacleGraph`, `GKMeshGraph`, `GKGraph.findPath`) or a deterministic custom A* if it clearly fits the mission geometry better.

**(Старый вариант: author/generate an RCP3 navigation mesh and use RealityKit `NavigationController`.)**

Requirements:

- one playable actor entity;
- tapping navigable floor requests a deterministic path;
- actor walks around walls/obstacles to the target;
- constant movement speed;
- actor faces its movement direction;
- retapping a new destination updates/cancels the current movement safely;
- dynamic door state can eventually update navigation without rebuilding the whole gameplay architecture;
- movement must not depend on dynamic physics forces;
- same start + same destination + same world state should produce the same selected route unless the navigation configuration explicitly changes.

If a rigged character is not yet available, a clearly identifiable 3D capsule/placeholder actor is acceptable for this navigation experiment. Keep the code ready for later skeletal Idle/Walk animation rather than coupling movement to the placeholder geometry.

### 6. Keep the implementation reusable

Do not put all code in one SwiftUI view.

Use the smallest sensible separation for:

- game scene/session setup;
- input/tap handling;
- selected actor/navigation state;
- navigation abstraction.

Do not create dozens of empty components/systems from the architecture document yet.

### 7. Preserve visual ambition

The iOS 18 deployment floor is not permission to downgrade the game into programmer art or a legacy-looking renderer.

Do not simplify:

- PBR/material target;
- lighting direction;
- real 3D geometry;
- orthographic presentation;
- animation architecture;
- level/system complexity.

If actual older supported hardware requires rendering adaptation, first measure the bottleneck and document a quality-tier solution. Do not silently redesign the game around weak hardware.

### 8. Build and test

Use Xcode agent/build tools to:

- compile the project;
- fix warnings/errors introduced by this work;
- run available tests;
- run the scene in Simulator and/or on an iPhone target if available;
- verify repeated navigation taps;
- verify the deployment target remains iOS 18.

Do not finish with uncompiled pseudocode.

## Acceptance criteria

This task is complete only when:

- the repository contains a native **iOS 18+** Xcode project; **(Старый вариант: native iOS 27 project.)**
- the project builds successfully;
- launching it displays a real 3D office-like scene;
- the tactical camera gives the intended true orthographic top-down/2.5D presentation;
- tapping valid floor sends the actor there through deterministic project-owned pathfinding; **(Старый вариант: Navigation Mesh pathfinding.)**
- the actor routes around at least one obstacle/wall instead of walking straight through it;
- movement uses a constant configured speed;
- there is no joystick;
- no paid dependency/service has been introduced;
- no iOS 27-only navigation API is required for the basic game loop;
- architecture remains ready for the next systems: door, deterministic guard and vision.

## Deliverable report

At completion, write/update a short `docs/IMPLEMENTATION_STATUS.md` containing:

- what was implemented;
- exact Xcode/iOS SDK versions used;
- minimum deployment target actually built/tested;
- current project structure;
- which navigation implementation was chosen and why;
- any API differences discovered versus our research notes;
- simulator/device build status;
- known technical problems;
- screenshots or capture references if practical;
- exact recommended next task.

## Stop conditions / blockers

If a fundamental current-SDK limitation prevents the planned iOS 18 `RealityView` + true orthographic-camera approach:

1. verify it against current Apple documentation and the installed SDK;
2. build the smallest experiment necessary to confirm the blocker;
3. document the exact failure/API limitation;
4. do not silently replace the stack with another game engine;
5. do not silently replace the orthographic camera with perspective approximation;
6. propose the narrowest native Apple fallback and state the visual/product cost explicitly.

The owner wants blockers surfaced immediately, not after a large amount of unrelated implementation work.
