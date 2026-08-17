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
