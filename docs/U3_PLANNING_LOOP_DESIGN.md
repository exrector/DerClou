# U3 — the real planning loop: design (no code yet)

Status: design note, following the same process U2 used (design first,
confirm, then small verified steps). Nothing in this file has been
implemented yet.

Parent context: `docs/00_UNITY_PORT_MASTER_PLAN.md` §Milestone U3 and
`CLAUDE.md` §"Planning rule" — that section already fixes the required shape
(tap creates an action but doesn't move the actor; Execute restores the
initial snapshot and deterministically replays the immutable plan; failure
reports time/source/reason; Retry preserves the plan). This document is the
concrete file-level plan for hitting that shape against the actual U2 code.

## What already exists (from before this session, unused until now)

`Core/Planning/PlanModel.cs` already has almost the right data model:
`PlanActionType` (MoveTo, Wait, OpenDoor, Hack, CrackSafe, TakeLoot, Extract,
etc.), `PlanAction` (type/actorId/targetId/targetPos/duration/earliestStart),
`ActorPlan`, `MissionPlan` (with `AllActionsSortedByTime()` already written),
and `DefaultDurationProvider` (config-driven duration per action type, already
matches the config keys `Level01Builder` already sets — `hackDuration`,
`crackSafeDuration`, etc.). None of it is used by anything yet —
`GameController.QueueMoveAction` calls into it but nothing ever reads the
result back out.

U2 also already delivered the one primitive U3 needs and doesn't have to
invent: `MissionState.Clone()` — a deep copy, unused until now.

## The actual behavior change

Right now (post-U2): a floor tap calls `ActorView.SetDestination` immediately
and *separately* records a dead `PlanAction`. An interactable tap calls
`InteractionSystem.RequestInteract`, which walks the actor over and performs
the effect immediately. Both happen the instant you tap, regardless of any
"phase."

After U3: during `GamePhase.Planning`, a tap **only** appends a `PlanAction`
— the actor does not move, no door opens, no camera toggles. Only pressing
Execute makes anything actually happen, and it happens by deterministic
replay from a clean snapshot.

## New pieces

### 1. `PlanCursor` (`Core/Planning`, new, pure C#)

Per-actor "where does the next planned action start from" — position and
time. Without this, every tap would plan from the actor's *live* position
(which never moves during Planning) instead of chaining from the end of the
previously planned action, so three consecutive move taps would all start
from the same spot instead of forming a route.

```csharp
public struct PlanCursor { public WorldPoint Position; public float Time; }
```

Held in a `Dictionary<int, PlanCursor>` on `GameController` (or a new small
`PlanBuilder` class it owns — see below), initialized from each actor's
`ActorState.Position` / `time 0` when Planning starts, and advanced by every
`PlanBuilder.Queue*` call.

### 2. `PlanBuilder` (`Core/Planning`, new, pure C#)

The thing `GameController.OnFloorClicked`/`OnInteractableClicked` call
instead of moving the actor directly. Two entry points:

```csharp
public static class PlanBuilder
{
    public static void QueueMove(MissionPlan plan, MissionState state,
        int actorId, ref PlanCursor cursor, WorldPoint destination);

    public static void QueueInteract(MissionPlan plan, MissionState state,
        int actorId, ref PlanCursor cursor, string targetId, WorldPoint targetPos,
        PlanActionType actionType, Dictionary<string, LevelValue> targetConfig,
        IActionDurationProvider durationProvider);
}
```

`QueueMove`: pathfinds from `cursor.Position` to `destination` via the
existing `PathFinder.FindPath(state.Grid, ...)` (read-only — does not touch
`ActorState`), computes `duration = pathLength / actor.Profile.walkSpeed`,
appends a `MoveTo` `PlanAction` at `earliestStart = cursor.Time`, advances
`cursor` to `(destination, cursor.Time + duration)`.

`QueueInteract`: appends a `MoveTo` to `targetPos` first (reusing the same
logic as `QueueMove` — an interaction always requires walking there, same as
today's `InteractionSystem.RequestInteract`), then appends the actual
interaction action (`OpenDoor`/`Hack`/`CrackSafe`/`TakeLoot`/`Extract`/…)
immediately after, with `duration` from `durationProvider.GetDuration(...)`
(the existing `DefaultDurationProvider`, unchanged). Advances the cursor past
both.

Neither method touches `ActorState`, `DoorState`, `CameraState` or anything
else in `MissionState` — Planning taps are pure data entry against
`MissionPlan`. This is what actually satisfies "the real actor does not
execute that move yet."

### 3. `MissionInitialSnapshot` (thin wrapper, or just a stored `MissionState`)

Not a new type worth its own file — `GameController` (or `GameBootstrap`)
holds one field: `private MissionState initialSnapshot;`, set exactly once,
right after `LevelBuilder.Build` finishes and before the player can tap
anything: `initialSnapshot = SimulationService.Current.Clone();`. Because
Planning taps no longer mutate `MissionState` at all (previous paragraph),
this snapshot stays valid for the whole Planning phase without needing to be
retaken — Execute and every subsequent Retry all restore from this same one.

### 4. `PlanExecutor` (`Core/Planning`, new, pure C#)

The thing that turns a compiled `MissionPlan` into things actually happening,
in mission-clock time, deterministically. Does **not** run every fixed step
unconditionally like the U2 systems — only during `GamePhase.Execution`,
ticked explicitly from `GameController.Update()` (not folded into
`SimulationStep.Tick`, which stays "the systems that are always live" and
should not need to know what a `GamePhase` is).

```csharp
public class PlanExecutor
{
    public FailureEvent? LastFailure { get; private set; }

    public void Begin(MissionPlan plan); // sorts actions, resets per-action "fired" flags
    public void Tick(MissionState state, float currentTime);
}
```

`Tick` walks the plan's actions (sorted by `earliestStart`, cached once in
`Begin`) and, for every action whose `earliestStart <= currentTime` and not
yet fired, dispatches it by `type`:

| `PlanActionType` | Dispatches to |
|---|---|
| `MoveTo` | `ActorMovementSystem.RequestPath(state, actorId, targetPos)` |
| `OpenDoor` / `CloseDoor` | `DoorSystem.SetOpen(state, targetId, true/false)` |
| `Hack` / `ToggleSwitch` | flip `MissionState.Cameras[controlledId].powered` — needs the panel→camera link, see below |
| `CrackSafe` | `SafeSystem.StartCracking(state, targetId, actorId)` |
| `TakeLoot` | see "Loot becomes state" below |
| `Extract` | see "Mission outcome becomes state" below |
| `Wait` | nothing to dispatch — its only job is occupying time on the actor's track, which `earliestStart`/`duration` already encode |

`MoveTo` firing is not itself "done" the instant it's dispatched — arrival is
still governed by `ActorMovementSystem.Tick` (unchanged, still runs every
fixed step via `SimulationStep`). `PlanExecutor` only needs to *start* it at
the right time; the action's own recorded `duration` was an estimate used for
scheduling later actions, not a hard cutoff enforced here — this matches how
plans are built today (duration comes from path length ÷ walk speed, the same
number the actual walk will take absent interference).

### 5. Loot and mission outcome become state, not `InteractionSystem` fields

This is the one real gap U3 has to close beyond what the design doc's parent
sections spell out: `InteractionSystem.HasLoot` and `.MissionComplete` are
private fields on a MonoBehaviour today (U2 didn't touch them — loot/
extraction weren't in U2's scope). If they stay there, Retry can't cleanly
reset "did I already grab the loot" back to false just by restoring
`MissionState` — there'd be a second, unsnapshotted place mission outcome
lives, which breaks "same plan replayed twice gives the same result" the
moment a plan involves loot or extraction (i.e. always, for this level).

Minimum fix, sized to what this level actually needs (not a general
inventory system): add to `MissionState`:

```csharp
public bool HasLoot;
public bool MissionComplete;
```

`PlanExecutor`'s `TakeLoot`/`Extract` dispatch reads/writes these instead of
calling into `InteractionSystem`. `MissionState.Clone()` copies both (two
more lines). `InteractionSystem.HasLoot`/`.MissionComplete` properties become
thin pass-throughs to `SimulationService.Current` for whatever UI code still
wants to read them, or are removed if nothing does by the time this lands.

### 6. The panel→camera link, revisited

`InteractionSystem.PerformPanel` currently reads `controlsCameraId` off the
clicked panel's `Interactable.config` (a Unity-side `Dictionary<string,
LevelValue>` living on the `Interactable` MonoBehaviour). `PlanExecutor` is
pure C# and has no `Interactable` to ask. Two options:

- **(a)** `PlanBuilder.QueueInteract` resolves `controlsCameraId` *once*,
  at planning time (it already has the `Interactable` in hand, since the
  player tapped it), and bakes it into the queued `PlanAction.targetId`
  directly — the action becomes "toggle camera `cam_hall`", not "hack panel
  `panel_main`". Simpler for `PlanExecutor` (it never needs to look anything
  up beyond what's already on the action), consistent with the plan being a
  fully resolved, immutable script by the time Execute runs.
- **(b)** Carry `targetId` = the panel's own id, and give `PlanExecutor` a
  read-only reference to the level's `PropCatalog`/prop configs to resolve
  the link at execute time.

Recommend **(a)** — resolving at planning time is simpler, matches "the plan
is immutable and fully compiled before Execute" from `CLAUDE.md`, and avoids
handing `PlanExecutor` a level-data dependency it would otherwise need for
exactly one action type.

## Execute / Retry flow

```text
StartExecution():
    state = SimulationService.Current = initialSnapshot.Clone()
    missionClock.Reset(); missionClock.Resume()
    planExecutor.Begin(currentPlan)
    SetPhase(Execution)

GameController.Update(), only while CurrentPhase == Execution:
    planExecutor.Tick(SimulationService.Current, missionClock.CurrentTime)
    (SimulationStep.Tick already runs every fixed step regardless of phase —
     unchanged from U2)

StopExecution() / Retry:
    SetPhase(Planning)
    (currentPlan is NOT cleared — this is the actual point of Retry)
    state = SimulationService.Current = initialSnapshot.Clone()
    rebuild each actor's PlanCursor from the *plan's own* recorded end
    positions/times (not from live ActorState — Planning must resume
    exactly where the existing plan left off, so further taps append
    correctly)
```

"Same plan run twice gives the same result" falls out of this for free: both
runs start from byte-for-byte the same `initialSnapshot.Clone()`, tick the
same fixed step size, and dispatch the same sorted action list at the same
`earliestStart` times — nothing in the loop reads real wall-clock time or
`Time.deltaTime` (U2's whole point).

## Failure — plumbing only, not detection

`docs/00_UNITY_PORT_MASTER_PLAN.md` puts actual failure *detection* (a guard
seeing the thief) at U4, which doesn't exist yet — there is no vision system
to source a failure from. U3's job is narrower: make sure the *type* and the
*flow* exist and are exercised by at least one real case, so U4 only has to
call `ReportFailure(...)`, not invent the plumbing under time pressure.

```csharp
public struct FailureEvent
{
    public float time;
    public int actorId;
    public string source;   // e.g. "Guard1", "Pathfinding" — free text, U4 decides its own vocabulary
    public string reason;   // e.g. "Seen", "NoPath"
    public WorldPoint position;
}
```

The one real, already-possible failure case in U3's own scope: `MoveTo`
dispatch finds no path (`PathFinder.FindPath` returns empty — can happen if
the level changes under a stale plan, e.g. a door state diverges from what
was assumed at planning time). `PlanExecutor.Tick` sets `LastFailure` and
stops dispatching further actions for that actor; `GameController` observes
`LastFailure` becoming non-null, ends Execution, and surfaces it (for now:
`Debug.Log`, matching every other player-facing message in this project so
far — a real "FAILED / seen by Guard 1 / 00:12.43" HUD is `docs/00_UNITY_PORT_MASTER_PLAN.md`'s
later Plan Deck milestone, out of scope here).

## What stays untouched

`PlanModel.cs` (`PlanAction`/`ActorPlan`/`MissionPlan`/`DefaultDurationProvider`)
— already correctly shaped, described above, not modified beyond finally
being used. All five U2 systems (`ActorMovementSystem`, `GuardPatrolSystem`,
`SecurityCameraSystem`, `DoorSystem`, `SafeSystem`) and `SimulationStep` —
U3 calls into them, doesn't change them. `MissionClock`/`FixedStepAccumulator`
— unchanged.

## Migration order — three vertical slices

### 3a. Planning stops moving the actor

- Add `PlanCursor`, `PlanBuilder.QueueMove`.
- `GameController.OnFloorClicked`: replace the direct `SetDestination` call
  with `PlanBuilder.QueueMove`. Take the `initialSnapshot` right after level
  build (`GameBootstrap`, once).
- **Regression check**: tapping the floor during Planning no longer moves
  the thief (this is the headline, easy-to-verify behavior change) —
  `MissionPlan.actorPlans[thiefId]` grows with each tap; `ActorState.Position`
  does not change.

### 3b. Planning covers interactions, Execute replays the whole plan

- Add `PlanBuilder.QueueInteract`, `PlanExecutor`, `HasLoot`/`MissionComplete`
  on `MissionState`.
- `GameController.OnInteractableClicked`: replace `InteractionSystem
  .RequestInteract` with `PlanBuilder.QueueInteract`. Wire `StartExecution`/
  `StopExecution` per the flow above.
- `InteractionSystem`'s `Perform*` methods either get removed (their job
  moves into `PlanExecutor`'s dispatch table) or `InteractionSystem` itself
  is deleted and `PlanBuilder`/`PlanExecutor` fully replace it — decide once
  actually writing this step, based on how much genuinely still differs
  between "resolve what a tap means" (still needed, in `PlanBuilder`) and
  "perform an already-decided effect" (`PlanExecutor`'s job now).
- **Regression check**: the exact full-mission walkthrough this session's
  U2 work already validated live (door → panel/camera → safe → loot →
  extraction) — but now: tap through the whole plan first (thief never
  moves), press Execute once, and watch it play out unattended, ending in
  `MissionComplete == true`.

### 3c. Retry

- `StopExecution` restores `initialSnapshot` and rebuilds `PlanCursor`s from
  the existing plan's recorded end-states, per the flow above.
- **Regression check**: run the full plan from 3b to completion, hit Retry,
  confirm the world is back to exactly the starting snapshot (thief at spawn,
  door closed, camera powered, safe locked), then Execute the *same,
  untouched* plan again and confirm it reaches `MissionComplete == true` a
  second time with the same timing (`missionClock.CurrentTime` at completion
  matches run 1) — this is the concrete, testable form of "same plan, same
  result."

## Explicitly out of scope for U3

- **Vision/failure detection** — U4, as above; only the plumbing lands here.
- **Visual route preview** while planning (drawing the queued path on the
  floor) — genuinely nice for playtesting but not required for the loop to
  be correct; `PlanAction` already carries enough data (`targetPos`,
  `duration`) to add this later without a data-model change.
- **Editing/deleting a queued action, scrubbing time, a real Plan Deck UI**
  — `docs/00_UNITY_PORT_MASTER_PLAN.md`'s own later milestone (Этап 10).
  U3 only needs Retry to preserve the plan *as a whole*, not per-action
  editing.
- **Multi-actor plans** running concurrently in a meaningful way — the level
  only has one player-controlled actor (the thief) right now, so
  `MissionPlan`'s existing multi-actor shape is exercised by exactly one
  `ActorPlan`. Real synchronization is `docs/00_UNITY_PORT_MASTER_PLAN.md`'s
  Этап 9, after a second playable actor exists.
