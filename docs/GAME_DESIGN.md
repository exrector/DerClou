# Game Design Specification

Status: working design baseline, 2026-08-16.

## 1. High concept

A top-down heist-planning puzzle game in which the player studies a building, gives precise movement/interact orders to one or more burglars, commits the plan, and watches it execute against deterministic guards and security systems.

The pleasure should come from understanding the system and producing a clean plan.

Core emotional cycle:

**Observe → understand → plan → commit → tension → result → refine.**

## 2. Primary player fantasy

The player is the architect of the burglary, not the twitch-action burglar.

The game should make the player feel smart for discovering:

- a blind spot;
- a safe timing window;
- a quieter route;
- a hidden dependency between security devices;
- the right specialist/tool combination;
- a way to synchronize two or more actors;
- a way to steal extra loot without breaking the core plan.

## 3. Camera and screen

- Landscape orientation is the default design assumption for maximum building readability, unless prototype testing strongly favors portrait.
- Game world consumes essentially the full screen.
- Fixed high tactical camera.
- Prefer orthographic projection.
- The player should see enough of the current building section to reason spatially without constant camera fighting.
- Zoom/pan can exist for larger missions, but tap-to-move must remain reliable.

## 4. Input

No virtual joystick.

### Basic taps

- tap actor → select;
- tap navigable floor → move selected actor;
- tap interactable → approach and perform/queue appropriate action;
- tap device → inspect state/dependencies;
- tap another actor → switch control/planning focus.

### Optional gestures

- pinch → zoom;
- two-finger drag or edge pan → map pan;
- long press → detailed object information / action alternatives;
- scrub timeline → inspect plan state at a time position.

Avoid gestures that conflict with primary tap selection.

## 5. Game phases

### A. Recon / inspection

The player studies:

- building layout;
- doors/windows;
- visible cameras/lasers;
- guard patrols;
- security panels;
- loot;
- possible alternate routes.

Not every mission must hide information. The challenge is primarily planning, not random guessing.

### B. Crew/loadout

Later missions can require choosing:

- actors;
- tools;
- carrying tradeoffs;
- entry point;
- getaway/extraction plan.

This phase can be initially minimal and expand after the core mission engine works.

### C. Plan authoring

Player moves actors and performs actions in a planning simulation / recorder timeline.

The plan stores semantically meaningful commands, not only raw transform samples.

Examples:

```text
MoveTo(point)
Wait(duration)
OpenDoor(doorID)
Lockpick(doorID, toolID)
DisableAlarm(panelID)
ToggleSwitch(switchID)
CrackSafe(safeID)
TakeLoot(lootID)
Hide(hideSpotID)
EnterExtraction(exitID)
```

Each action has known start/end timing and preconditions.

### D. Commit / execute

The player starts the plan.

Default design assumption:

- plan executes autonomously;
- player watches;
- minimal or no intervention;
- failure returns the player to plan editing quickly.

This preserves the central tension: the player is watching the consequences of their own plan.

## 6. Deterministic simulation

The same plan against the same starting state should yield the same meaningful result.

Why:

- retry feels fair;
- timing improvements are meaningful;
- the player can debug a plan;
- missions behave like engineered puzzles.

Do not use random detection rolls, random lockpick failure or random guard deviations in the core campaign unless explicitly designed and communicated.

## 7. Time

Time is a first-class system.

Every important action has a duration.

Potential timing model:

```text
movementTime = pathDistance / baseMoveSpeed
interactionTime = baseObjectDifficulty × toolModifier × skillModifier
```

Exact formula TBD.

Keep values data-driven.

### Constant walking speed

Initial design decision: all normal actors share the same base movement speed.

Advantages:

- easier mental calculation;
- easier balance;
- less hidden complexity;
- player focuses on plan topology and specialist action times.

If later testing proves that different movement speed creates meaningful crew decisions, it can be reintroduced intentionally.

## 8. Actor capabilities

Suggested skill dimensions:

- lockpicking;
- safe cracking;
- electronics/security;
- strength/carrying;
- stealth/noise handling only if it produces clear gameplay;
- special mission abilities later.

Skills should affect transparent outcomes such as action time and tool access.

Avoid excessive RPG stat clutter.

## 9. Tool design

A tool should represent a tradeoff, not just a key.

Potential dimensions:

- compatible target type;
- action speed;
- noise;
- visible damage/evidence;
- weight;
- consumable durability/cost if needed.

Example:

- lockpick: slow, quiet, clean;
- crowbar: faster, noisy, leaves damage;
- drill: good on safes, loud;
- electronics kit: disables security, skill-dependent.

## 10. Environment primitives

### Structural

- Floor
- Wall
- Door
- Window
- Stair / floor transition
- Restricted/non-navigable zone
- Hiding area
- Entry point
- Extraction point

### Containers / objectives

- Safe
- Cash register
- Drawer
- Locker
- Cabinet
- Crate
- Computer/terminal
- Display case
- Painting/art object
- Cash/jewelry/valuable
- Mission-specific item

## 11. Door state model

Suggested explicit states:

```text
closedUnlocked
closedLocked
open
jammed/damaged
alarmArmed
alarmDisabled
```

Door may independently track:

- lock state;
- open/closed state;
- damage/evidence;
- connected alarm;
- key/keycard requirement.

Avoid encoding all behavior in one large enum if independent state is cleaner.

## 12. Security camera

A camera has:

- transform / mount;
- scan arc;
- scan period;
- field of view;
- range;
- enabled/disabled state;
- alarm relationship;
- occlusion via scene geometry.

Visual cone is a player-readable representation of the actual detection model.

Do not let displayed cone and real detection disagree.

## 13. Guards

### Patrol

- fixed waypoint route;
- deterministic pause durations;
- deterministic orientation/actions;
- possibly scripted door/object inspections.

### Vision

Detection needs:

- range;
- FOV angle;
- facing;
- geometry line-of-sight;
- optional short reaction timer later.

### Hearing

Actions emit noise events.

Noise may be represented as:

```text
NoiseEvent {
  origin
  intensity
  duration
  category
}
```

A guard hears the event if the game rules say the effective intensity at the guard exceeds a threshold.

The model must be understandable enough to communicate through UI.

## 14. Evidence / delayed discovery

This is an important differentiator.

The player can succeed locally and still fail later because a guard discovers evidence.

Potential evidence:

- broken window;
- forced door;
- door left open;
- locker/safe left open;
- missing monitored object;
- disabled security device;
- visible tool/damage state.

A patrol may have an `InspectTarget` step. During inspection it evaluates the target's state and can raise suspicion/alarm.

## 15. Alarms

Alarm is a system state, not merely an animation.

Potential consequences:

- mission fail immediately on high-security mission;
- countdown to police/security arrival;
- guards switch to alert route;
- cameras change scan behavior;
- doors lock;
- extraction becomes harder.

Initial vertical slice should use one simple consequence before implementing a complex global response.

## 16. Lasers / tripwires

Properties:

- enabled/disabled;
- linked alarm;
- linked switch/control panel;
- possibly timed disable window;
- visible beam corresponding to actual collision/detection volume.

## 17. Switches and security dependency graph

This is a central content system.

A switch may:

- toggle a device;
- disable a device for N seconds;
- require a key/skill;
- enable another switch;
- open/close a door;
- alter cameras/lasers/alarms.

Represent dependencies in reusable data, not bespoke level code.

Example:

```text
Switch_A disables Laser_B for 8 sec
Panel_C permanently disables Camera_D
Key_E unlocks OfficeDoor_F
OfficeSwitch_G disables WarehouseAlarm_H
```

## 18. Loot and carrying

Loot can have:

- value;
- weight/bulk;
- mandatory/optional status;
- evidence sensitivity;
- pickup duration.

The player may need to choose between:

- mission-safe minimal objective;
- extra valuables that increase risk/time/carry burden.

## 19. Objectives

Do not limit engine to “steal enough money.”

Supported objective grammar should eventually include:

- steal one specific object;
- reach minimum loot value;
- rescue person;
- sabotage device;
- place/install an item;
- retrieve key/intelligence;
- escape with all required crew;
- complete without alarm;
- leave no detectable evidence;
- optional bonus loot.

## 20. Multi-character planning

Later missions may have up to roughly 3–4 active actors, depending on UI testing.

Important mechanics:

- actor A holds/activates a switch while actor B crosses;
- actors execute parallel tasks;
- synchronized start windows;
- actor-specific tool/skill roles;
- one actor carries mission object while another prepares escape;
- separated entry points.

The timeline/plan editor must make concurrent actor plans comprehensible.

## 21. Level difficulty philosophy

Difficulty should come from **composition of understood systems**, not hidden information or arbitrary stat inflation.

Good difficulty increase:

- one guard → two intersecting patrols;
- static camera → rotating camera;
- direct switch → timed remote switch;
- one actor → two synchronized actors;
- one objective → optional high-value secondary objective;
- independent systems → dependency graph.

Bad difficulty increase:

- guards randomly change route;
- unexplained detection;
- microscopic tap targets;
- huge levels with no new reasoning;
- inflated interaction timers with no strategic meaning.

## 22. First mission philosophy

The first production-quality mission should already look like the final game, but systemically remain simple.

Suggested challenge:

- enter small office;
- guard patrol crosses corridor;
- camera covers direct approach;
- switch disables camera or laser;
- locked office contains safe;
- steal target;
- return to extraction.

The player learns:

- tap movement;
- observe timing;
- interact;
- use one security dependency;
- commit and execute.

## 23. UX requirements

The tactical view must answer at a glance:

- who is selected;
- where actor will go;
- what action will happen;
- how long it will take;
- what sees/hears the actor;
- whether a security system is active;
- what a switch controls when inspected;
- what failed during execution.

Failure report should be concrete, e.g.:

- “Guard saw Alex at 00:28.4”
- “Camera 02 detected movement at 00:42.1”
- “Door inspection revealed forced entry at 01:03.8”
- “Timed laser reactivated 0.7 s before crossing completed”

This makes retry part of the fun.

## 24. Metagame — intentionally unresolved

Potential systems from the original inspiration:

- city exploration;
- recruit accomplices;
- buy tools;
- buy getaway vehicles;
- fences/loot sale;
- reputation/progression.

Do not implement all of these until the core heist loop proves itself.

The mobile adaptation may replace free city walking with a faster mission/crew/equipment interface.

## 25. Monetization — unresolved

No monetization architecture has been fixed yet.

Do not design the core around energy timers, gacha or ad interruptions.

The current game concept naturally fits a premium or trial-to-premium model better than exploitative F2P, but this requires later business validation.

## 26. Success test

The vertical slice works if a player fails, immediately understands the cause, modifies one or two planned actions, re-runs the burglary, and experiences satisfaction when the corrected plan succeeds.