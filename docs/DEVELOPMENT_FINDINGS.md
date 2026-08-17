# Development Findings

Status: living development-research log

Purpose: record practical findings, corrections, experiments, and implementation rules discovered while the game is being built. This file is not a replacement for `docs/DECISIONS.md`; stable architectural decisions should eventually be promoted there. This file preserves the reasoning and the development-stage discoveries that led to them.

---

## 2026-08-17 — Safe areas, Dynamic Island, and gameplay placement

### Final rule

Use the system-provided safe areas. Do not invent a second custom exclusion geometry around Dynamic Island, display cutouts, rounded corners, or specific iPhone models unless a real measured problem later requires it.

The game may render the world edge-to-edge, but **gameplay-critical content must be placed inside the current system safe area**.

This is deliberately simpler than a custom `GameplayOcclusionZone` system.

### Rendering versus gameplay bounds

The 3D world itself may extend across the full display:

- floor;
- walls;
- background geometry;
- decorative props;
- lighting/background effects.

These elements may visually continue behind or adjacent to Dynamic Island or other system-reserved screen regions.

However, interactive or mission-critical objects must be authored/generated inside the actual safe gameplay bounds derived from the system safe area.

Examples of gameplay-critical objects:

- guards and their important start positions;
- security cameras;
- doors used by the mission;
- switches and control panels;
- safes;
- mandatory loot/objectives;
- extraction points;
- key mission items;
- interactive devices;
- important laser/security elements;
- HUD controls and mission information.

The goal is simple: the world can fill the screen, but the player must never be required to inspect, tap, or reason about an important object that is physically hidden by Dynamic Island, a display cutout, rounded-corner constraints, or another system-reserved region.

### No device-specific hard-coding

Do not write rules such as:

```text
if iPhone Pro Max -> reserve 57 px on the left
if Dynamic Island -> offset cameras by X
```

Do not maintain a hand-written table of iPhone cutout dimensions.

Use the actual safe-area information supplied by the current layout/runtime for the current device and orientation.

Conceptually:

```swift
let safeInsets = geometry.safeAreaInsets
```

or the appropriate current SwiftUI/UIKit equivalent used by the implementation.

The exact API may vary with the final view hierarchy, but the architectural rule does not: **the system safe area is the source of truth**.

### Level authoring and generation

The level generator / level-authoring validation must distinguish between:

```text
full render bounds
```

and:

```text
safe gameplay bounds
```

`full render bounds` may occupy the complete viewport.

`safe gameplay bounds` are the area in which mission-critical objects may be placed.

When a level or replay variant is generated, critical entities must be placed only where they remain inside the safe gameplay bounds for the current presentation.

This rule is particularly important once dynamic/replay variants can move guards, cameras, switches, loot, or other mission objects between valid locations.

### HUD

HUD and interactive UI controls also respect the system safe area.

Do not solve HUD placement by manually compensating for Dynamic Island or a particular iPhone model.

The game render surface may be edge-to-edge while HUD content uses safe-area-aware SwiftUI layout.

### Landscape orientation

Safe-area values must be taken from the current orientation, not assumed to be symmetric.

Test both supported landscape orientations on representative devices/simulators because the reserved area may appear on different physical sides of the screen.

No mission-critical placement rule should assume that the obstruction is always on the left or always on the right.

### What we explicitly rejected

**Rejected approach:** create a separate custom `GameplayOcclusionZone`, maintain custom per-object occlusion footprints, and manually model Dynamic Island/display cutouts.

Reason for rejection: unnecessary complexity at this stage. The system already exposes the correct safe area for the active device/orientation. We should not build a second approximation of information the OS already knows.

If future playtesting demonstrates a specific case that system safe areas alone cannot solve, add the smallest targeted rule needed for that measured case rather than pre-building a generalized occlusion framework.

### Development/debug requirement

During graybox development, it is useful to expose the actual safe gameplay bounds in a debug overlay so level geometry and object placement can be visually checked on-device and in Simulator.

The overlay must visualize the **real system-derived safe area**, not a hard-coded approximation.

### Implementation principle

Keep this rule simple:

```text
WORLD RENDERING
full screen / edge-to-edge

GAMEPLAY-CRITICAL PLACEMENT
inside system safe area

HUD / INTERACTIVE UI
inside system safe area

DEVICE CUTOUT DATA
provided by the OS, never hand-maintained
```

This is the current project rule unless real device testing demonstrates a concrete reason to refine it.

---

## 2026-08-17 — Safe-area rule implemented

The rule above is now enforced in code, not only written down.

### How it works

- `ScreenInsets` and `SafeGameplayBounds` in `HeistCore`, with `SafeAreaSolver`
  projecting the four corners of the system safe area onto the floor plane using
  the same camera framing the renderer uses. The result is axis-aligned because
  the tactical camera only tilts, never yaws.
- The insets come from SwiftUI and must be read **outside** `ignoresSafeArea` —
  read inside, they are already consumed and arrive as zero. `GameScreen` reads
  them at the top level and passes them down.
- `GameSession.updateSafeArea` recomputes the region whenever the viewport,
  orientation or level changes, and logs any mission-critical object that falls
  outside it.
- Scenery is exempt by design: only props with interactions, security devices,
  loot, markers and actor start positions are checked.
- A debug outline of the **real, system-derived** region can be toggled from the
  debug panel. It is not a hard-coded approximation.

### What it caught immediately

Two real placement bugs in `office01`, neither visible in the level file:

1. `panel.corridor` — a security panel on the west wall, 0.51 m outside the safe
   area. Moved to the corridor's south wall.
2. `shelf.02` — an interactable cabinet against the east wall, 0.20 m outside.
   Moved inward.

### Correction to the assumed inset geometry

The first test fixture assumed the reserved region is on one side only. Measured
on an iPhone 16 simulator in landscape, the system reports **L59 / R59 / B21** —
both sides, regardless of which way the housing physically faces. The one-sided
fixture passed while a real object was outside the area on the other side.

Landscape insets must therefore be treated as symmetric-until-proven-otherwise,
and fixtures should use measured values rather than assumed ones.

---

## 2026-08-17 — Filling the display edges: scenery, not thicker walls

First attempt was wrong and is recorded so it is not repeated: the building's
exterior walls were thickened to 2 m so that *they* would sit under the cutout.
That ate playable space, dominated the frame and washed out the interior, for no
gain.

**The rule:** the edges of the display are filled by the world *outside* the
building — neighbouring walls in right-angled runs, trees, hedges — not by making
the target building's own geometry heavier.

Implemented as a `scenery` prop kind, which:

- sits outside the floor rects, and is therefore exempt from the "placed outside
  every floor" validation;
- never enters the navigation grid, so it cannot affect routing;
- is exempt from the safe-area placement check, since covering the screen edges
  is its entire purpose;
- is placed in level data like any other prop, so a generator can scatter it.

Underneath everything is a dark ground plane extending well past the building, so
no camera position can reveal empty background.

The building itself keeps ordinary wall thickness. The camera separately
guarantees the floor stays inside the system safe area, so gameplay is never
under the cutout while the street around it is.
