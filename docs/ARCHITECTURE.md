# Architecture

The rules the codebase is built on. If a change would break one of these, that is
a decision to make deliberately, not a detail to work around.

Status as of 2026-08-17, after the audit that followed the iOS 27 → 18 move.

## 1. Three layers, one direction of dependency

```text
DerClouApp        SwiftUI shell: app entry, screens, HUD
     │  depends on
     ▼
HeistKit          RealityKit runtime: scene building, camera, input, systems
     │  depends on
     ▼
HeistCore         pure Swift: the rules of the game
```

`HeistCore` imports **only** Foundation. No RealityKit, no SwiftUI, no UIKit, no
I/O. That is the load-bearing rule of the whole project, and it buys three
things:

- everything that decides a game outcome is testable in milliseconds with no
  simulator (62 tests run in ~9 s, most of them in microseconds);
- the same code can be driven by a future level editor, generator or headless
  simulation without dragging a renderer along;
- a rendering change cannot silently alter gameplay.

Nothing in `HeistKit` may contain a game rule. If a system needs to decide
something — how far an actor moves, whether a door can be opened, whether a guard
sees you — that decision belongs in `HeistCore` and the system only applies it.

`PathFollowingSystem` is the reference example: it converts transforms to world
points, calls `PathWalker`, and writes the result back. The walking itself is
tested without RealityKit.

## 2. One source of truth per fact

Every quantity is written down exactly once, and everything else derives from it.

| Fact | Lives in | Derived from it |
|---|---|---|
| Character size and speed | `PropCatalog` prototype | `CharacterProfile` → navigation erosion, doorway validation, collision capsule, walk timing |
| Cell → meter conversion | `LevelMetrics` | every world position in the game |
| What an object can do | `PropPrototype.interactions` | interaction verbs offered on tap |
| Where objects are | `LevelBlueprint` | scene entities, walkability grid |
| Camera framing | `CameraFramingSolver` | camera transform *and* tap projection |

This was not free. Before the audit, the character's radius, height and walk
speed each existed in three places, so changing the actor in the catalog would
have left navigation built for the old body — a bug that only appears as an actor
stuck in a doorway, long after the edit. `CharacterProfileTests` now fails if that
link is ever broken again.

## 3. Levels are data, mechanics are code

A level is a `LevelBlueprint` value: floors, walls (a line plus openings), placed
prototypes, actors, markers, security links. It contains **no behaviour**.

A prototype in `PropCatalog` declares footprint, surface, whether it blocks
movement, which interactions it supports, and default config. Instances override
config per placement.

Adding a level must cost data. If it needs new Swift, the missing piece belongs
in the catalog or in a system — that is the test for whether this rule still
holds.

`LevelBlueprint` is `Codable` and survives a JSON round-trip, so a generator or
editor can emit levels without touching the app.

## 4. Preparation happens once

`LevelBuild.make(blueprint, catalog:)` is the single entry point. It derives the
navigation budget from the level's actors, builds the geometry, builds the
walkability grid, and validates — in that order, once.

`LevelSceneBuilder` consumes a prepared `LevelBuild`; it never recomputes. The
earlier version validated and rendered from two independently built copies of the
same geometry, which is both wasted work and a chance for the two to disagree.

## 5. Determinism is a requirement, not a nicety

The game's whole premise is that a plan can be trusted: study, plan, commit,
watch it run, learn from the failure. That collapses if the same plan can produce
different results.

Concretely:

- path finding breaks ties on a fixed ordering — same request, same path;
- movement is `distance / speed`, never physics, never frame-rate dependent —
  `PathWalkerTests` asserts a 60 Hz and a 30 Hz walk take the same time;
- geometry building is deterministic and asserted as such;
- no hidden randomness anywhere in the rules.

## 6. Broken levels fail loudly, before they are played

`LevelValidator` runs as part of every `LevelBuild`. It rejects: openings past the
end of a wall, overlapping openings, doorways too narrow to survive navigation
erosion, unknown prototypes, duplicate IDs, actors spawned off-floor, security
links pointing at nothing — and, by flood-filling the grid from the spawn point,
**anything cut off from the rest of the level**.

That last check exists because of a real bug: a safe placed beside its own door
sealed the store room once the character radius was accounted for. Nothing in the
level file hinted at it. For hand-authored levels this is a convenience; for
generated ones it is the only thing standing between a generator and unplayable
output.

## 7. The deployment floor is not the art budget

iOS 18 is the oldest OS the game runs on, set by three APIs that are core to the
look: `RealityView`, `RealityViewCameraContent`, `OrthographicCameraComponent`.

Nothing in rendering, art direction, level complexity, lighting, materials,
animation or gameplay is simplified to fit that floor. `RenderQuality` scales
*up* on capable hardware — more practical lights, crisper shadows — and the
baseline tier is still the full visual target.

API choices follow the owner's principle: use the oldest stable Apple API that
solves the problem well; reach for the newest only when it gives a substantial
advantage that cannot reasonably be had otherwise.

## 8. Where things live

```text
HeistCore/
  Geometry/    LevelMetrics, primitives, vector maths, CameraFramingSolver, ScreenProjection
  Catalog/     PropPrototype, PropCatalog, CharacterProfile
  Level/       LevelBlueprint, WallSpec, LevelGeometry, LevelValidator, LevelBuild
  Navigation/  NavigationBudget, NavGrid, PathFinder, PathWalker
  Levels/      shipped levels, as data

HeistKit/
  Components/  RealityKit components — storage only, no rules
  Systems/     thin adapters that apply HeistCore rules to entities
  Scene/       LevelSceneBuilder, GreyboxKit, TacticalCamera, RenderQuality
  Session/     GameSession — runtime state for one loaded level
  Views/       HeistSceneView — presentation and input translation
```

Tests mirror the split. `HeistCoreTests` covers the rules and needs no simulator.
`DerClouTests` covers only what genuinely requires RealityKit: that a scene builds,
that components land on entities, that the grid survives the round trip into a
real scene.

## 9. Placeholder art is scaffolding, not a decision

`GreyboxKit` renders prototypes as primitives with **final real-world
dimensions** and real PBR response. Swapping in authored USDZ models is meant to
be a one-field change in `PropCatalog` (`asset`), with no level data touched,
because the footprints are already correct.

Do not treat the greybox as the visual target. See `docs/ART_DIRECTION.md`.

## 10. What is deliberately not built yet

Present in the schema, absent from the runtime — so levels authored now stay
valid when these land:

- `SecurityLinkSpec` — switch/camera/alarm dependency graph;
- `MarkerSpec.Kind.cameraFocus`;
- `PropPrototype.asset` — production model reference;
- patrol routes on `ActorSpec` — stored and validated for reachability, but
  nothing walks them yet.

Interaction dispatch, doors, guards, vision and the planning timeline are the next
systems. They plug into `GameSession` and `HeistCore`; none of them should require
changing the layering above.
