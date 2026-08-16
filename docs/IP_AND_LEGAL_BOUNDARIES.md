# IP and legal boundaries

Status: project policy / legal-risk guardrail

Last reviewed: 2026-08-17

This document defines the intellectual-property boundaries for this project. It is not a substitute for advice from a qualified lawyer before commercial release, but it is the operating rule for all design, implementation, art, writing, naming, and agent-assisted development in this repository.

## Bottom line

The project may use the **general idea, gameplay concepts, systems, methods, and design grammar** associated with *Der Clou! / The Clue!* and *Der Clou! 2 / The Sting!*.

It must **not copy the protected expression** of those games: their specific maps, characters, story, dialogue, artwork, music, sounds, models, text, distinctive UI presentation, or source code.

The production game must be a **spiritual successor**, not a remake, sequel, port, clone, restoration, or reimplementation of copyrighted content.

The internal repository name `DerClou` is only a research codename. The commercial title must be original and independently cleared for trademark risk before release.

---

## 1. Why the gameplay idea itself is generally usable

The U.S. Copyright Office explicitly states that:

- the **idea for a game** is not protected by copyright;
- the **methods for playing a game** are not protected by copyright;
- copyright protects original expression, not ideas, procedures, systems, processes, methods, concepts, or principles.

Official references:

- U.S. Copyright Office — Games: https://www.copyright.gov/register/tx-games.html
- U.S. Copyright Office — What Is Copyright?: https://www.copyright.gov/what-is-copyright/
- U.S. Copyright Act, 17 U.S.C. § 102(b): https://www.copyright.gov/title17/92chap1.html
- U.S. Copyright Office — Computer Programs: https://www.copyright.gov/register/tx-programs.html

The European IP Helpdesk expresses the same general idea/expression distinction for videogames: copyright protects the **expression of ideas**, not the ideas themselves, and similar ideas expressed independently in different ways are not automatically infringement.

Official EU reference:

- European IP Helpdesk — IP in the Videogames Industry: https://intellectual-property-helpdesk.ec.europa.eu/regional-helpdesks/european-ip-helpdesk/europe-ip-specials/europe-ip-specials-ip-videogames-industry_en

Therefore, the following high-level concepts are considered part of the project's safe design vocabulary, provided they are independently implemented and expressed:

- burglary/heist planning as a game concept;
- reconnaissance before execution;
- tap/click-to-move;
- recording or authoring a plan;
- committing to the plan and watching it execute;
- deterministic guard patrols;
- visible fields of view;
- cameras, alarms, lasers and switches;
- doors, locks, safes and containers;
- tools with different speed/noise/damage tradeoffs;
- specialist characters with different skills;
- timed interactions;
- noise and evidence systems;
- guards later discovering changed world state;
- optional loot versus mission objectives;
- multi-character synchronization;
- remote switches and dependency chains;
- rescue, sabotage, theft and placement objectives;
- deterministic failure and retry loops;
- progressive teaching of mechanics through levels.

None of those general mechanics should be treated as proprietary content belonging to the original games.

---

## 2. What must not be copied

The European IP Helpdesk specifically lists videogame elements such as **source code, characters, buildings, maps, concept art, soundtrack, sound effects, script, dialogue and storyline** as examples of material that can be protected by copyright.

For this project, the following are prohibited unless explicit permission/license is obtained.

### Maps and level layouts

Do not recreate an original Der Clou! / The Sting! mission map room-for-room, corridor-for-corridor, floor-for-floor or obstacle-for-obstacle.

Do not take screenshots, walkthrough diagrams or extracted map data and rebuild the same layout with new textures.

It is acceptable to study why an original mission works and create a new puzzle using the same abstract principles.

Example:

**Allowed:**

`guard patrol + locked door + timed switch + safe objective`

implemented in a completely new building with a different geometry, route structure, timing and solution space.

**Not allowed as project policy:**

recreating the original Mausoleum, Museum, Bank, Ministry of Light or another original mission and merely changing names/materials.

### Characters

Do not use original characters, names, biographies, dialogue, visual identities or recognizable substitutes intended to represent those characters.

Create a new cast.

### Story and dialogue

Do not reproduce original mission text, plot events, conversations, jokes, briefing text or narrative structure in a substantially similar expressive form.

General concepts such as "a crew planning a robbery" are fine. Specific story expression is not.

### Graphics and audiovisual material

Do not reuse:

- original sprites;
- textures;
- models;
- animations;
- icons;
- UI graphics;
- concept art;
- music;
- sound effects;
- voice recordings;
- cinematics.

All production audiovisual assets must be independently created or properly licensed.

### User interface

Do not deliberately reproduce the original UI screen-for-screen or copy distinctive visual arrangements purely to make the new game look like The Sting!.

The planning/recording concept may be retained, but its iPhone interaction design and visual presentation must be our own.

### Source code

Do not copy source code from the original games into the proprietary commercial project.

For the first game, the COSP/Open SDL lineage is useful for historical and behavioral research, but it is GPLv2. Copying GPL-covered code into a closed proprietary codebase can create licensing obligations inconsistent with the current project model.

Research links are stored in `docs/SOURCES.md` and `docs/ORIGINAL_GAMES_RESEARCH.md`.

For *Der Clou! 2 / The Sting!* no legitimate public source-code release was located in the project's research pass as of 2026-08-16.

Agents must never download random "abandonware source" archives and assume they are lawful, authentic or safe to reuse.

---

## 3. Campaign-design rule

`docs/CAMPAIGN_PLAN.md` uses the 18 original The Sting! jobs as **research labels for design progression**.

That does **not** mean our final campaign should mirror those 18 missions one-to-one in recognizable form.

The intended use is:

1. study the mechanic introduced by an original mission;
2. extract the abstract puzzle primitive;
3. mix it with mechanics learned elsewhere;
4. design a new building and new objective;
5. use different patrol topology, security relationships, timings and solution paths;
6. give the mission an original setting, story and name.

The safest and strongest design approach is to **mix the grammar** rather than preserve a visible one-to-one correspondence.

Example extracted grammar:

```text
patrol timing
→ noise
→ evidence
→ specialist
→ alarm
→ camera
→ timed switch
→ remote dependency
→ multiple actors
→ chained security graph
```

This progression can inspire the campaign without reconstructing the original content.

### Internal research names versus production names

Labels such as:

- Gas Station
- Museum
- Bank
- Mausoleum
- Ministry of Light

may appear in research documentation to identify the historical reference source.

They are **not production mission names** unless they happen to be generic names independently selected and cleared; agents should assume they are research-only labels.

---

## 4. Trademark and game-title rules

Copyright is not the only issue. Names and branding can create **trademark** risk.

The USPTO explains that a mark can conflict with another mark when similarity in appearance, sound, meaning or commercial impression, combined with related goods/services, creates a likelihood that consumers will be confused about source or sponsorship.

Official references:

- USPTO TMEP §1207.01 — Likelihood of Confusion: https://tmep.uspto.gov/RDMS/TMEP/print?href=TMEP-1200d1e5044.html&version=current
- USPTO trademark search/help: https://tmsearch.uspto.gov/
- USPTO common application problems / conflicting marks: https://www.uspto.gov/trademarks/basics/common-problems

Therefore:

### Do not ship under these names

- Der Clou!
- The Clue!
- Der Clou! 2
- The Sting!
- Der Clou! 3
- The Sting! 2
- any title deliberately implying that this is an official sequel, remake or licensed continuation.

The internal GitHub repository name `DerClou` should not be treated as the commercial branding decision.

### Before finalizing the commercial title

Perform a trademark clearance pass covering at minimum:

- USPTO database;
- relevant EU/UK trademark databases if those markets are targeted;
- App Store search;
- general web/game marketplace search;
- same/similar names used for games, software and entertainment products.

A merely available App Store name is **not** proof that the trademark is safe.

---

## 5. Practical green / yellow / red zones

### GREEN — normal project work

Safe design territory when independently implemented:

- heist-planning genre;
- plan → commit → execute loop;
- deterministic patrols;
- cameras and cones;
- alarms and lasers;
- timed switches;
- dependency graphs;
- multiple playable specialists;
- noise and evidence;
- safes, doors and tools;
- tap-to-move;
- top-down / orthographic 3D presentation;
- short mobile missions;
- progressive mechanic teaching;
- generic crime/heist terminology;
- original levels using these primitives.

### YELLOW — requires deliberate review

Potentially safe, but agents must stop and evaluate similarity before proceeding:

- a mission whose layout was directly derived from an original screenshot/map;
- reproducing the same sequence of unusual puzzle events from one original mission;
- highly similar UI composition;
- intentionally matching an original character archetype plus appearance/backstory;
- marketing language such as "the spiritual sequel to The Sting!";
- using original screenshots in promotional material;
- importing GPL/COSP code even for a small subsystem;
- names intentionally designed to sound close to Der Clou!/The Sting!.

When in doubt, redesign rather than rationalize.

### RED — prohibited for this project without explicit rights

- copying original map geometry;
- original characters;
- original dialogue/story text;
- original artwork/models/textures/icons;
- original music/sounds;
- original game data;
- original source code;
- copying GPL code into proprietary production code without a deliberate licensing decision;
- marketing the game as official/authorized when it is not;
- using the original game's trademark as our title.

---

## 6. Rule for Claude, Codex and other coding/design agents

Before generating a level, story, UI, asset or mechanic based on research from the originals, apply this test:

### Step 1 — identify the abstraction

Write the mechanic in generic terms.

Example:

> Actor A must temporarily disable a security barrier so Actor B can cross during a deterministic timing window.

### Step 2 — discard the original expression

Do not retain the original:

- map;
- room arrangement;
- character identity;
- object placement;
- wording;
- names;
- timings;
- art;
- story context.

### Step 3 — independently redesign

Create:

- new geometry;
- new patrol topology;
- new timing values;
- new security graph;
- new objective context;
- new visual treatment;
- preferably more than one valid solution.

### Step 4 — similarity sanity check

Ask:

> If someone familiar with The Sting! saw this mission without being told about the reference, would they recognize it as a recreation of a specific original mission rather than merely a game in the same design tradition?

If the answer is plausibly yes, redesign it further.

---

## 7. Clean-room development preference

The project should prefer **behavioral research + independent implementation**.

Use manuals, walkthroughs and gameplay observations to understand:

- rules;
- state transitions;
- timing concepts;
- player affordances;
- mission progression;
- abstract systems.

Then write new Swift/RealityKit code from our own architecture and requirements.

Do not translate original source code line-by-line, mechanically port routines, or ask an agent to reproduce source from a disassembly/decompilation unless a future explicit legal/licensing decision changes this policy.

This also has an engineering benefit: the current project is architected for iOS 27, Swift, RealityKit and Reality Composer Pro 3, so a clean implementation is more appropriate than carrying forward decades-old architecture.

---

## 8. Documentation and provenance

Keep research separated from production assets and code.

Research material belongs in documentation such as:

- `docs/ORIGINAL_GAMES_RESEARCH.md`
- `docs/SOURCES.md`
- `docs/CAMPAIGN_PLAN.md`

Production code and assets should have independent provenance.

For third-party assets, retain license/source information where appropriate.

Do not commit downloaded copyrighted original game assets into this repository merely because they are available online.

---

## 9. Pre-release IP checklist

Before App Store submission, perform a final review:

- [ ] commercial title is original and trademark-cleared;
- [ ] App Store subtitle/keywords do not imply official affiliation;
- [ ] all characters and names are original;
- [ ] story/dialogue/briefings are original;
- [ ] all maps are independently designed;
- [ ] no original game screenshots/assets are in the shipping bundle;
- [ ] all 3D models/textures/audio have known provenance/licenses;
- [ ] no original or GPL-derived source has accidentally entered proprietary production code;
- [ ] UI has its own visual identity;
- [ ] campaign missions are not recognizable map-for-map remakes;
- [ ] marketing copy does not imply sponsorship, authorization or sequel status;
- [ ] final title/logo receives a dedicated trademark search;
- [ ] if the project has become substantially closer to the originals than described here, obtain professional IP counsel before release.

---

## 10. Risk statement

No document can guarantee that a third party will never send a complaint or file a lawsuit. Litigation can be initiated even when a defendant believes a claim is weak.

The purpose of this policy is to keep the project on the materially stronger side of the idea/expression boundary:

> **Take the gameplay grammar. Create the expression ourselves.**

That means our own title, maps, characters, story, code, art, audio, UI, timings and mission implementations.

If this rule remains intact, the project is intentionally designed as an independent work inspired by a genre/mechanical lineage rather than a copied work.
