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
| One finger drag | Pan the map | implemented |
| Pinch | Zoom | implemented |
| Two-finger vertical drag | Limited tilt — "peek" | implemented |
| Double tap an actor | Focus that actor | planned |
| Button | Fit the whole mission | implemented |
| — | **Rotation is not offered** | decided |

### Peek tilt

The tactical angle is near-overhead. A two-finger vertical drag lowers it within
a fixed range — roughly 82° down to 65–70° — which reveals what a plan view
cannot show: the inner face of a wall, a doorway, a wall-mounted camera, the
height of furniture, an actor standing behind an object.

Strictly one dimension. **The map's orientation never changes** — north does not
become west. The player peeks under an angle; they do not fly around the scene.
That is what protects spatial memory, keeps vision cones comparable, and stops
tap-to-move fighting the view.

**Peeking does not re-frame.** The tactical angle is the only view with a
guaranteed framing; a peek is local inspection, so part of the level running off
screen is expected. Automatically zooming out to keep everything visible would
defeat the point of leaning in.

Implemented starting range: 0–14° beyond the tactical 24°, at 0.06° per point of
drag. Numbers to be settled by eye on device.

**The point under the fingers stays put.** The gesture records the world point
beneath the touch midpoint, then re-pans after each tilt so that point returns to
the same pixel. Without it the map slides out from under the hand and the gesture
reads as the camera lurching. This is what `ScreenProjection.screenPoint(of:)`
exists for, and there is a round-trip test covering it.

### Walls between the camera and the action

Tilting still looks from the same side, so it cannot show the far face of a wall.
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
