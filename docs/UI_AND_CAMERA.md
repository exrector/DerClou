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
| One finger drag | Lean into the box — "peek" | implemented |
| Pinch | Zoom | implemented |
| Double tap an actor | Focus that actor | planned |
| Button | Fit the whole mission | implemented |
| — | **Rotation is not offered** | decided |
| — | **Panning is not offered** | decided |

### The anchored view shift

Settled by the owner on 2026-08-18, after five rejected attempts that each moved
the level on screen in one way or another. The rule, in his words:

> Представь уровень как открытую сверху прямоугольную коробку. В исходном
> состоянии камера смотрит почти строго сверху вниз, так что верхние торцы
> внешних стен образуют фиксированную рамку уровня на экране. **Эту рамку нельзя
> двигать по экрану при жесте.**

So:

* The camera looks **straight down**, never rotates, and never moves for a
  gesture — only zoom changes where it stands.
* The **tops of the exterior walls frame the level**, and that frame is fixed to
  the display: same pixels at every lean, in all four directions.
* What moves, against that fixed frame, is everything *below* it: the floor, the
  furniture, the people, the inside faces of the walls. The further below the
  frame something is, the further it travels.

That is neither a pan nor an orbit — both move the frame. It is an anchored shift
of viewpoint, and it is what makes the level read as a box being looked into.

**How it is done.** A shear of the scene about the plane of the wall tops. A
shear leaves its own plane exactly where it was, so the frame cannot drift: there
is no correction term to get slightly wrong. `ViewShear` in `HeistCore` is the
transform, and `CameraControlTests` asserts every corner of the frame holds to
better than a hundredth of a pixel across the whole range of lean.

The equivalent expression on the camera — an off-axis frustum, camera sliding
sideways with the projection sheared to match — is mathematically identical and
was implemented first. It renders black:
`ProjectiveTransformCameraComponent` is ignored by `RealityView` on iOS 18.6,
while a control `PerspectiveCameraComponent` on the same entity renders. Do not
spend another evening on it.

**Range.** ±20°, at 0.09° per point of drag, so a drag across half the screen
reaches the limit. A lean of θ slides the floor by the wall height × tan θ, so
20° exposes a little over a third of a wall's inside face.

**The floor follows the finger.** Drag right, the floor goes right, and the
inside of the wall it moves away from comes into view.

**Nothing outside the building can ever come into frame.** Not by a compensating
zoom, but structurally: the wall tops are the outermost geometry and they are
pinned to the display edges, so anything beyond them is either behind a wall or
off screen. There is a test for that too.

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
