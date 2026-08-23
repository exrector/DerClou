# U2 — deterministic simulation: migration design (no code yet)

Status: design note, approved process per owner instruction 2026-08-23 ("сначала
план U2, без изменений кода... после этого начинай U1 и затем U2 по утверждённой
схеме"). This document is what gets executed once U1 (Built-In → URP) is done.
Nothing in this file has been implemented yet.

Parent context: `docs/00_UNITY_PORT_MASTER_PLAN.md` §Milestone U2 and its
`CLAUDE.md` §"Current architecture rule": *Core simulation decides what
happened. Unity decides how it looks.*

## The actual problem, grounded in the real code

None of this is hypothetical — every reference below is to code that exists in
`UnityPort/Assets/DerClou/` right now:

- `ActorEntity.Update()` (`Gameplay/Actors/ActorEntity.cs`) moves
  `transform.position` itself, stepping along `currentPath`/`pathIndex` at
  `Profile.walkSpeed * Time.deltaTime`. The actor's position lives only on the
  Transform — there is no separate "where is the actor" fact anywhere else.
- `Door.Update()` (`Gameplay/Props/Interactables.cs`) animates
  `currentProgress` toward `IsOpen ? 1 : 0` using `Time.deltaTime` directly.
- `SecurityCamera.Update()` advances `scanPhase += Time.deltaTime / ScanPeriod`
  directly — not even routed through `MissionClock`.
- `Safe.StartCracking(dt)` exists and is correct in shape, but is called from
  `InteractionSystem.Update()` with `Time.deltaTime` as the argument.
- `GuardPatrolSystem.Update()` (the MonoBehaviour) is *closer* to correct — it
  already reads `missionClock.DeltaTime` instead of `Time.deltaTime` — but
  `missionClock.Tick(dt)` itself is fed `Time.deltaTime` once per
  `GameController.Update()`, a variable-length frame, not a fixed step. It also
  reads `entity.transform.position` and calls `entity.SetDestination(...)` —
  i.e. it treats `ActorEntity`'s presentation state as ground truth, so it
  inherits the same non-determinism transitively even though its own line
  doesn't say `Time.deltaTime`.
- `GameController` already has a `FixedStepAccumulator fixedStep` field and a
  `FixedTick(dt)` method — but `FixedTick` currently does nothing but
  `patrolSystem.enabled = true;`. The fixed-step scaffolding exists and is
  unused. U2's job is largely to actually wire it up, not invent it.
- `SimulationComponents.cs` already has dead, unused pure-data structs shaped
  almost exactly like what's needed: `DoorComponent`, `SecurityCameraComponent`,
  `SafeComponent`, `GuardComponent`. None of the four live MonoBehaviours
  (`Door`, `SecurityCamera`, `Safe`, `GuardPatrolSystem`) actually read or write
  them today. U2 turns these from dead code into the real source of truth
  instead of writing new ones from scratch.
- One caveat in the same file: `VisionComponent` uses `UnityEngine.Vector3`
  directly, contradicting the file's own "pure C#" doc comment. Not in U2's
  scope (vision is U4) — noted here so nobody re-discovers it as a surprise.

## Target shape

```text
DerClou.Core.Simulation
    MissionState
    ├── ActorState[]      (by ActorId)
    ├── GuardState[]      (by ActorId)
    ├── DoorState[]       (by DoorId)
    ├── CameraState[]     (by CameraId)
    └── SafeState[]       (by SafeId)

    MissionClock            (already exists, unchanged — owns "what time is it")
    FixedStepAccumulator    (already exists, unchanged — owns "how many fixed
                              steps has real time produced")
    SimulationStep           (new — owns "given one fixed step, what happens")

DerClou.Core.Systems
    ActorMovementSystem.Tick(MissionState, float dt)
    GuardPatrolSystem.Tick(MissionState, float dt)      (new pure-C# class —
                                                           name clash with the
                                                           existing MonoBehaviour
                                                           is intentional and
                                                           resolved by namespace,
                                                           see "Naming" below)
    SecurityCameraSystem.Tick(MissionState, float dt)
    DoorSystem.Tick(MissionState, float dt)
    SafeSystem.Tick(MissionState, float dt)

DerClou.Gameplay (Unity-side, presentation only)
    ActorView    (renamed from ActorEntity)
    GuardView    (renamed from the GuardPatrolSystem MonoBehaviour)
    DoorView     (renamed from Door)
    CameraView   (renamed from SecurityCamera)
    SafeView     (renamed from Safe)
```

A View's job, without exception: read its own state entry out of
`MissionState.Current`, set `transform.position` / `transform.rotation` /
`Animator` parameters from it. A View never decides game state. If a View
method currently *decides* something (e.g. `Door.IsLocked` gating `Open()`),
that decision moves into the matching System.

## Who owns time

No third clock class. The two pieces that already exist keep doing exactly
what they do today:

- `MissionClock` — "what time is it" (`CurrentTime`, `DeltaTime`, `IsPaused`,
  `Tick(dt)`). Unchanged.
- `FixedStepAccumulator` — "how many whole fixed steps has real elapsed time
  produced" (`Accumulate(dt)`, `TryConsume()`). Unchanged.

New: `SimulationStep.Tick(MissionState state, MissionClock clock, float
fixedDt)` — the single entry point. `GameController.Update()` still does
`fixedStep.Accumulate(Time.deltaTime)`, but its `while (fixedStep.TryConsume())`
loop now calls `SimulationStep.Tick(...)` instead of the current no-op
`FixedTick`. `SimulationStep.Tick` calls `clock.Tick(fixedDt)` once, then runs
the five Systems in a fixed order:

```text
ActorMovementSystem → GuardPatrolSystem → SecurityCameraSystem → DoorSystem → SafeSystem
```

Order matters in one place: `GuardPatrolSystem` reads the actor's current
position to decide arrival, so `ActorMovementSystem` must run first in the same
step. Every other pair is independent.

## How a View gets state

Polling, not events. Each `*View.LateUpdate()` reads
`SimulationService.Current.Actors[id]` (or the matching dictionary) and applies
it to the Transform/Animator. `SimulationService` is a new static class,
deliberately copying the pattern `NavigationService` already uses for
`NavGrid` (`Gameplay/Level/NavigationService.cs`) — one mutable static
property, no event bus, no dependency injection framework. This project
already has exactly one precedent for "how does Unity code reach shared
simulation state" and U2 reuses it rather than adding a second pattern.

```csharp
public static class SimulationService
{
    public static MissionState Current { get; set; }
}
```

## Snapshot / reset — the one primitive U2 owes U3

U2 does not build plan execution, restore-on-Execute, or replay — that is U3.
But U3 cannot exist without a way to snapshot and restore `MissionState`
deterministically, and that's cheap to deliver now while the state shape is
being defined anyway: `MissionState.Clone()`, a plain deep copy (new
dictionaries, new arrays, value-type states copied by value). No snapshot
*storage*, no "restore on Execute" wiring, no `MissionInitialSnapshot` type —
those are U3's job and are out of scope here.

## Migration order — five vertical slices, each one shippable

Each step below is a self-contained PR-sized change. The project must build,
run, and pass its regression check after every single one — never a half-done
step spanning two of these.

### 2a. Actor movement (first — everything else reads actor position)

- Add `MissionState`, `ActorState`, `SimulationService`.
- Add `ActorMovementSystem.Tick` — the exact algorithm
  `ActorEntity.Update()` has today (step along `currentPath` at
  `walkSpeed * dt`, planar arrival tolerance, `Quaternion.RotateTowards`
  facing), just reading/writing `ActorState` instead of `transform`.
- Wire `GameController`'s fixed-step loop to actually call it.
- Rename `ActorEntity` → `ActorView`. `SetDestination`/`Stop` become thin calls
  that write into `ActorState` via `PathFinder` (same as today) instead of
  mutating private fields. `LateUpdate` applies `ActorState.Position` to the
  Transform and drives the Animator from `ActorState.HasPath`.
- **Regression check**: tap-to-move still walks the thief to the clicked point,
  same speed and arrival feel as the live test earlier this session.

### 2b. Guard patrol

- Add `GuardState` (adapted from the existing dead `GuardComponent`) into
  `MissionState.Guards`.
- New `DerClou.Core.Systems.GuardPatrolSystem.Tick` — ports today's
  `TickGuard` state machine (Moving/Waiting/Acting/Alert) to read/write
  `GuardState` and `ActorState` through `MissionState`, never touching a
  Transform or calling an `ActorView` method.
- Old MonoBehaviour `GuardPatrolSystem` → `GuardView`: no longer runs the
  state machine, only drives `Animator` from `GuardState`/`ActorState` each
  frame.
- **Regression check**: same position-over-time test used earlier this
  session — all three guards complete multiple patrol loops without freezing.

### 2c. Security camera

- Add `CameraState`.
- New `SecurityCameraSystem.Tick` — `scanPhase += fixedDt / scanPeriod`, same
  formula as today, just fed a fixed step instead of `Time.deltaTime`.
- `SecurityCamera` → `CameraView`: rotates the transform/cone from
  `CameraState.currentYaw` each frame. `Powered` becomes a `CameraState`
  field; `InteractionSystem`'s panel toggle (`PerformPanel`) flips that field
  instead of calling `cam.Powered = ...` on the MonoBehaviour directly.
- **Regression check**: panel click still disables the camera (state and
  visible rotation both stop); cone still rotates at the documented rate.

### 2d. Door

- Add `DoorState`.
- New `DoorSystem.Tick` — advances `openProgress` toward the target at
  `openSpeed * fixedDt`, same math `Door.Update()` has today.
- `Door` → `DoorView`: applies `DoorState.openProgress` via the same
  `Quaternion.Slerp(closedRot, openRot, progress)` it already uses.
  `Open()/Close()/Toggle()/IsLocked` become `DoorState` mutations;
  `InteractionSystem.PerformDoor` reads/writes `DoorState` instead of calling
  MonoBehaviour methods.
- **Regression check**: door still swings open on interaction, same duration.

### 2e. Safe (last — depends on nothing else)

- Add `SafeState`.
- New `SafeSystem.Tick` — advances `crackProgress` by `fixedDt /
  crackDurationSeconds` while a "being cracked" flag is set on the state
  (mirrors `InteractionSystem`'s current `crackingSafe`/`crackingActor`
  tracking, moved into state).
- `Safe` → `SafeView` (presentation only; no visible change today on open,
  same as now). `InteractionSystem.PerformSafe`/`Update` read/write
  `SafeState` instead of calling `safe.StartCracking(Time.deltaTime)`.
- **Regression check**: the full live walkthrough already proven this session
  — door → panel/camera → safe → loot → extraction — still completes
  end-to-end, with the safe now advancing on simulated fixed steps.

## What stays untouched

`PathFinder`, `NavigationData`/`NavGrid`, `LevelBlueprint`/`PropCatalog`/
`WorldPoint`/`WorldBox`, `MissionClock`, `FixedStepAccumulator`,
`PlanModel.cs` (`PlanAction`/`ActorPlan`/`MissionPlan` — U3's job, not
touched here). `InteractionSystem` stays a `MonoBehaviour`: it is input→state
glue, not state itself, and keeps that role — it changes from calling methods
on Door/Safe/SecurityCamera MonoBehaviours to reading/writing the matching
`*State` records in `MissionState.Current`.

## Naming note

The new pure-C# `GuardPatrolSystem` (in `DerClou.Core.Systems`) and the
existing MonoBehaviour of the same name are two different classes in two
different namespaces. The MonoBehaviour gets renamed to `GuardView` as part of
step 2b specifically so this stops being two classes sharing one name — the
overlap only exists transiently in this document, not in the final code.

## Explicitly out of scope for U2

Restating the owner's list plus why each one would blow up the estimate if
folded in now:

- **Actor collision/encounter prediction** — needs its own conflict-resolution
  design; bolting it onto the state-migration step would couple two unrelated
  risks in one change.
- **Funnel/corridor navigation** — the existing grid A* stays exactly as is;
  swapping the pathing backend is an unrelated project.
- **Automatic door traversal** — planned later in the master plan (after U4);
  needs the planning layer (U3) to exist first to make sense.
- **Full security dependency graph** — the current hardcoded panel→camera link
  (`controlsCameraId` in `Level01Builder`) stays exactly as is.
- **Multi-actor scheduling/synchronization** — master plan's own U9, needs a
  second playable actor to even test against.
- **Complex animation state machine** — keep the existing Walk/Idle bool; no
  upper-body layers, no blend trees added here.
- **Vision/detection** — explicitly U4, a separate milestone, and the master
  plan is specific that camera/vision math must read the same state this
  milestone produces rather than `Physics.Raycast` — reason enough to keep it
  a separate step done right, not folded in here.

No new abstractions beyond this list: no event bus, no generic ECS framework,
no reflection-based system registry. `SimulationStep.Tick` is a fixed,
hand-written sequence of five method calls. That is the whole "engine."
