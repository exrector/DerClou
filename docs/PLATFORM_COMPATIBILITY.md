# Platform compatibility and API floor

Status: verified architecture note

Last reviewed: **2026-08-17**

Purpose: define the minimum operating-system target for the game from the actual API set we need, not from RealityKit as a framework in general.

## Current decision

The project targets **iOS 18+**.

**(Старый вариант: iOS 27+ was selected because the project initially intended to use the newest RealityKit Navigation Mesh / `NavigationController` stack directly.)**

The reason for iOS 18 is not visual simplification. It is the lowest current target that preserves the intended modern RealityKit rendering architecture around SwiftUI `RealityView`, a virtual RealityKit camera and a true `OrthographicCameraComponent` while avoiding an iOS-27-only navigation dependency.

Supporting iOS 18 must **not** reduce the intended production art direction, gameplay complexity, animation quality, lighting, materials or level design. Performance adaptation should happen through measured device-quality tiers if needed.

---

## Verified Apple API facts

### RealityKit itself predates iOS 18

RealityKit as a framework is much older than iOS 18. Therefore the minimum deployment target cannot be inferred from the framework name alone. The target must be derived from the exact APIs used by this game.

### `RealityView`

For iPhone/iPad, the modern SwiftUI `RealityView` path used by this project belongs to the iOS/iPadOS 18 generation. Apple's iOS 18 release notes explicitly discuss `RealityView` behavior on iOS/iPadOS 18, including the `environment` property and world-tracking behavior.

Project rule: use `RealityView` as the primary RealityKit host on iOS 18+.

**(Старый вариант: deployment target iOS 27 because the whole modern RealityKit navigation stack was treated as one package.)**

### `RealityViewCamera` / virtual camera

Apple documents `RealityViewCamera` as a camera for RealityView scenes and exposes `.virtual` for displaying purely virtual RealityKit content.

This is the correct conceptual mode for our game: a fully virtual 3D game world, not AR passthrough.

### `OrthographicCameraComponent`

Apple documents `OrthographicCameraComponent` as a true orthographic virtual camera. In orthographic projection, distant entities do not become smaller simply because they are farther from the camera.

This property is central to the intended tactical-plan visual language. The game remains real 3D — geometry, materials, lighting, shadows and animations remain 3D — but the camera can read like a clean tactical map.

Project rule: keep the true orthographic camera.

Do **not** lower the OS target by replacing it with a perspective camera purely to gain older-device compatibility unless the owner explicitly reopens this product decision.

### `ARView(.nonAR)` is not equivalent to our chosen camera path

Apple documents `ARView.CameraMode.nonAR` as a fully virtual environment with no relationship to the real world.

However Apple also documents that, outside an AR session, `ARView` uses a `PerspectiveCamera` by default. This makes `ARView(.nonAR)` a valid older RealityKit virtual-3D host, but not a drop-in equivalent for our true orthographic tactical view.

**(Старый fallback idea: support iOS 17 or earlier through `ARView(.nonAR)` and approximate the top-down look with a narrow-FOV perspective camera. Rejected as the current production path because it compromises the exact camera model we selected.)**

---

## Navigation / tap-to-move

Tap-to-move does **not** require iOS 27.

Apple's GameplayKit provides long-standing navigation graph APIs:

- `GKGraph`
- `GKGridGraph`
- `GKObstacleGraph`
- `GKMeshGraph`
- `GKGraphNode2D` / `GKGraphNode3D`
- `findPath(from:to:)`

Apple describes these APIs specifically as pathfinding tools for game worlds. `GKGraph.findPath(from:to:)` computes a shortest traversal through the graph.

Therefore the project should own a navigation abstraction independent of the newest RealityKit navigation stack.

Candidate implementations:

1. `GKGridGraph` for a grid-based representation;
2. `GKObstacleGraph` for continuous 2D movement around obstacle outlines;
3. `GKMeshGraph` where a space-filling 2D graph is useful;
4. custom deterministic A* if our mission geometry/data model benefits from full control.

Do not choose the final representation by fashion. Build a small navigation benchmark using actual room/corridor geometry and compare path quality, determinism, authoring cost and dynamic-door updates.

**(Старый вариант: RCP3 Navigation Mesh + RealityKit `NavigationController`, requiring the iOS 27 generation of navigation APIs.)**

---

## Why this does not make the game visually primitive

Deployment target and visual target are separate concerns.

The iOS 18 build may still use the full intended production design:

- real 3D geometry;
- PBR materials;
- detailed reusable models;
- skeletal character animation;
- articulated doors/safes/cabinets;
- rotating 3D security cameras;
- dynamic/procedural laser and alarm effects;
- real lighting and shadows;
- high-resolution UI and tactical overlays;
- complex deterministic levels;
- multi-character plans and security dependency graphs.

If lower-end supported devices fail performance budgets, introduce explicit capability tiers for expensive rendering features. Examples may include shadow resolution, number of dynamic shadow casters, particle density, texture resolution or nonessential effects. Do not alter the core rules or deliberately make the art primitive.

---

## Reality Composer Pro 3 policy under iOS 18

Reality Composer Pro 3 remains the visual authoring tool for scenes and assets.

Use it for:

- scene construction;
- asset placement;
- materials;
- lighting;
- reusable 3D content;
- animation content whose runtime requirements are compatible with iOS 18;
- authoring metadata/anchors used by our own Swift navigation and game systems.

Do not assume every newest RCP3 graph/runtime feature supports the iOS 18 floor merely because the editor itself can create it. Check the generated/runtime API availability before making that feature part of the production pipeline.

**(Старый вариант: because the game targeted iOS 27, newest RCP3 Navigation Mesh, Script Graph and other current runtime features could be adopted without considering an older deployment floor.)**

---

## Required architecture

```text
SwiftUI
  └── RealityView                 iOS 18+ game host

RealityKit
  ├── OrthographicCameraComponent
  ├── entities / components / systems
  ├── rendering / materials / lighting
  ├── animation
  ├── collision / ray tests
  └── presentation of gameplay state

Navigation abstraction
  ├── GameplayKit graph implementation
  │     or
  └── deterministic custom A*

Swift simulation
  ├── plan timeline
  ├── guards
  ├── cameras
  ├── doors
  ├── alarms / lasers / switches
  ├── evidence / noise
  └── deterministic execution

Reality Composer Pro 3
  └── level / asset authoring compatible with the runtime floor
```

---

## Source references — Apple

- RealityKit `OrthographicCameraComponent`: https://developer.apple.com/documentation/realitykit/orthographiccameracomponent
- RealityKit `RealityViewCamera`: https://developer.apple.com/documentation/realitykit/realityviewcamera
- `ARView.CameraMode.nonAR`: https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar
- RealityKit `PerspectiveCamera`: https://developer.apple.com/documentation/realitykit/perspectivecamera
- GameplayKit: https://developer.apple.com/documentation/gameplaykit
- `GKGridGraph`: https://developer.apple.com/documentation/gameplaykit/gkgridgraph
- `GKGraph.findPath(from:to:)`: https://developer.apple.com/documentation/gameplaykit/gkgraph/findpath(from:to:)
- iOS & iPadOS 18 Release Notes: https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18-release-notes

---

## Change policy

Do not raise the minimum OS merely because a convenient new API exists.

Do not lower the minimum OS merely to increase the compatibility number if doing so requires replacing the true orthographic camera or otherwise degrading a fixed core visual/product decision.

When considering a newer API:

1. identify the exact benefit;
2. identify its actual deployment requirement;
3. determine whether the capability already exists through stable older APIs or a small project-owned implementation;
4. measure implementation/maintenance cost;
5. change the deployment target only if the product benefit clearly justifies the lost device coverage.
