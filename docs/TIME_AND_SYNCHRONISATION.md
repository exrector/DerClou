# Time and synchronisation

Status: core design decision, settled 2026-08-17

This answers the question the whole game rests on: how do the thief, the guards
and the security devices share time?

## The decision

**Continuous time, not turns. The player controls time by spending it.**

Everything in a mission — guard position, camera angle, laser state, the thief's
own progress — is a *function of mission time*. Ask any of them "where were you
at 00:31.4" and they answer directly. Nothing accumulates, nothing ticks
independently, so nothing can drift out of sync with anything else.

There is exactly one clock. Systems read it; they do not keep their own.

## Why not turns

Turn-based movement would make the timing puzzle coarse. The game's promise is
"I failed by 1.2 seconds, and I can fix that" — a granularity turns cannot
express. It would also break the visual language: a guard sliding one tile per
turn reads as a board game, and this is a building, viewed from above, with
people walking through it.

## How the original solved the "I can never get past" problem

This was the worry that prompted the decision, and it is worth recording the
answer plainly.

In *The Sting!* (Der Clou! 2), plan recording runs a timer during time-consuming
actions — walking, lock-picking — and the player can additionally perform
**active waiting**: an action that advances time while doing nothing, expressly
so the crew can dodge guards. Guards' movements are visible while planning.

So the player never races a camera. The player **waits for it**.

> "I cannot get past the camera" is not a difficulty problem. It means the plan
> is missing a wait.

This reframes the core skill from reflexes to arithmetic, which is exactly the
game we are building, and it is why walking speed can stay constant.

## What follows for us

### Wait is a first-class action

`wait(duration:)` is as fundamental as `move(to:)`. It is not a fallback for when
the player has nothing to do; it is the main tool for solving timing puzzles. It
must be as easy to place in a plan as a move.

### Every obstacle needs a passable window

For a level to be solvable, each guarded stretch must have a period within the
patrol cycle during which crossing it is possible:

```text
window ≥ time to cross the exposed stretch
```

Because guards and cameras are deterministic functions of time, this is
**checkable**, not a matter of playtesting hope. A future validator can sweep the
patrol cycle and report any stretch with no window — the same way
`LevelValidator` already reports rooms cut off by furniture. This becomes
mandatory once levels are generated rather than hand-placed.

### Cycles must be learnable

Patrol and scan periods are derived from geometry and speed, never measured at
runtime, so the number a player learns stays stable across builds and devices.
Cycle lengths should be short enough to observe in one planning session — long
cycles are not more difficult, only more tedious.

### The planning view shows time, not just space

Since the answer to "when do I go" is a moment, the planning UI has to expose
moments: the guard's position at the time the thief would arrive, and where the
plan currently sits on the clock. Without that, the player is guessing, and the
game becomes trial and error rather than reasoning.

### Speed is a level-design parameter, not a difficulty knob

If a camera scans too fast for any window to exist, the fix is the camera's scan
period in that level's data — not the thief's walking speed, which stays constant
by design (`CLAUDE.md`).

## Implementation state

- `MissionClock` — the single authority. Advances only from one place in the
  view layer; nothing else converts frames into game time.
- `PatrolRoute.state(at:)` — guard position and facing as a pure function of
  time. Implemented and tested, including exact repetition across circuits.
- Security cameras will use the same shape: `scanState(at:)`.
- Plan actions will carry explicit durations, so a plan's total time is
  arithmetic over its actions rather than something observed while it runs.

## Sources

- *The Sting!* — https://en.wikipedia.org/wiki/The_Sting!
- Kasey Chang, player review describing record mode, the timer and active waiting — https://www.mobygames.com/game/4295/the-sting/user-review/2681069/
- Kasey Chang, *The Sting! Unofficial Strategy Guide and FAQ* — https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/14674
- German manual (`Plan Aufzeichnen` / `Plan Starten`) — https://www.ds.thqnordic.com/support/Clou2_Handbuch.pdf

---

## Additional facts from the original manual (2026-08-17)

Confirmed against the official Der Clou! 2 manual, and they sharpen the design:

**The recorder had rewind, fast-forward, pause and active waiting.** Planning was
not a one-take performance — the player could scrub back and rewrite part of a
plan.

**Multiple characters share one timeline.** The manual states that when control
switches to another character, the moment it starts from is the moment the
previous character was left at; to have someone begin *earlier*, the recorder has
to be rewound. So the crew is not a set of independent scripts — it is parallel
tracks on a single clock:

```text
GLOBAL TIME
0s      5s      10s     15s      20s
|-------|-------|-------|--------|

THIEF    ████ walk ███ lockpick ███ wait
GUARD    ██ patrol ───────── patrol ───────
CAMERA   <<<< sweep >>>><<<< sweep >>>><<<<
ACTOR B         wait ███████ move ███ disable
```

This is the structure to build toward, and it is why `MissionClock` is a single
authority rather than one clock per actor.

**Timed windows are a designed mechanic, not an accident.** The walkthrough
describes a switch that disables a system for ten seconds, requiring another
character to be synchronised with that window. Our `SecurityLinkSpec` already
carries a `duration` for exactly this.

### Balance arithmetic

The window a level offers must exceed the time the crossing costs:

```text
corridor 4 m ÷ 1.4 m/s = 2.86 s to cross

easy    window 5.0 s   → generous, teaches the pattern
normal  window 4.0 s   → comfortable
hard    window 3.2 s   → 0.34 s of slack, tense but possible
broken  window 1.5 s   → mathematically impossible
```

Difficulty should not be raised by speeding cameras up indefinitely. Better
levers, in rough order of preference: phase offset between two systems, patrol
route length, pause placement, and overlapping coverage of two devices. Those
make a puzzle harder to *solve*; a faster sweep mostly makes it harder to
*execute*, which is the wrong axis for this game.
