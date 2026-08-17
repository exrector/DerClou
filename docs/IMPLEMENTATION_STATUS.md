# Implementation Status

Last updated: 2026-08-17. Covers issue #1 (Phase 0–2), plus the move off iOS 27.

## Summary

The native iOS 27 project exists, builds, runs on the iOS 27 simulator, renders a
real 3D office location under an orthographic top-down camera, bakes a navigation
mesh at runtime, resolves screen taps to world positions, and walks an actor along
a computed path around a solid wall at a constant speed.

One deliberate extension beyond the literal issue text: the test location is not
hard-coded scene setup. It is built from a `LevelBlueprint` value through a
reusable pipeline, so a second level costs data rather than Swift. This was agreed
with the owner before implementation. See "Level authoring model" below.

## Toolchain actually used

| Component | Version | Notes |
|---|---|---|
| Deployment target | **iOS 18.0** | lowered from 27.0 on 2026-08-17 |
| Xcode | **26.6 release works** | the beta is no longer required — see below |
| iOS SDK | 26.5 or 27.0 | both build the project |
| Swift | 6.4 | package builds in language mode 6 (`HeistCore`) and 5 (`HeistKit`) |
| Reality Composer Pro | 3.0 Beta 4 | standalone at `/Applications/RealityComposerPro.app`, **not** bundled inside Xcode-beta |
| macOS | 27.0 (26A5406e) | |
| Simulator | iPhone 17 Pro, iOS 27.0 (24A5355p) | |

### Why iOS 18 and not lower

Measured against the installed SDK, API by API:

| API | Minimum iOS |
|---|---|
| `RealityView`, `RealityViewCameraContent` | **18.0** |
| `OrthographicCameraComponent` | **18.0** |
| `InputTargetComponent` | 18.0 — no longer used |
| `PhysicallyBasedMaterial`, `System` | 15.0 |
| `CollisionComponent`, `Scene.raycast`, `Entity.look`, `PerspectiveCameraComponent` | 13.0 |
| `NavigationMesh*` / `NavigationController` | 27.0 — replaced by our own A* |

So the floor is set by exactly three APIs, all of them core to the look. Going
lower would mean `ARView(.nonAR)` plus a narrow-FOV perspective camera imitating
orthographic — rejected, because converging verticals are precisely wrong for a
tactical plan view. `CameraProjection.perspective` exists in the code as a
documented escape hatch, not as the default.

**iOS 18 is an API floor, not an art budget.** Nothing in the rendering, art
direction, level complexity or gameplay is cut for it; `RenderQuality` scales
light count and shadow cost *up* on capable hardware.

Consequence: builds produced now cannot be submitted to App Store Connect
(ITMS-90111 rejects beta-built binaries). Irrelevant for development, relevant
before any TestFlight distribution.

### Toolchain

Dropping the iOS 27 navigation APIs had a second payoff beyond audience: the
project now **builds and tests with the released Xcode 26.6**, verified against
the iOS 18.6 simulator. Consequences:

- no beta toolchain needed for day-to-day work;
- Xcode Cloud can build it — it only has released Xcode;
- ITMS-90111 (App Store rejects beta-built binaries) no longer applies.

A connected device also has to be genuinely available: `xcrun devicectl list
devices` reports `unavailable` when it is merely paired. Cable, unlocked screen,
trusted computer.

Build and test:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project DerClou.xcodeproj -scheme DerClou -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Pure-logic tests run without a simulator, in about 2 ms:

```bash
cd Packages/HeistEngine && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test
```

## Project structure

```text
DerClou.xcodeproj          objectVersion 77, synchronized file groups
DerClouApp/                app shell: DerClouApp.swift, GameScreen.swift, Info.plist
DerClouTests/              runtime tests that need RealityKit
Packages/HeistEngine/      local Swift package, where the engine lives
  Sources/HeistCore/       pure Swift: no RealityKit, no UI, no I/O
    Geometry/              LevelMetrics, primitives, CameraFramingSolver, ScreenProjection
    Level/                 LevelBlueprint, WallSpec, LevelGeometry, LevelValidator, NavigationBudget
    Catalog/               PropCatalog, PropPrototype
    Navigation/            NavigationSourceMeshBuilder
    Levels/                Level01 (office01) as data
  Sources/HeistKit/        RealityKit runtime
    Components/            LevelEntity, NavigableSurface, PlayableActor, PathFollowing, Interactable
    Systems/               PathFollowingSystem
    Scene/                 GreyboxKit, LevelSceneBuilder, TacticalCamera
    Navigation/            NavigationBaker
    Session/               GameSession
    Views/                 HeistSceneView
  Tests/HeistCoreTests/    43 tests
```

The split is the point: everything that decides *game outcomes* lives in
`HeistCore` and is testable in milliseconds without a device.

## Level authoring model

A level is a `LevelBlueprint` value:

- **floors** — rectangles that define the walkable surface;
- **walls** — a line from A to B plus a list of openings (`doorway`, `window`,
  `passage`). `WallSpec.segments(metrics:)` cuts the holes and puts lintels and
  sills back, deterministically;
- **props** — instances of catalog prototypes with position, yaw and per-instance
  config overrides;
- **actors** — placements plus patrol routes;
- **markers** — spawn, extraction, camera focus;
- **security** — directed links (`source -> target`, effect `power` / `unlock` /
  `disarm` / `alarmTrigger`), already in the schema so levels authored today stay
  valid when the security system lands.

Coordinates are authored in **cells**, converted to meters in exactly one place
(`LevelMetrics`). Default cell is 1.0 m, wall height 2.6 m, wall thickness 0.2 m,
doorway 0.9 × 2.1 m, character 1.75 m tall / 0.6 m wide, walk speed 1.4 m/s.

Behaviour never lives in a level. A prototype in `PropCatalog` declares its
footprint, surface, whether it blocks movement, which interactions it supports
and its default config. That is what makes new levels composable from existing
mechanics: the level says *what and where*, the catalog says *what it can do*.

`LevelValidator` rejects broken data before anything is built: openings past the
end of a wall, overlapping openings, unknown prototypes, duplicate IDs, actors
spawned off-floor, security links pointing at entities that do not exist.

The blueprint is `Codable` and survives a JSON round-trip (tested), so an external
generator or editor can emit levels without touching the app.

## What actually worked in the SDK

### `OrthographicCameraComponent`

Works. Available since iOS 18, not new in 27.

**Undocumented behaviour found by measurement:** `scale` is the **half** extent of
the view along `scaleDirection`, not the full extent. Framing a 10 m building with
`scale = 12.9` produced a view covering ~25.9 m. `TacticalCamera` divides by two.

Chosen presentation: tilt **24°** off straight down, vertical `scaleDirection`,
1 m margin around the level. Strict top-down reads flat; 24° shows enough wall and
prop sides to convey volume without tall geometry occluding the floor behind it.
`near = 0.05`, `far = 200`, camera 60 m back (irrelevant to scale under
orthographic projection).

Framing has two modes. `.fit` shows the whole level and letterboxes whatever does
not match; `.fill` (the default) uses the entire display. Filling only works
without cutting playfield if the level is shaped roughly like the device, which is
why **office01 is 24 × 10 m** rather than square — the building's proportions are a
framing decision, not only a design one. `CameraFraming.croppedDepth` /
`croppedWidth` report what a given level loses, a warning is logged at runtime when
anything is cropped, and a test asserts office01 loses nothing on a landscape
phone.

### Navigation — our own, not RealityKit's

The iOS 27 navigation APIs work, and the mesh does bake at runtime from arbitrary
triangles. They were still removed, for two independent reasons.

**They were wrong for the geometry.** A voxelising baker is fed the whole scene
and infers walkability from surface slope. It therefore treats the top of a wall
and a desktop as walkable ledges, and it takes the segment *above* a doorway —
the lintel — as solid all the way down. Symptoms seen in play: actors walking
through walls, rooms unreachable from each other, actors tripping over furniture.

**They cost four OS generations.** They are the only thing that required iOS 27.

Replaced by `NavGrid` + `PathFinder` in `HeistCore`:

- the grid is built from the blueprint's own boxes, and an obstacle only counts
  if it occupies `0 ..< characterHeight` — a lintel at 2.1–2.6 m does not;
- obstacles are dilated by the character radius, so any route along cell centres
  automatically clears walls;
- eight-way A* with no corner cutting, then line-of-sight smoothing to remove the
  grid staircase;
- pure Swift, no simulator needed, deterministic by construction — the same
  request always returns the same path, which is what a recorded plan depends on.

`LevelValidator` now also flood-fills the grid from the spawn point and reports
anything cut off. That caught a real bug immediately: the store room's safe was
placed beside its door, and once the character radius was added it sealed the
room. A level file gives no hint of that; only walking it does.

Measured on office01: 336 source triangles (28 boxes) → 80 navigation polygons.

**Doorway width is a navigation constraint, not a cosmetic choice.** The bake
voxelises the world and erodes the walkable area by the character radius, so a
1.0 m opening with a 0.3 m radius keeps only 0.4 m — four voxels at the original
0.05 m cell size, which bakes into a ragged polygon that actors jam in, especially
when approaching at an angle. Two changes came out of that:

- bake resolution raised to 0.05 m cells;
- `NavigationBudget` in `HeistCore` encodes the rule, and `LevelValidator` now
  warns when an opening is too narrow to survive the bake and errors when it is
  narrower than the character. office01's doorways are 1.2 m.

`PathFollowingSystem` also carries a stall watchdog: an actor that makes no
progress for 1.5 s logs which waypoint it is stuck at and abandons the path,
rather than standing still with no explanation.

`NavigationMeshResource` also exposes `Area`, `Flag`, `Layer`, per-polygon marking
and `OffMeshConnection`, plus `NavigationComponent.Filter` with area costs and
include/exclude flags. That is a ready-made vocabulary for locked doors,
staff-only routes, vents and windows — worth using rather than reinventing.

### Tap input

`SpatialTapGesture().targetedToAnyEntity()` was the first approach and **never
fired**. It only reports taps that RealityKit's input stack matches to an entity,
and that never happened in this orthographic non-AR scene even with floors
carrying both `CollisionComponent` and `InputTargetComponent`.

What works instead, and is now the design:

1. a plain SwiftUI `.onTapGesture { location in }` on the `RealityView`;
2. `ScreenProjection.ray(screenPoint:viewportSize:framing:)` in `HeistCore`
   builds the world ray by hand from the camera framing we already compute —
   orthographic projection makes this exact, and it is unit tested including a
   screen-to-world-to-screen round trip;
3. `ScreenProjection.hit(_:planeY:)` intersects the floor plane;
4. `Scene.raycast(origin:direction:length:)` finds what the ray passes through,
   which is independent of the input stack and does work.

Second cause, found by the owner: the debug HUD was swallowing taps. It is now
`.allowsHitTesting(false)` — verified by tapping directly on the HUD panel and
watching the tap resolve to the floor underneath it.

Measured on the simulator: tap at (600, 201) resolved to world (12.24, 5.00) and
produced a 2.70 m path; a tap under the HUD at (700, 40) resolved to world
(15.46, −0.67) — outside the building — and navigation clamped it to the nearest
reachable point, producing a valid 11.54 m path rather than failing.

### Movement

`PathFollowingSystem` interpolates along path nodes at a constant configured speed
and yaws the actor toward travel. No physics forces, so arrival time is a pure
function of path length and speed. Verified: 12.46 m at 1.4 m/s reported ETA 8.9 s.

### RealityView on iOS

`RealityViewCameraContent` with `content.camera = .virtual` gives a non-AR scene,
no ARKit session, no device motion. Confirmed working.

## Differences from the research notes

1. Reality Composer Pro 3 is a **separate application**, not bundled inside
   Xcode-beta 27.0 as `Reality Composer Pro.app` was in Xcode 26.
2. `EntityTargetValue` on iOS has **no** `convert(_:from:to:)` and no
   `location3D` member — those are visionOS APIs. On iOS use
   `ray(through:in:to:)` or `unproject(_:to:)`. In practice none of this matters,
   because entity-targeted gestures never fired at all (see "Tap input").
3. `OrthographicCameraComponent.scale` is a half extent (above).
4. `Entity` has no `.collision` property; that is `HasCollision` on `ModelEntity`.
   Use `components.set(CollisionComponent(...))`.
5. `MeshResource.generateCapsule` does not exist — `ShapeResource.generateCapsule`
   does (collision only). Visual capsules must be composed from primitives.

## Known problems

1. **`NavigationController.computePath` never returns in a headless test.** A
   bare `ARView` is enough to bake a mesh but not to service a path request, so
   the runtime test hangs until timeout. That test is `.disabled` with a note. If
   an automated route check is wanted, it needs a UI test with a rendered scene.

2. **Doorway jams are mitigated, not proven fixed.** Openings are wider, the
   bake is finer and the validator enforces the rule, but the original symptom
   was only reproducible by hand. If an actor still wedges, the movement log now
   names the waypoint — check `category: movement`.

3. **Taps outside the building still produce a route.** Navigation clamps an
   unreachable target to the nearest mesh point instead of rejecting it. Fine for
   now, but planning will need an explicit "not navigable" answer so a player
   cannot schedule a move to a place they cannot stand.

4. Actor visuals are placeholder primitives (cylinder body, sphere head, nose cone
   for facing). No skeletal animation yet; movement is decoupled from geometry so
   a rigged character drops in without touching navigation.

5. Only one actor is player-controlled. The guard is placed and has a route in the
   blueprint, but nothing walks it yet.

6. `UIRequiresFullScreen` was removed from Info.plist — deprecated in iOS 26.

7. Injecting input into a `simctl`-booted device with no open Simulator window
   silently does nothing — taps and even the HOME button are ignored. Open the
   Simulator window before trying to drive the app.

## Acceptance criteria for issue #1

| Criterion | Status |
|---|---|
| Native iOS 27 Xcode project in the repository | done |
| Project builds from a clean checkout | done |
| Launching shows a real 3D office-like scene | done |
| Tactical camera gives top-down / 2.5D presentation | done, 24° tilt |
| Tapping valid floor sends the actor there via navmesh | done, confirmed on simulator |
| Actor routes around an obstacle instead of through it | done — 12.46 m path vs 11.34 m straight line |
| Movement uses a constant configured speed | done, 1.4 m/s |
| No joystick | done |
| No paid dependency | done |
| Architecture ready for door / guard / vision | done — components and security schema in place |

## Recommended next task

**Build the generic interaction framework (Phase 3).**

Concretely:

1. Run once on a real iPhone to confirm the presentation at true device scale and
   frame rate; everything so far is simulator-verified only.
2. Implement `InteractionSystem`: tap an interactable → walk to its approach point
   → run the interaction for its configured duration → emit an event. The
   `InteractableComponent` and the catalog's `interactions` list already exist;
   what is missing is approach points and a duration model.
3. Then the door (Phase 4): `DoorComponent` with open/locked state, hinge
   animation, and — importantly — re-baking or flagging the navigation mesh when
   a door's passability changes. `NavigationMeshResource.markFlagInBox` plus
   `NavigationComponent.Filter` looks like the intended mechanism; verify it before
   designing around it.

Do not start guards or vision until interaction and doors are solid.

## Xcode Cloud

The repository is connected to Xcode Cloud, with one product (`DerClou`) and one
workflow (`Default`). The workflow triggered on **any branch**, so every push
started a build; those builds failed with "Project DerClou.xcodeproj does not
exist at the root of the repository" simply because the Xcode project had not
been pushed yet.

**The workflow is now disabled** (`isEnabled = false`, 2026-08-17) at the owner's
request: Xcode Cloud is wanted for the eventual App Store build, not for every
commit during development. Nothing was deleted — re-enable it when a release is
actually being cut.

Two things worth knowing for later:

- the `DerClou` product is **CI-only** (no App Store Connect app record yet), and
  products in that state are *not* returned by `GET /v1/ciProducts`. It is
  invisible to the API until an app record exists. The product and workflow IDs
  can be read out of Xcode's local cache at
  `~/Library/Developer/Xcode/UserData/XcodeCloud/XcodeCloudCoreDataModel-v12.sqlite`
  (`ZPRODUCTENTITY`, `ZWORKFLOWSUMMARYENTITY`);
- product `0f533374-52cf-4085-b811-49ea543d829b`, workflow
  `12DE6FC8-0C5A-4746-8FFF-61FB762ACF53`. Toggling it:

```bash
TOKEN=$(python3 ~/.appstoreconnect/asc_jwt.py)
curl -sg -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"data":{"type":"ciWorkflows","id":"12DE6FC8-0C5A-4746-8FFF-61FB762ACF53","attributes":{"isEnabled":true}}}' \
  "https://api.appstoreconnect.apple.com/v1/ciWorkflows/12DE6FC8-0C5A-4746-8FFF-61FB762ACF53"
```
