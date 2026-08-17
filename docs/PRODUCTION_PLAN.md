# Production plan

How the project moves forward, and in what order, so that work done now is not
redone later. Written 2026-08-17, after the foundation audit.

Complements `docs/ROADMAP.md`, which lists *systems* in dependency order. This
document is about *risk* order — which question each stage answers, and what has
to be true before the next stage starts.

## The distinction this plan is built on

Standard industry practice separates two artefacts that are easy to confuse:

- a **prototype** answers *should we make this game* — it de-risks the **design**;
- a **vertical slice** answers *can we make this game* — it de-risks the
  **production pipeline**, at final quality, across every discipline.

Rami Ismail's framing is that developers who mix these up "lose a lot of time and
money doing so", because the slice is a production prototype rather than a design
one: by the time you build it, the design question should already be settled.

Standard milestone chain: Research (ideation, prototyping) → Pre-production
(vertical slice) → Production (feature complete, then content complete) →
Wrap-up (release candidate, release).

## Where this project actually stands

We have built a **technical prototype**, and it answered its question well: yes,
a native RealityKit top-down tactical scene works, tap-to-move works, levels can
be data, navigation can be ours and deterministic.

We have **not** built a design prototype. And the design question is not "does
walking feel good" — it is:

> Is it enjoyable to study a building, commit to a plan, watch it fail by 1.2
> seconds, and fix it?

That loop does not exist yet in any form. What exists is free real-time movement,
which is the one thing this game is explicitly *not* about (`CLAUDE.md`: "not a
reflex stealth game").

**This is the risk.** `ROADMAP.md` reaches the planning recorder at Phase 10 and
deterministic playback at Phase 11, with the first полished slice at Phase 12.
Following it literally means building interaction dispatch, doors, guards, vision,
cameras, lasers, switches, safes and loot — nine systems — before ever testing
whether the core idea is fun. If the answer turns out to be "not yet", every one
of those systems was designed against an unvalidated loop.

## Stage 1 — Design prototype: prove the loop (next)

**Question:** is the plan → commit → fail → fix → retry loop fun?

**Build the thinnest possible version.** Deliberately skipping most of the
security vocabulary, because none of it is needed to answer the question:

1. **Simulation clock.** An explicit timeline, separate from render frames.
   Actions have start and end times. This already half-exists — movement is
   `distance / speed` and deterministic — it needs to become an authoritative
   schedule rather than something that happens live.
2. **One deterministic guard.** Walks its route (already in the blueprint,
   already reachability-validated), waits at waypoints, loops exactly.
3. **Vision, the simple version.** Range, cone angle, facing, and a line-of-sight
   check against walls. Nothing else. The visible cone must be drawn from the same
   numbers that decide detection.
4. **Plan recording.** Player taps out moves during planning; each becomes a
   timed semantic action on a timeline. No free-running actor.
5. **Commit and playback.** Reset to the level's initial state, run the plan
   against the clock, report success or the exact moment and cause of failure.
6. **Edit and retry.** Return to the plan with it intact.

**Gate — do not proceed until all of these hold:**

- a plan can be recorded, committed and replayed with identical results;
- a failure names the second and the reason ("seen by guard.01 at 00:31.4");
- changing one action changes the outcome predictably;
- **the owner plays it repeatedly and wants to keep fixing the plan.**

That last one is the real gate. If beating the level feels like admin rather than
a puzzle, the design changes here — while it costs days — rather than after nine
systems exist.

Content for this stage stays greybox. Explicitly: no art, no audio, no menus.

## Stage 2 — Mechanic vocabulary

Only once the loop is proven. Each mechanic added one at a time, and each one
arrives with a small level that exists to test it:

door → switch/laser dependency → security camera → safe/loot → noise → evidence

Every one must be data in a blueprint plus one system, per `ARCHITECTURE.md`.
The rule that keeps this honest: **if adding a mechanic requires touching level
data structures, the design is wrong, not the level format.**

## Stage 3 — Vertical slice

Now the question changes to *can we produce this*. One mission at genuine final
quality across every discipline: authored 3D assets replacing the greybox kit,
skeletal animation, lighting pass, audio, HUD, failure and retry UX, the lot.

The `asset` field in `PropCatalog` exists for exactly this swap; footprints are
already final so level data should not move.

**Gate:** a screenshot with no explanation reads as a commercially released
tactical game (`ART_DIRECTION.md` §15), and the whole loop plays at 60 fps on
device.

## Stage 4 — Measure the real speed, then plan the campaign

The trick worth stealing: after the slice, build a **second** mission at the same
quality and time it. The first is slow because the pipeline is being invented; the
second is the honest measurement. Campaign length is then arithmetic, not hope.

Only after that does the mission count in `ROADMAP.md` Phase 17 mean anything.

## Standing rules against rework

1. **One question per stage.** Do not answer a production question during a design
   stage, or vice versa.
2. **No mechanic without a level that tests it.**
3. **No art before the mechanic it dresses is final.** Greybox has final
   dimensions precisely so this ordering is free.
4. **Validation runs on every level, every build.** `LevelValidator` already
   fails loudly; keep it that way as mechanics grow.
5. **Playtest at every gate, by actually playing** — not by looking at a
   screenshot and agreeing it looks right.
6. **When a stage's gate is not met, the scope changes, not the gate.**

## Sources

- Rami Ismail, *Prototypes & Vertical Slice* — https://ltpf.ramiismail.com/prototypes-and-vertical-slice/
- Rami Ismail, *Milestones* — https://ltpf.ramiismail.com/milestones/
- Tono Game Consultants, *Evolve Your Game Prototype Into a Vertical Slice* — https://tonogameconsultants.com/prototype-to-production/
- Indie Bandits, *Why Your Indie Game Needs a Vertical Slice* — https://indiebandits.com/2023/02/13/why-your-indie-game-needs-a-vertical-slice/
