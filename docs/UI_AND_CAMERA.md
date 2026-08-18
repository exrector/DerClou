# UI and camera

Status: agreed direction, 2026-08-17. Not yet implemented except where noted.

The principle: the top of the screen stays an almost clean 3D world. All the
complexity of control lives at the bottom, and only appears when it is needed.
Not a permanent frame of buttons around the map.

## The Plan Deck

The modern equivalent of the original's Recorder, not a copy of it.

**Collapsed** — a strip about a finger high along the bottom, carrying only what
is always needed:

```text
┌──────────────────────── GAME ────────────────────────┐
│                     game world                       │
├──────────────────────────────────────────────────────┤
│  00:18.4   ◀︎   ▶︎/Ⅱ   ▶▶   [━━━━●━━━━]   EXECUTE  │
└──────────────────────────────────────────────────────┘
```

**Expanded** — swipe or tap up, and it becomes the planning console:

```text
├──────────────────────────────────────────────────────┤
│ THIEF   ━ Move ━━━ Wait ━ Hack ━━━━━ Move            │
│ TECH         ━━━━━━━ Move ━ Disable ━━━━━            │
│                                                      │
│ GUARD 1 ┄ patrol ┄ inspect ┄ patrol ┄                │
│ CAM 01  ↔↔↔↔↔↔↔↔↔↔↔↔                                │
│ LASER   █████ OFF ███████████                        │
│                                                      │
│ |◀   ◀︎   ▶︎/Ⅱ   ▶︎   ▶|            EXECUTE          │
└──────────────────────────────────────────────────────┘
```

Crew tracks are the heavy ones; security systems are drawn as thinner lanes. The
player should be able to read, in one glance: *the guard passes here at 12.4 s,
the camera turns at 14.1 s, and I enter the corridor at 13.8 s.*

This is the single most important screen in the game. It is where the player
conducts time rather than guesses at it.

### The deck does not shrink the viewport — the level reserves a strip

Settled 2026-08-17, correcting an earlier note here that proposed feeding the
deck's height into the framing solver as an inset. That would shrink the whole
scene whenever a panel appeared, undoing the fullscreen framing.

Instead the **level** reserves it. `LevelBlueprint.reservedNearBand` (1.5 cells by
default) marks the strip along the near edge where nothing mission-critical may
be placed. The world still renders underneath, so the game stays fullscreen; the
collapsed deck simply sits over scenery.

`LevelValidator` reports any interactable, marker, actor start or patrol waypoint
that strays into it, and this already moved two objects in office01.

The **expanded** deck may cover part of the world freely. It is an editing mode,
not the main view, and nothing has to re-frame when it opens.

### Waiting is an action

Standing still records nothing. A deliberate `WAIT 2.5 s` is placed on the
timeline and can be stretched with a finger. The player designs a delay rather
than sitting through one — the same distinction the original drew, made
manipulable.

### Rewinding replaces what follows

Scrub back, resume recording, and the actions after that point are replaced.
Matches the original's recorder semantics.

## Mission status, not a percentage

A completion percentage means little in a heist. Show state instead, compact, and
expandable into a mission card on tap:

```text
OBJECTIVE   1 / 2
LOOT        $3,200 / $5,000
ALARM       SAFE
TRACES      0
```

## Camera

| Gesture | Effect | Status |
|---|---|---|
| One finger drag | Peek into the box | implemented |
| Pinch | Zoom | implemented |
| Double tap an actor | Focus that actor | planned |
| Button | Fit the whole mission | implemented |
| — | **Rotation is not offered** | decided |
| — | **Panning is not offered** | decided |

### Fixed top-plane anchored off-axis perspective camera

Settled 2026-08-18, after five wrong implementations. That name is the technical
one and it is worth using: it says exactly what the camera is and rules out the
four things it is not — an orthographic camera, a tilt, an orbit, and a pan.

The rule, from the owner:

> Представь уровень как открытую сверху прямоугольную коробку. В исходном
> состоянии камера смотрит почти строго сверху вниз, так что верхние торцы
> внешних стен образуют фиксированную рамку уровня на экране. **Эту рамку нельзя
> двигать по экрану при жесте.**

So:

* The camera looks **straight down** and never rotates.
* Peeking **moves the camera sideways** — a real change of viewpoint.
* The projection is **off axis** by exactly the amount that cancels that movement
  at the anchor plane. Shifting the principal point moves the image by an amount
  independent of depth; moving the camera moves it by an amount inversely
  proportional to depth. Matching them at one depth cancels there and nowhere
  else.

Result: the tops of the walls hold still to the pixel, and the floor below them
slides by `anchor height × tan(peek)` — 20° over a 3 m wall exposes a little over
a third of its inside face. **World-space coordinates of walls, floor, furniture
and characters do not change at all.** One real 3D world serves rendering,
navigation, raycast, collision, guards, cameras and interactions. There is no
second "visual" geometry.

#### Why a symmetric camera cannot do this

Worth writing down, because it is the reason the design looks unusual.

A perspective camera images the anchor plane by a homography. If that image is
unchanged, so is the image of the plane's horizon. At rest the picture plane is
parallel to the anchor plane, the horizon is at infinity, and the frame's
opposite sides are parallel on screen. The moment the camera stops looking
straight down, the horizon becomes a finite line and the frame keystones. So the
camera must keep looking straight down — and a straight-down symmetric camera
images that plane as a plain scale and offset, which cannot stay put while the
camera moves. "Frame fixed" and "viewpoint changes" are incompatible for a
symmetric frustum. Only an off-axis one has the extra freedom.

#### Implementation

`ProjectiveTransformCameraComponent`, which takes a projection matrix. RealityKit
uses **reverse-depth** projection — the near plane maps to 1 and the far plane to
0; the implementation was additionally validated experimentally against the
built-in camera at zero offset, where the two agree pixel for pixel.

`CameraProjection` in `HeistCore` is the **single source of truth**. The matrix
handed to the renderer, the ray a tap casts, the screen position of a world point
and the safe-area solve are all built from its numbers. A second implementation
of the same projection would drift, and the symptom would be taps landing away
from the finger.

Two dead ends recorded so they are not tried again:

* **A shear on the level's transform does not work.** `Transform` is scale,
  rotation and translation; Apple documents that it cannot represent an arbitrary
  4x4 without loss and that shear may be dropped. RealityKit silently decomposed
  ours into a rotation, which pins one edge of the box and swings the rest —
  exactly what the owner saw and rejected.
* **Deforming the world's vertices was proposed and rejected**, correctly. It
  would have made furniture skew against its own top and bottom, split the game
  into a drawn geometry and a real one, and put lighting, shadows, raycast and
  future production assets permanently out of step. If a non-standard projection
  is ever needed beyond what the camera can express, it belongs in rendering or a
  shader, with the world left alone.

#### Range and feel

±20°, at 0.09° per point of drag, so a drag across half the screen reaches the
limit. The floor follows the finger: drag right and it goes right, revealing the
inside of the wall it moves away from.

**Nothing outside the building can come into frame** — structurally, not by a
compensating zoom. The wall tops are the outermost geometry and they are pinned
to the display edges, so anything beyond them is behind a wall or off screen.

#### What this asks of level data

Version 1 of the level format uses a **rectangular horizontal projection anchor
plane at the height of the outer top contour**, taken from the level's own bounds
and wall height. That is a property of the format, not of the camera: the anchor
plane is just a plane, so a later format can carry an explicit one and allow
L-shaped buildings, courtyards, projections and locally differing wall heights
with the camera unchanged.

One consequence to design around: an opening in an exterior wall will show
whatever is beyond it. Today nothing is, because the outer walls are solid.

#### Tests

`CameraProjectionTests` owns the contract, and tests it on projected points
rather than on pixels — Apple can change anti-aliasing or rasterisation without
changing the camera maths. The central pair:

```
wall-top corner → screen point     must not change
floor beneath it → screen point    must change
```

checked at peek 0, ±X and ±Y, plus: every corner of the frame at every peek in
range; the floor's travel against the predicted `height × tan(peek)`; the matrix
applied by hand agreeing with the projection used for taps; and a screen → world
→ screen round trip.

`CameraLab` in the app is the rendered counterpart: one room, four cubes, markers
on the anchor corners, driven by the real `TacticalCamera`. Launch with
`CAMLAB=1`, drag to peek, double tap to reset. Kept deliberately — this camera is
unusual enough to deserve somewhere it can be checked by eye in isolation.

### Walls between the camera and the action

Leaning looks from a shallow angle, so it cannot show the far face of a wall.
The answer is not free rotation but the standard architectural one: a wall that
comes between the camera and the selected actor goes

```text
opaque → translucent → cutaway
```

Better than rotating the world, because the map stays where the player left it.

## Why not copy the original's interface

The original was a 2001 PC game with a mouse: free camera movement, tilt, zoom,
an auto-camera, and a screen ringed with tools. Its *grammar* is worth keeping —
record, rewind, execute, shared timeline. Its *layout* is not.

Sources: Der Clou! 2 manual (recorder controls, stopwatch, character switching on
a shared timeline, active waiting, camera handling) —
https://www.ds.thqnordic.com/support/Clou2_Handbuch.pdf
