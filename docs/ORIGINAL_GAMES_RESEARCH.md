# Original games research

Research date: **2026-08-16**.

Purpose: extract the design grammar of the original *Der Clou!* games without cloning copyrighted content.

---

## 1. Naming / identity

### First game

- **Der Clou!**
- English title: **The Clue!**
- 1994 game by neo Software.
- Mixes adventure/RPG-like city interaction with tactical burglary planning.

### Second game

- **Der Clou! 2**
- English/North-American title: **The Sting!**
- Released in 2001.
- Russian release was known as **«Ва-банк! 2: Золотое издание»** / related localized naming depending on edition.
- Developer: neo Software.
- The sequel is the primary gameplay reference for this project.

The repository name `DerClou` is only an internal codename. Production title must be original.

---

## 2. Primary / useful reference links

### Der Clou! / The Clue! (1994)

#### Open-source lineage

Clou! Open Source Project (COSP):

https://sourceforge.net/projects/cosp/

Files root:

https://sourceforge.net/projects/cosp/files/

Open SDL Port source releases:

https://sourceforge.net/projects/cosp/files/Open%20SDL%20Port/

Preserved original game-data packages:

https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/

German Der Clou! + Profidisk files:

https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/Der%20Clou%21%20%2B%20Profidisk%20%28German%29/

English The Clue! + Profidisk files:

https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/The%20Clue%21%20%2B%20Profidisk%20%28English%29/

German CD version:

https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/Der%20Clou%21%20CD%20Version%20%28German%29/

English Amiga CD32 version:

https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/The%20Clue%21%20%28English%20Amiga%20CD32%29/

#### Important source-code caveat

COSP is GPLv2 and the surviving source tree is described by project discussion participants as **modified/restructured from the original Neo release**. The exact original Neo source archives historically named things such as `der_clue_base.zip` / `der_clue_install.zip` appear to have disappeared from the original Neo host; a 2023 discussion specifically asks whether anyone preserved them:

https://sourceforge.net/p/cosp/discussion/25891/thread/5e2dd6b92b/

Therefore:

- first-game source lineage exists and is useful for research;
- it is **not** automatically safe to copy into a commercial proprietary project because COSP is GPLv2;
- treat it as behavioral/design research unless an explicit licensing decision is made;
- do not assume the surviving COSP tree is byte-for-byte the original 1994 source release.

#### Modern first-game guide

GameFAQs walkthrough/reference:

https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/introduction

The guide includes sections on planning robberies, accomplices, vehicles, tools, execution, security systems and police investigation.

---

### Der Clou! 2 / The Sting! (2001)

#### Official German manual

Hosted by THQ Nordic, 26-page PDF:

https://www.ds.thqnordic.com/support/Clou2_Handbuch.pdf

The manual explicitly describes:

- the game as a burglary simulation;
- city/preparation mode;
- `Plan Aufzeichnen` / Record Plan;
- `Plan Starten` / Start Plan;
- choosing target, getaway vehicle, accomplices and tools;
- a maximum of three accomplices;
- each accomplice using up to three tools;
- switching control among hero/accomplices during planning;
- recording the burglary with a recorder-like planning interface;
- executing the finished plan according to the recorded actions;
- click-to-move control: click the destination where the hero should go.

#### English manual

English manual scan:

https://www.gamewholesale.com/downloads/Sting_Manual.pdf

Useful because it mirrors the German manual terminology in English, including **Record Plan**, **Main Plan Menu**, **New Plan**, **Edit Plan**, **Start Plan**, accomplices, tools, vehicles and receivers/fences.

#### Main strategy guide / all missions

Kasey Chang, *The Sting! Unofficial Strategy Guide and FAQ* (2001):

https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/14674

This is the single most useful mission-design source located. It contains hints and a complete walkthrough for all 18 jobs, plus lists of tools, accomplices and related systems.

Secondary mirror:

https://www.mogelpower.de/cheats/loesung.php?id=38954

Another GameFAQs guide (incomplete but useful as an independent source):

https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/29111

Historical metadata, box/manual images and screenshots:

https://www.mobygames.com/game/4295/the-sting/

Covers/manual scans index:

https://www.mobygames.com/game/4295/the-sting/covers/

Historical overview:

https://www.homeoftheunderdogs.net/game.php?id=3943

#### Source code status for the sequel

As of **2026-08-16**, research did **not** locate a legitimate public source-code release for *Der Clou! 2 / The Sting!*.

Do not assume sequel source is available. If a source tree is later discovered, verify provenance and license before using anything from it.

For our purposes, the manuals and detailed walkthrough provide enough information to reconstruct the **design grammar** independently.

---

## 3. What the sequel actually does that matters to us

The sequel's core is best thought of as a **time-based burglary puzzle**.

Broad loop:

1. Explore / prepare in the city.
2. Obtain tools, vehicles and accomplices.
3. Inspect a target.
4. Enter planning mode.
5. Choose target, crew, vehicle and tools.
6. Record precise movements/actions.
7. Edit/check the plan.
8. Start the plan.
9. Watch the recorded burglary execute.
10. Sell loot / progress / attempt harder jobs.

The conceptual innovation worth preserving is not the city walking. It is the **authoring and deterministic execution of a burglary plan**.

### Input

The official sequel manual describes mouse-only character control and click-to-move. This maps naturally to iPhone:

- tap destination on floor → navigate there;
- tap object → approach and perform contextual action.

### Crew

Original sequel variables include concepts such as:

- movement speed;
- lockpicking skill;
- safe-cracking skill;
- alarm-system skill;
- strength/carry capacity;
- tool choice.

Our adaptation deliberately simplifies base walking speed initially. Keep role differentiation through skills, action times, tool compatibility and carrying constraints.

### Tools

The original guide lists tools such as:

- axe;
- pickaxe;
- crowbar;
- core/hand drill;
- lockpick;
- sledgehammer;
- electric/cordless drill;
- soldering iron;
- cutting/blow torch;
- ground/tripod drill.

Do not copy the exact economy/balance automatically. Use the general idea that tools differ in:

- which obstacle they can defeat;
- action duration;
- noise;
- visible damage;
- weight/carry cost;
- possibly consumability.

### Guards

The walkthrough makes clear that patrols are predictable enough to plan around. Guards can differ in behavior:

- patrol fixed routes;
- inspect doors/windows;
- inspect valuables/areas;
- move between floors/buildings;
- create timing windows.

This deterministic behavior is central to our design.

### Noise and evidence

Important principle: a burglary action can matter after the player has left the immediate area.

Examples of design grammar:

- destructive entry may be noisy;
- a guard may later inspect a door and notice tampering;
- an unlocked/open object can reveal the burglary;
- closing/restoring an object can prevent detection;
- a quieter tool may be slower but leave fewer traces.

This should become a reusable `Evidence/WorldState` concept in our game rather than one-off scripted mission logic.

### Security dependency graph

A major strength of later sequel jobs is the relationship between systems:

```text
switch -> laser
switch -> alarm
alarm -> protected door/object
remote panel -> camera
key -> secure room -> switch -> warehouse alarm -> objective
character A action -> opens path for character B
```

The later missions become synchronization/dependency puzzles, not merely “avoid the cone.”

---

## 4. All 18 sequel jobs and what to learn from them

The mission names below come from Kasey Chang's full walkthrough. The descriptions here are **our design abstraction**, not a reproduction of the original walkthrough.

### 1. Gas Station

Teaches:

- one patrol;
- noise timing;
- basic entry;
- cash/loot interaction;
- waiting for a patrol window;
- return to getaway vehicle.

Our lesson: first mission can demonstrate movement + patrol + one interaction without a complex security graph.

### 2. Grocery Store

Teaches:

- hide in rooms;
- follow a civilian/patrol cycle;
- use vertical movement/floors;
- take multiple optional valuables;
- return through the entry route.

Our lesson: deterministic inhabitant movement + hiding spaces.

### 3. Cinema

Teaches:

- alternate entrance;
- lockpicking;
- indoor/outdoor patrol interaction;
- hiding in a restroom/room;
- guard checks that make destructive entry dangerous.

Our lesson: evidence/inspection behavior can change the correct tool choice.

### 4. Hotel

Teaches:

- specialist safe cracker;
- multi-floor patrol;
- noisy safe work only while guard is sufficiently far away;
- optional loot vs unnecessary risk.

Our lesson: action duration + noise + objective sufficiency.

### 5. Greenhouse / Arboretum

Teaches:

- coordination with a faster accomplice;
- alternate entry;
- timing around a technician's routine;
- taking an objective and escaping before a returning NPC discovers the missing object.

Our lesson: world-state discovery can be delayed; theft can have a future deadline.

### 6. Boxing Club

The guide describes this as the first job requiring alarm work.

Teaches:

- first explicit alarm bypass;
- alarm specialist;
- soldering/electronics-type tool;
- tradeoff between safe/slow and fast/risky plan;
- NPC can inspect a door and fail the plan if its state is wrong.

Our lesson: introduce electronic security after basic patrol understanding.

### 7. Printing Office

Teaches:

- multiple accomplices;
- carrying capacity;
- multiple specialist tasks;
- safe cracking + alarm work + lockpicking;
- hiding team members while another performs an objective.

Our lesson: crew composition becomes part of the puzzle.

### 8. Undertaker / Funeral Home

Teaches:

- alternate route/skybridge-like access;
- multi-floor patrol;
- safe interaction;
- close/restoration behavior matters;
- actors can perform parallel tasks.

Our lesson: “restore scene before guard arrives” is a strong puzzle primitive.

### 9. Mausoleum

The guide explicitly discusses cross-wired alarms and a switch controlling a trip beam.

Teaches:

- not every alarm should be directly defeatable;
- temporary/timed access window;
- one actor holds/activates access for another;
- cross-linked systems;
- synchronized movement.

Our lesson: add `TimedSwitch` and remote dependency primitives.

### 10. Spam Factory

Teaches:

- split actors across different buildings/areas;
- one actor disables security for another;
- safe specialist performs the actual objective;
- timing around multiple NPC routes.

Our lesson: remote assistance between actors.

### 11. The Villa

Teaches:

- primary mission item vs large optional loot pool;
- solo vs crew choice;
- rooftop/alternate path can bypass cameras;
- risk/reward from greed.

Our lesson: player should sometimes choose between clean mission completion and extra loot.

### 12. Neo Office

The guide emphasizes “cause and effect” among alarms/switches.

Teaches:

- large crew;
- multiple alarms and safes;
- layered laser barriers;
- switches that allow another team member to enter/leave;
- careful dependency ordering.

Our lesson: this is the template for a true security-graph puzzle.

### 13. Museum

Teaches:

- multiple floors and patrols;
- switches disabling cameras;
- camera room controlling protected systems;
- guards checking paintings/objects;
- optional loot optimization under carrying limits;
- several team objectives.

Our lesson: security systems can form a multi-stage hierarchy.

### 14. Bank

Teaches:

- large team / multiple roles;
- front/back route asymmetry;
- lasers and alarms;
- split teams;
- multiple safes/vault stages;
- carrying capacity matters to mission completion;
- enter one way, leave another.

Our lesson: large open-ended capstone heist before narrative/special missions.

### 15. Barracks

This job is a rescue, not a loot job.

Teaches:

- objective type can change completely;
- preselected rescue character;
- separated teams;
- two remote switches must be coordinated;
- strict timing window;
- escort extraction.

Our lesson: system supports non-loot objectives and synchronized switches.

### 16. Harbor

Teaches:

- mission-specific key acquisition;
- ship/club/warehouse dependency chain;
- key opens room;
- room switch disables warehouse security;
- alarm specialist + safe specialist + fast runner + carrier roles;
- repeated coordination of remote systems.

Our lesson: strong chain:

```text
obtain key -> unlock room -> use switch -> disable alarm -> crack container -> obtain mission object -> extract
```

### 17. Power Plant

Teaches:

- mission object placement rather than theft;
- several guard routines;
- three teams;
- one team's actions create access for another;
- speed and timing dominate;
- staged barriers.

Our lesson: mission goals can be sabotage/placement while using the same engine primitives.

### 18. Ministry of Light

Final integrated puzzle.

Teaches:

- multiple starting positions;
- cameras/lasers;
- guard-following and hiding;
- remote switches;
- rescue/freeing another actor;
- one actor's progress repeatedly unlocks another's path;
- final multi-character dependency puzzle.

Our lesson: campaign finale combines learned primitives rather than adding arbitrary new rules.

---

## 5. Level-design grammar extracted from the 18 jobs

A new campaign should introduce primitives in approximately this conceptual order, while using completely original maps and scenarios:

### Tier A — spatial basics

- tap movement;
- locked/unlocked door;
- one fixed patrol;
- vision;
- one loot objective;
- extraction.

### Tier B — timing/evidence

- waiting/hiding;
- noise radius;
- interaction duration;
- guard inspections;
- destructive vs clean tools;
- optional loot.

### Tier C — specialists/security

- safe cracker;
- electronics specialist;
- alarm panel;
- camera;
- laser/tripwire;
- switch.

### Tier D — dependencies

- remote switch;
- timed switch;
- cross-linked security;
- key/keycard dependency;
- security control room;
- action in area A changes area B.

### Tier E — multi-agent planning

- separate actors;
- parallel actions;
- synchronized actions;
- carrying limits;
- actor-specific tool/skill restrictions;
- extraction ordering.

### Tier F — advanced objectives

- rescue;
- sabotage;
- plant/place an item;
- steal a specific mission item;
- avoid evidence rather than maximize loot;
- multiple entry/exit routes.

---

## 6. What to preserve vs what to modernize

### Preserve conceptually

- planning matters more than reflexes;
- execution of a plan is satisfying to watch;
- predictable systems create fair puzzles;
- multiple valid plans should exist when possible;
- tools/crew choices influence the plan;
- later missions are dependency graphs;
- failure should teach something concrete.

### Modernize

- iPhone-first touch interaction;
- remove clumsy 2001 PC camera/control conventions;
- native 3D top-down presentation;
- much clearer security-state visualization;
- immediate retry/edit workflow;
- modern save/checkpoint behavior;
- better onboarding without flattening depth;
- production-quality animation and lighting;
- data-driven reusable level components;
- potentially reduce/remove city wandering if it does not serve the core loop.

---

## 7. Legal boundary

Do not recreate the original 18 layouts from walkthrough descriptions.

Do not use original names, dialogue, story, models, textures, audio or mission text.

The research objective is to learn abstract relationships such as:

- “guard checks a changed door later”;
- “switch temporarily disables laser”;
- “one actor opens a path for another”;
- “specialist + tool determines action duration.”

Those abstract gameplay concepts should be implemented with original content and independently authored logic.