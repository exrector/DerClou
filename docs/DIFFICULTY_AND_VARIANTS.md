# Difficulty and replay variants

Status: core game-design decision

## Final model

The game uses **two fundamentally different retry rules**.

### First-time campaign completion

Before a mission has ever been completed successfully:

- every failure resets the mission to **exactly the same scenario**;
- guard routes are identical;
- camera timing is identical;
- switch windows are identical;
- active devices are identical;
- evidence checks are identical;
- patrol phases are identical;
- the same plan against the same initial state always produces the same result.

This preserves the core planning fantasy:

> fail -> understand exactly why -> modify the plan -> retry the same problem

The player must be allowed to learn the level precisely.

### Replay difficulty after first completion

Once a mission has been completed, the player may replay it in an advanced difficulty mode.

In this mode, **each new attempt may use a slightly different scenario configuration**.

The physical building can stay the same, but dynamic systems may be reconfigured at the beginning of the attempt.

Examples:

- a guard gets a different valid patrol route;
- a second guard may be active;
- a guard checks a different door or object;
- camera starting phase changes;
- camera scan arc changes;
- one camera is active instead of another;
- a laser is controlled by another switch;
- a timed switch has a different but bounded duration;
- an alarm dependency changes;
- optional loot moves between predefined valid locations;
- available tools/crew restrictions change;
- evidence inspection behavior changes.

If the player fails and chooses Restart on this advanced mode, the next attempt can generate another valid variation.

Therefore the advanced replay mode tests **understanding of the systems**, not memorization of one exact timeline.

## Important distinction: deterministic attempt, variable restart

Even in the advanced replay mode, an individual attempt should remain deterministic once it begins.

The randomness/variation happens at attempt creation time.

Conceptually:

```text
Attempt #42 created
seed = 884193

Guard A route = A -> C -> D -> B
Camera 1 phase = 2.3 s
Camera 2 enabled = true
Laser switch window = 7.5 s
Guard B inspection target = Door 04

From this point until failure/success:
all behavior is deterministic.
```

If that exact seed is replayed, it must produce the same scenario.

On restart in the advanced mode:

```text
Attempt #43
new seed
-> slightly different valid security configuration
```

This architecture gives us both:

- deterministic simulation;
- replay unpredictability.

## Why not randomize the first campaign attempt?

Because that would damage the main design loop.

If a player fails because Camera 2 saw them at 00:31.4, then changes the plan, but on restart Camera 2 behaves differently, the player cannot verify whether the correction was right.

For first completion, this is unacceptable.

The canonical campaign version is therefore a fixed puzzle.

Advanced replay is a different challenge:

> You already proved you can solve this building. Now prove you understand the systems well enough to solve a changed security setup.

## Recommended progression

### State 1 — Uncompleted

Only the canonical mission is available.

Retry behavior:

```text
same level
same scenario
same timings
same patrols
same devices
```

### State 2 — Completed

The player can replay the canonical mission at any time.

Additionally unlock one advanced mode, working name:

- Professional
- Dynamic Security
- Mastermind
- Unpredictable
- Security Shift

Final naming is open.

### State 3 — Advanced replay

Every new run is built from a controlled scenario generator.

The generator should not create arbitrary chaos. It chooses among designer-approved possibilities.

## Controlled variation, not procedural nonsense

Do not procedurally generate arbitrary patrols or security graphs without validation.

Every variable element must come from a legal authored set.

Example guard configuration:

```text
guard_lobby_01:
possibleRoutes:
- route_A: Lobby -> Hall -> Lobby
- route_B: Lobby -> OfficeDoor -> Hall -> Lobby
- route_C: Lobby -> Storage -> Hall -> Lobby
```

The generator selects one.

It does not invent random navigation points anywhere on the NavMesh.

Likewise for cameras:

```text
camera_corridor_01:
possibleScanProfiles:
- [-40°, +40°], 4.0 s
- [-55°, +25°], 4.8 s
- [-30°, +60°], 5.2 s
```

All profiles are authored/tested.

## What may vary

### Guards

- patrol route from a predefined set;
- starting waypoint;
- starting phase;
- inspection targets;
- deterministic wait profile;
- presence/absence of optional guard;
- which guard performs a certain inspection role.

### Cameras

- active/inactive camera subset;
- starting orientation;
- phase offset;
- scan profile;
- endpoint pauses;
- which switch/panel controls the camera.

### Lasers and alarms

- which barriers are active;
- which switch controls which barrier;
- timed disable duration selected from approved values;
- cross-linked alarm relationships;
- reactivation schedule.

### Doors / access

- selected door locked/unlocked;
- key/keycard placed in one of several valid locations;
- one alternate entry route enabled/disabled;
- a normally safe door becomes evidence-sensitive.

### Evidence and inspection

- which objects guards inspect;
- whether a guard checks doors, safes, cabinets or missing valuables;
- which evidence categories matter in this attempt.

### Objectives / optional loot

Main objective should usually remain stable so the identity of the mission stays clear.

Optional loot may move among authored sockets/locations.

Advanced variants can add constraints such as:

- leave no evidence;
- take all marked valuables;
- do not disable cameras;
- do not break locks;
- use only one actor;
- complete under a target execution time.

## What should usually NOT vary

Avoid changing everything at once.

Normally keep stable:

- building geometry;
- room identity;
- overall objective;
- fundamental rules of detection;
- controls;
- meaning of visual feedback.

The player should recognize the mission immediately.

The challenge is:

> Same building. Different security shift.

Not:

> Completely different game every restart.

## Difficulty tiers

A possible structure:

### Standard / Campaign

Fixed authored scenario.

Every retry identical until successful.

### Professional

After first completion.

Each run selects a small number of changed variables, for example:

- one guard route;
- one camera phase/profile;
- one timed security dependency.

### Master / Expert

Later unlock.

More subsystems may vary simultaneously:

- guard routes;
- camera subset/phases;
- inspection behavior;
- security graph relationships;
- optional challenge conditions.

Still constrained by authored valid combinations.

## Seeded generation

Every advanced attempt should have a seed.

Benefits:

- bugs are reproducible;
- QA can replay exact failures;
- players could theoretically share challenge seeds later;
- daily challenge mode becomes possible;
- analytics can identify impossible/broken combinations;
- Claude/Codex can reproduce a reported scenario exactly.

Example debug display:

```text
Mission: 07
Mode: Professional
Seed: 884193
VariantSet: 3
```

Production UI does not have to expose the seed unless we later want shareable challenges.

## Generator architecture

Conceptually separate:

```text
LevelGeometry
CanonicalScenario
VariantRules
AttemptScenario
```

### LevelGeometry

Stable physical world:

- rooms;
- walls;
- doors/sockets;
- props;
- navigation mesh;
- interaction anchors.

### CanonicalScenario

The first-play fixed puzzle.

### VariantRules

Designer-defined allowed variations and incompatible combinations.

### AttemptScenario

Concrete scenario created from the canonical level + difficulty + seed.

Pseudo-model:

```text
AttemptScenario = VariantGenerator.generate(
    level: level_07,
    mode: professional,
    seed: 884193
)
```

Once generated, `AttemptScenario` is immutable for that attempt.

## Validation requirement

The generator must never create an impossible mission unless explicitly designed as a failure state, which we generally do not want.

We need validation rules such as:

- objective remains reachable;
- extraction remains reachable;
- required tool exists if required;
- security graph has at least one valid solution;
- timed windows are physically possible given movement/action durations;
- no required key is behind the door that the key itself opens;
- no two selected variations create a circular impossible dependency.

Eventually automated simulation/validation may test generated variants before release.

## Strong long-term opportunities

This model gives us inexpensive future modes using the same technology:

### Daily Heist

All players receive the same mission + seed for a day.

### Challenge Code / Seed

A player shares a generated configuration with another player.

### Perfect Run

Complete a generated variant without detection/evidence.

### Streak

Solve multiple randomized security shifts without failure.

### Leaderboards

Compare execution time, loot, evidence and retries on the same daily seed.

These are not first-release requirements. They are architectural benefits of seeded scenario variation.

## Critical design rule

The distinction must remain explicit in code and product design:

```text
FIRST COMPLETION
failure -> reset SAME puzzle

ADVANCED REPLAY
failure -> optionally/new restart generates NEW valid variation
```

Do not accidentally apply the advanced reroll behavior to the canonical campaign.

The canonical campaign teaches mastery by iterative correction.

The advanced mode tests mastery by adaptation.