# CLAUDE.md — DerClou project instructions

## PRIORITY 0 — READ THIS BEFORE DOING ANYTHING

**The first and authoritative current implementation plan is:**

`docs/00_UNITY_PORT_MASTER_PLAN.md`

Read that file **before** `README.md`, old roadmaps, Swift/RealityKit architecture notes, or any other implementation document.

If any older document conflicts with `docs/00_UNITY_PORT_MASTER_PLAN.md` about the active engine, current implementation target, work order, rendering pipeline, or migration status, **the master plan wins** until the owner explicitly changes it.

## Current source of truth

- **Active production target:** `UnityPort/`
- **Engine:** Unity **6000.5.9f1 / Unity 6.5.9f1**
- **Language:** C#
- **Platform target:** Apple ecosystem first, iPhone/iOS first
- **Swift + SwiftUI + RealityKit implementation:** **FROZEN REFERENCE IMPLEMENTATION**. Keep it in the repository and mine it for validated behavior, algorithms, tests, design lessons and contracts. Do not delete it and do not treat it as the active production codebase.
- Do not migrate away from Unity unless the owner explicitly changes the decision.

## Mandatory current work order

Follow `docs/00_UNITY_PORT_MASTER_PLAN.md` literally. In particular, the current sequence is:

1. **U0 — repository source of truth**: Unity is active; Swift is frozen reference; onboarding/docs must say so.
2. **U1 — Built-In → URP** using Unity's official Render Pipeline Converter, preserving the existing playable loop.
3. **U2 — pure-C# deterministic simulation authority**: gameplay state/outcomes must not depend on `Time.deltaTime` or GameObject transforms.
4. **U3 — real planning loop**: planning creates actions without moving the actor; Execute restores the initial snapshot and deterministically replays the immutable plan; failure reports time/source/reason; retry preserves the plan.
5. **U4 — deterministic guard vision** using the same simulation data as the visible cone, producing the first genuine `plan → execute → fail/succeed → edit → retry` greybox mission.

**Until U4 is complete, do not spend project time on additional characters, polished materials, additional levels, a complex camera, or unrelated feature expansion unless the owner explicitly asks for it.**

## Read after the master plan

1. `docs/00_UNITY_PORT_MASTER_PLAN.md`
2. `README.md` — product history/context; some native-stack wording may be historical until updated
3. `docs/GAME_DESIGN.md`
4. `docs/PRODUCTION_PLAN.md`
5. `docs/TECHNICAL_ARCHITECTURE.md` — use Swift-specific implementation details as reference, not current engine instructions
6. `docs/UI_AND_CAMERA.md` — design/research history, not an instruction to recreate the old RealityKit camera
7. `docs/IMPLEMENTATION_STATUS.md` — Swift reference baseline
8. `docs/ART_DIRECTION.md`
9. `docs/IP_AND_LEGAL_BOUNDARIES.md`
10. `docs/CAMPAIGN_PLAN.md`
11. `docs/DIFFICULTY_AND_VARIANTS.md`
12. `docs/ORIGINAL_GAMES_RESEARCH.md`

Do not ask the owner to re-explain facts already present in the repository.

## Project in one sentence

Build a polished top-down / 2.5D heist-planning puzzle game for iPhone, inspired by the **planning/execution grammar** of *Der Clou! 2 / The Sting!* while using original IP, with Unity as the active engine.

## Non-negotiable gameplay decisions

- Real 3D world viewed from above; not a 2D sprite-sheet game.
- No virtual joystick.
- Tap floor/room/corridor to create movement intent; tap world objects for contextual interaction.
- Constant base walking speed in the initial design.
- Crew differences primarily come from skills, permitted actions, carrying capacity and action duration.
- Guards/patrols are deterministic and learnable.
- The central game is **planning → commit → execution → explainable failure/success → edit → retry**.
- Do not turn the project into a reflex stealth/action game.
- Same mission state + same plan + same deterministic variables must produce the same relevant result.
- A failure must be explainable with exact timing and source, so the player can correct the plan rationally.

## Current architecture rule

`DerClou.Core` must become the gameplay authority.

Core simulation decides **what happened**. Unity decides **how it looks**.

Unity presentation objects — GameObjects, Transforms, Animator, visual door rotation, visual camera head rotation, particles, shaders and UI — must not become the authoritative source of mission outcomes.

The custom grid/A* already in `UnityPort` is the validated current movement foundation. Do not silently replace deterministic routing with `NavMeshAgent` local avoidance as gameplay authority.

## Planning rule

During Planning:

- a floor tap may calculate a path and duration;
- it appends a `PlanAction` to `ActorPlan` / `MissionPlan`;
- the real actor **does not execute that move yet**;
- the planned route may be previewed visually.

During Execute:

- restore `MissionInitialSnapshot`;
- reset mission time to zero;
- run the immutable compiled plan against deterministic simulation;
- presentation follows simulation;
- on failure, return a structured failure event with time, actor, source, reason and relevant position/state;
- returning to Planning preserves the plan for editing.

## Visual direction

The production target remains a polished tabletop/tactical diorama with believable 3D volume, materials, shadows and readable silhouettes. Greybox is allowed internally while proving systems, but is not the target look.

The Unity project currently needs the Built-In → URP migration described in the master plan before production rendering work expands.

Do not recreate the old RealityKit custom off-axis projection merely because it exists in the Swift reference. Treat it as research history. The Unity camera should remain simple until the core planning loop is proven unless the owner explicitly asks otherwise.

## Character / animation rule

Do not bulk-port the whole character library before U4.

When character integration resumes, validate one real humanoid first:

- correct Humanoid avatar/rig;
- Idle and Walk;
- correct scale;
- no foot sliding;
- stable Animator behavior;
- correct shadows/materials under the chosen render pipeline.

Then expand to guards and upper-body/additive interaction layers.

## Original-game / IP rules

`docs/IP_AND_LEGAL_BOUNDARIES.md` remains mandatory project policy.

Do not copy original maps, mission layouts, characters, plot/dialogue, artwork/audio, code, distinctive UI expression, or protected names. Study abstract mechanics, timing grammar, dependency patterns, patrol behavior, tool tradeoffs and multi-character planning; then independently redesign production content.

## Working with the owner

- The owner drives product/game design and does not want to hand-write routine implementation code.
- Check the repository before asking basic context questions.
- Verify technical claims against the **current** relevant Unity documentation and the actual installed/project version before recommending installs, render pipelines, packages, APIs or workflows. Do not rely on stale version assumptions.
- When a blocker exists, state it immediately.
- Do not silently change selected technologies or scope.
- Keep the active build working and create checkpoints before destructive or one-way migrations.
- When the owner explicitly changes a decision after seeing the running result, implement the change first and then update documentation so the repository remains truthful.
