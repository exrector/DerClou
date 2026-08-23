# AGENTS.md — Codex onboarding

## PRIORITY 0 — READ THIS FIRST

Before any nontrivial work, read:

1. `docs/00_UNITY_PORT_MASTER_PLAN.md`
2. `CLAUDE.md`
3. `README.md`
4. the supporting docs referenced by the master plan

`docs/00_UNITY_PORT_MASTER_PLAN.md` is the **authoritative current implementation plan**. If an older document conflicts with it about the active engine, migration state, rendering pipeline, current work order or Swift/Unity ownership, **the master plan wins** until the owner explicitly changes the decision.

## Current project source of truth

- **Active production target:** `UnityPort/`
- **Engine:** Unity **6000.5.9f1 / Unity 6.5.9f1**
- **Language:** C#
- **Primary platform:** Apple ecosystem first, iPhone/iOS first
- **Swift + SwiftUI + RealityKit codebase:** **FROZEN REFERENCE IMPLEMENTATION**. Keep it. Use it to recover validated behavior, algorithms, tests and design lessons. Do not treat it as active production code and do not delete it.
- Do not migrate away from Unity unless the owner explicitly changes the decision.

## Mandatory milestone order

Follow the master plan in this order:

- **U0:** repository/docs source-of-truth cleanup.
- **U1:** Built-In Render Pipeline → URP using Unity's official conversion path; preserve the current playable loop and zero Console errors.
- **U2:** make `DerClou.Core` the sole gameplay authority; critical simulation must not depend on `Time.deltaTime` or GameObject transforms.
- **U3:** implement actual planning/commit/execution/retry semantics around the existing `PlanAction`, `ActorPlan` and `MissionPlan` models.
- **U4:** one deterministic guard, pure-C# vision and a visible cone driven by the same authoritative numbers, yielding a genuine `plan → execute → fail/succeed → edit → retry` mission.

Until U4 is complete, do not expand into extra characters, additional levels, polished materials, complex camera work or unrelated systems unless the owner explicitly asks for them.

## Core gameplay constraints

- Real 3D world viewed from above; not a sprite game.
- No virtual joystick.
- Planning and execution are separate phases.
- During Planning, taps create/modify plan actions; they must not immediately execute the final actor movement.
- During Execution, restore the mission's initial snapshot and deterministically replay the immutable compiled plan.
- Same state + same plan + same deterministic variables must produce the same relevant outcome.
- Failures must report enough structured information to explain exactly what happened and when.
- Guards and security systems must be deterministic and learnable.
- Do not turn the project into reflex stealth/action gameplay.

## Architecture constraints

`DerClou.Core` owns gameplay truth. Unity owns presentation.

GameObject transforms, Animator state, visual camera motion, visual door rotation, particles, physics presentation and frame timing must not silently become the source of mission outcomes.

The current custom grid/A* pathfinding is the validated migration backend. Do not silently replace it with nondeterministic `NavMeshAgent` local avoidance as gameplay authority.

Do not blindly port the most complex Swift navigation machinery before the core planning loop is proven. Use the Swift implementation as reference and import only the behavior/contracts currently needed.

## Rendering

The Unity project recorded in the repository is Unity 6000.5.9f1 and currently needs the Built-In → URP migration specified by `docs/00_UNITY_PORT_MASTER_PLAN.md` before production rendering expands.

Create a checkpoint before one-way render-pipeline conversion. Verify the existing door/panel/camera/safe/loot/extraction live slice still works afterward.

Do not recreate the old RealityKit custom off-axis camera merely because it exists in the reference implementation. Keep camera work simple until the core game loop is proven unless the owner explicitly changes that priority.

## Assets and animation

Do not bulk-port all characters before U4. When character work resumes, validate one humanoid end-to-end first: correct scale, Humanoid rig, Idle/Walk, stable Animator behavior, no foot sliding, correct materials and shadows.

## IP boundary

`docs/IP_AND_LEGAL_BOUNDARIES.md` remains mandatory. Use the original games only to study abstract design grammar. Do not copy protected maps, layouts, characters, story/dialogue, art/audio, code or distinctive presentation.

## Agent behavior

- Check the repository before asking the owner to repeat context.
- Verify recommendations against current Unity documentation and the actual project/editor version before recommending installs, packages, render pipelines, APIs or workflows.
- Surface blockers immediately.
- Keep main/buildable checkpoints before destructive changes.
- Do not silently change the engine, render pipeline strategy, gameplay model or milestone order.
- Owner decisions after inspecting the running game outrank stale documentation; implement the decision and then make the docs truthful again.
