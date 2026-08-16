# Gamedev guide for this first large project

Status: project reference / operating guide

Purpose: prevent the most common mistakes in a first large game project, especially with AI-assisted development.

This guide is specific to this project: native iPhone game, Swift + SwiftUI + RealityKit + Reality Composer Pro 3, Claude Code first and Codex later.

## 1. Scope is the primary risk

The main danger is not writing Swift. It is uncontrolled scope, unclear rules, too many systems before the core loop is fun, and too much content before the level-authoring workflow is proven.

Treat generated code as comparatively cheap. Treat game design, architecture, content, art consistency, testing and level design as expensive.

## 2. Build a vertical slice first

The first real milestone is one small but polished mission containing the complete loop:

```text
observe -> plan -> move -> interact -> bypass security -> obtain objective -> extract -> execute -> success/failure -> edit -> retry
```

It can be only 3–5 rooms, but should already contain one actor, one deterministic guard, one camera, one door, one security dependency, one objective and extraction.

Do not build ten missions before this works.

## 3. Separate systems from level content

Generic systems are written once:

```text
Guard
Door
SecurityCamera
Laser
Alarm
Switch
Safe
Loot
Navigation
Vision
Noise
Planning
Execution
```

Mission content should mostly be data/configuration:

```text
guard_01 patrols A -> B -> C
camera_03 scans -45° ... +30°
switch_02 disables laser_01 for 8 seconds
safe_01 requires SafeCracking 3
objective = document_07
```

A normal future mission should require little or no new Swift.

## 4. Determinism is a feature

The same initial state + same plan must produce the same relevant result.

Avoid random guard pauses, hidden probabilities, frame-rate-dependent timing, uncontrolled physics and cosmetic animation affecting gameplay state.

The player should be able to fail by 0.6 seconds, fix that 0.6-second error, and trust the result.

## 5. Use an explicit simulation clock

Gameplay timing must not depend on render frames, SwiftUI animation timing or scattered `DispatchQueue.asyncAfter` calls.

Conceptually:

```text
00:00.0 Actor begins movement
00:03.8 reaches Door 02
00:04.3 Door is logically open
00:07.0 Guard reaches waypoint B
00:11.0 Lockpick begins
00:15.7 Lockpick completes
```

Rendering follows simulation. Rendering does not define simulation.

This enables planning, deterministic playback, rewind/reset, debugging, tests and later fast-forward.

## 6. Stable entity IDs are mandatory

Use stable IDs such as:

```text
actor_player_01
guard_lobby_01
door_manager_02
camera_corridor_03
switch_security_01
safe_office_01
```

Do not identify gameplay objects by array index, child order, world coordinates or IDs that change every launch.

## 7. Gameplay state is not transform state

The truth should be explicit:

```swift
door.state = .open
```

The 3D hinge rotation is only presentation. Do not infer game rules from arbitrary transforms.

## 8. Prefer state machines over boolean soup

Examples:

```text
DoorState: locked, closed, opening, open, closing, broken
GuardState: patrol, wait, inspect, investigate, alert
CameraState: scanning, disabled, alert
SafeState: locked, opening, open, empty
```

Explicit states are easier for humans, tests, Claude and Codex to reason about.

## 9. Debug visualization is a first-class feature

Development mode should be able to show:

- navigation mesh;
- requested path;
- guard waypoints;
- patrol timestamps;
- vision cones;
- real raycasts used for detection;
- noise radius;
- camera scan limits;
- entity IDs;
- current states;
- security dependency links;
- simulation clock;
- scheduled plan actions;
- last failure reason.

The displayed debug cone must use the same configuration as the actual detection code.

## 10. Prototype with primitives, then replace them

A capsule may temporarily be a guard and a cube may be a safe while proving engineering behavior.

The workflow is:

```text
prove mechanic -> replace with production asset -> retest scale/collision/lighting/readability -> polish vertical slice
```

Do not let programmer art become the intended final style.

## 11. Define an asset pipeline early

All 3D assets need shared conventions:

- world scale;
- axes/forward direction;
- pivot/origin rules;
- naming;
- material naming;
- texture policy;
- collision policy;
- animation naming;
- rig conventions;
- interaction anchors;
- placement anchors;
- optional UI/highlight anchors.

Door pivot belongs at the hinge. Camera pivot belongs at its physical yaw point. Character origin belongs at ground contact under the feet.

## 12. Gameplay feel is mostly tuning

Keep tunable values in configuration rather than magic numbers hidden in code.

Examples:

- actor speed;
- orthographic scale;
- camera tilt;
- tap radius;
- destination tolerance;
- interaction duration;
- FOV/range;
- guard waits;
- camera scan speed;
- route thickness;
- highlight intensity;
- haptic strength;
- sound volumes.

## 13. Save semantic gameplay data, not the entire rendered scene

Persistent data should describe product state:

```text
campaign progress
unlocked missions
mission results
crew/tools/resources
settings
saved plans
```

Plans should contain semantic actions:

```text
Move(actor_01, destination_A)
Wait(actor_01, 2.5)
Open(actor_01, door_03)
Disable(actor_02, camera_01)
Take(actor_01, loot_04)
```

not snapshots of entity transforms.

## 14. Version persistent data

Save data, mission definitions and plan formats need schema versions.

Example:

```text
saveSchemaVersion = 3
missionSchemaVersion = 2
planSchemaVersion = 4
```

During development either migrate old data or explicitly invalidate it. Do not allow changed `Codable` structs to silently break old TestFlight saves.

## 15. Design the plan model so undo/redo is possible

Users will eventually want to delete, insert, reorder, move and undo plan actions. Plan edits should therefore be semantic data transformations, not scattered mutations inside SwiftUI views.

## 16. Every failure needs a structured reason

Failure should not be only a Boolean.

Useful fields:

```text
timestamp
category
sourceEntityID
actorEntityID
zone/location
human-readable explanation
relevant timing delta
```

Categories can include guard detection, camera detection, noise, laser, alarm, evidence, missing objective, failed extraction or timeout.

This supports player feedback, debugging, analytics and automated testing.

## 17. Test on real iPhone early

Simulator/Mac performance is not the target.

Regularly test real hardware for frame pacing, thermals, memory, lights, shadows, entity counts, skeletal animation, transparency, shaders, touch accuracy, physical readability, haptics and audio.

## 18. Establish performance budgets after the first polished room

Record practical budgets for target FPS, lights, shadow casters, active guards/cameras, model complexity, texture memory, scene load time and memory footprint.

Budgets can change after profiling. Their purpose is to stop content production from becoming progressively more expensive.

## 19. Maintain a developer-only systems test scene

Keep controlled test areas for:

```text
Door lab
Camera lab
Guard vision lab
Noise lab
Navigation lab
Switch dependency lab
Timed switch lab
Safe/tool timing lab
Multi-actor synchronization lab
```

Test generic systems there before diagnosing them inside a complicated campaign mission.

## 20. Automated tests are valuable

Prioritize deterministic pure-logic tests for timeline scheduling, action durations, dependency graphs, plan serialization, save migration, state transitions, success conditions, failure classification, tool/skill rules and patrol schedules.

Example:

```text
laser disabled from 10.0 to 18.0
actor crossing runs from 17.2 to 18.4
expected: laser reactivates at 18.0 and mission fails
```

## 21. Level design is a separate discipline

For every level ask:

- what is the main insight?
- is the relevant information readable?
- is failure explainable?
- is there unnecessary waiting?
- can it be solved accidentally?
- is there a meaningful decision?
- does optional loot create real risk/reward?
- is the map readable on an iPhone?

The 180 slots in `CAMPAIGN_PLAN.md` are a content framework, not 180 finished designs.

## 22. Expect Level 1 to be rebuilt repeatedly

The first level will teach us practical room sizes, corridor widths, actor scale, door scale, useful FOV, patrol duration, camera scan speed, tap-target sizes, interaction timings and how much building should fit on screen.

Do not duplicate Level 1 into many missions until these fundamentals stabilize.

## 23. Prove that Plan -> Execute -> Watch is fun before scaling

Good failure reaction:

> I understand exactly what happened. I need to disable that camera three seconds earlier and delay the second actor here.

Bad failure reaction:

> I have to watch all of this again and hope something different happens.

If repeated planning feels like waiting rather than solving, fix the core first.

## 24. Avoid dead time

Deterministic patrols can accidentally make the correct strategy “wait 18 seconds”. Strategic waiting is valid; passive boredom is not.

Potential tools:

- timeline scrubbing during planning;
- explicit `Wait` actions;
- optional execution acceleration for irrelevant dead sections;
- simultaneous tasks for multiple actors;
- shorter meaningful patrol cycles;
- optional objectives during otherwise idle windows.

Measure this in the vertical slice before deciding the final UX.

## 25. Keep SwiftUI separate from simulation

SwiftUI displays and edits state. It does not define game rules.

Correct direction:

```text
SecuritySystem says alarm disabled -> UI displays disabled
```

not:

```text
button hidden -> therefore alarm disabled
```

## 26. Design for localization early

User-visible strings must be localizable. Logic should use IDs/enums, not parse localized text.

This includes mission names, objectives, failure explanations, tool descriptions, tutorial hints, settings and accessibility labels.

## 27. Accessibility is also good tactical design

Do not rely on red/green alone. Use icon/shape/state redundancy, scalable UI text, clear contrast, reduced-motion options for nonessential effects, haptics as supplemental feedback, and visible equivalents for important sound cues.

## 28. Audio should be semantic

Attach sounds to gameplay events such as lockpick complete, camera disabled, alarm changed, guard suspicion, objective collected, execution start and extraction success.

Do not bury gameplay-relevant sounds inside arbitrary animation callbacks.

## 29. Keep `main` buildable

As soon as the project is real:

- keep `main` working;
- use feature branches for major systems;
- tag meaningful milestones;
- document required Xcode/iOS SDK versions;
- separate release/debug configuration;
- ensure debug overlays cannot accidentally ship enabled;
- periodically verify clean checkout -> build -> run.

## 30. Git is recovery infrastructure for AI development

AI agents can rewrite many files quickly. Require checkpoints.

Example:

```text
main = known working state
feature/guard-vision
feature/security-graph
feature/plan-recorder
```

A large refactor should first state what problem it solves and what files/systems it will change.

Avoid giant unrelated agent rewrites.

## 31. Prevent AI over-architecture

Do not accept complexity because an agent can generate it cheaply.

A task like “make a security camera” should not turn into a hierarchy of generic factories/protocols unless multiple real use cases require it.

Rule:

> Build the smallest reusable architecture that solves the current verified need.

No speculative framework-building.

## 32. Record important decisions

Whenever a major choice becomes stable, update the repository documentation instead of relying on chat memory.

Examples:

- camera projection;
- movement speed model;
- timing rules;
- plan format;
- difficulty model;
- asset conventions;
- save schema;
- target devices;
- performance budgets.

`docs/DECISIONS.md` should remain the project decision log.

## 33. Difficulty should vary systems, not introduce randomness

The same map can support multiple deterministic scenario configurations.

Difficulty can change:

- guard patrol routes;
- guard inspection behavior;
- guard FOV/range;
- camera scan arcs/speeds/phase offsets;
- number of active cameras/guards;
- timed-switch windows;
- alarm dependencies;
- whether evidence is inspected;
- available crew/tools;
- optional loot pressure;
- permitted planning information.

Do not make Hard mode simply “everything is 30% faster”.

Most importantly, each difficulty configuration remains deterministic. A player can learn and solve it.

See `docs/DIFFICULTY_AND_VARIANTS.md`.

---

# Working definition of success

The project has crossed its first major threshold when one small polished level makes the player voluntarily replay it to perfect the plan.

Everything else — more missions, more assets, more story, more crew, more systems — should scale from that proof.