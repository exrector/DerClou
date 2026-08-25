# ORIGINAL LEVEL CATALOG — reconstruction dossier

Status: **living research master document**. Rebuilt and expanded 2026-08-25.

Purpose: consolidate every publicly recoverable fact about the burglary targets / missions in **Der Clou! / The Clue! (1994)**, the **Profidiskette** expansion, and **Der Clou! 2 / The Sting! (2001)** so future level design can reconstruct the *functional puzzle structure* before deliberately redesigning it into original production content.

> **LEGAL / PRODUCTION RULE — DO NOT SKIP**
>
> This document is an internal historical reconstruction dossier, **not** permission to copy original maps, story, names, art, dialogue, exact patrol geometry or distinctive presentation into the commercial game. `docs/IP_AND_LEGAL_BOUNDARIES.md` remains mandatory. Production levels must independently redesign geometry, patrol topology, exact timings, object placement, security graph, story context, names and visual expression.

The required workflow is:

```text
historical reconstruction
        ↓
abstract mechanic / dependency graph
        ↓
new geometry + new timings + new fiction
        ↓
production level
```

Do not embed or redistribute copyrighted map images in production assets. Public blueprint links are useful research references; convert them into abstract facts, then redesign.

---

# 1. Confidence and source policy

- **CONFIRMED** — directly supported by a primary/near-primary source, structured preserved data reference, or multiple independent sources.
- **STRONG** — concrete high-quality walkthrough evidence; good enough for design research, but still re-measure exact simulation values before coding.
- **PARTIAL** — target is certain, but public text does not currently expose enough topology/security detail.
- **OPEN** — information must still be recovered from preserved data, original runtime or blueprint inspection.

When guides disagree on exact loot value, “best time” or route, this document prefers **topology, systems and causal relationships** over economy numbers. Differences are recorded rather than silently resolved.

---

# 2. Primary research sources

## The Clue! / Der Clou! (1994)

- Odino, detailed 2023 GameFAQs PC guide:  
  https://gamefaqs.gamespot.com/pc/583304-the-clue/faqs/80487
- whowasphone404, 2022 GameFAQs guide/walkthrough:  
  https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/introduction
- Easy jobs:  
  https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/easy-jobs
- Hard jobs:  
  https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/hard-jobs
- Nasty jobs:  
  https://gamefaqs.gamespot.com/amiga/937304-the-clue/faqs/80167/nasty-jobs
- Impossible jobs:  
  https://gamefaqs.gamespot.com/pc/583304-the-clue/faqs/80167/impossible-jobs
- Planning system:  
  https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/planning-a-robbery
- Security / police investigation:  
  https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/secruity-systems-and-police-investigations
- Map/chart index:  
  https://gamefaqs.gamespot.com/pc/583304-the-clue/faqs
- MobyGames:  
  https://www.mobygames.com/game/2568/the-clue/
- COSP / preserved game-data lineage:  
  https://sourceforge.net/projects/cosp/

GameFAQs separately hosts research maps for at least: Aunt Emma Shop, Chiswick House, Ham House, Jeweller's, Kenwood House, Natural Museum, Old Curiosity Shop, Old People's Home, Osterly Park House, Pink Villa and Suterby's. These are not embedded here.

## Profidiskette (1995)

- MobyGames expansion description:  
  https://www.mobygames.com/game/57184/der-clou-profidiskette/
- Preserved German base + Profidisk data:  
  https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/Der%20Clou%21%20%2B%20Profidisk%20%28German%29/
- Preserved Profidisk data package:  
  https://sourceforge.net/projects/cosp/files/DerClouProfiData.zip/download
- COSP discussion identifying separate Profidisk databases (`DATA/OBJPROFI/BUILDING.PC`, `OBJECTS.PC`, `TCDATA.H`):  
  https://sourceforge.net/p/cosp/discussion/25891/thread/db7965ff/
- Preserved game-logic example for Westminster Abbey vehicle constraint:  
  https://sourceforge.net/p/cosp/discussion/25891/thread/a0a818eb/

## Der Clou! 2 / The Sting! (2001)

- Kasey Chang complete 18-job guide/walkthrough:  
  https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/14674
- Preserved mirror:  
  https://www.justadventure.com/walkthrough/the-sting-cheats/
- Walkthrough page 2:  
  https://www.justadventure.com/walkthrough/the-sting-cheats/2/
- Modern independent Any% walkthrough:  
  https://www.speedrun.com/The_Sting/guides/abw4o
- Exact 18-level list:  
  https://www.speedrun.com/The_Sting/levels
- Official German manual:  
  https://www.ds.thqnordic.com/support/Clou2_Handbuch.pdf
- English manual:  
  https://www.gamewholesale.com/downloads/Sting_Manual.pdf

---

# 3. Coverage summary

## The Clue! / Der Clou! base game

The first game is nonlinear: after the introductory robbery the player can choose among available targets; story gates mainly care about the **number** of completed burglaries rather than a fixed mission order. The two detailed modern guides together support a catalog of **18 selectable burglary targets**, plus the scripted **Starford Barracks** final operation.

The 18 selectable targets are:

1. Fulham Newsagents / Kiosk
2. Aunt Emma's Shop
3. Old People's Home
4. Pink Villa
5. Old Curiosity Shop
6. Highgate Cemetery / Karl Marx' Tomb
7. Jeweller's
8. Chiswick House
9. Suterby's
10. Ham House
11. Osterly / Osterley Park House
12. Natural History Museum / Natural Museum
13. Kenwood House
14. Victoria & Albert Museum
15. Bank of England
16. National Gallery
17. British Museum
18. Tower of London

Story finale: **Starford Barracks**.

A mid-story “Jaguar + suitcase” event is **not a unique fixed target map**. The walkthrough states the event can be satisfied by doing a different burglary as long as the required Jaguar is used, so treat it as a campaign/loadout constraint rather than another level.

## Profidiskette

MobyGames confirms **8 new locations**. Four are explicitly named there: **Buckingham Palace, Madame Tussaud's, a valuables train/Post Train and 221B Baker Street**. COSP source/game-logic material independently proves **Westminster Abbey** is also a Profidisk building. Three remaining names found in preservation/community material are recorded below as **PARTIAL** until the actual Profidisk database is decoded.

## The Sting!

The Kasey Chang guide and Speedrun.com independently agree on exactly **18 jobs**:

Gas Station; Grocers; Cinema; Hotel; Greenhouse; Boxing Club; Printing Office; Undertaker; Mausoleum; Spam Factory; Villa; neo Office; Museum; Bank; Barracks; Harbour; Power Plant; Ministry of Light.

---

# 4. Shared first-game reconstruction model

A first-game target is not just a room plan. Reconstruct at least four layers:

```text
SPACE
rooms / doors / windows / stairs / valuables

TIME
police patrol / guard route / check-clock deadline / action duration

SYSTEMS
alarms / switchboxes / microphones / searchlights / locks

EVIDENCE
opened or damaged objects / fights / tool traces / witnesses
```

Before planning, the player cases a building. Around 50% knowledge is enough to target it; deeper investigation reveals more objects, security relations and guard routes. Guards follow regular patrols and may have to service Check Clocks. Noise has a per-building threshold. Alarms, switchboxes, microphones and searchlights can be linked. The post-burglary investigation also cares about traces and suspicious world states.

This is important for our game: the historical design already treats the building as a **time-dependent state graph**, not as a static maze.

---

# PART I — DER CLOU! / THE CLUE! (1994)

## C1. Fulham Newsagents / Kiosk

**Confidence:** STRONG  
**Role:** canonical tutorial/first robbery.

**Known target data:** police response about **10:00**; estimated valuables about **£380**; no internal guard; low overall guard/security rating; maximum noise around **78** in the odino data.

**Topology:** tiny shop/kiosk footprint with the getaway vehicle immediately outside. Important nodes are the entry/window, cash register and a few optional small valuables. Spatial complexity is deliberately minimal.

**Actors/security:** one predictable external police/cop patrol. The decisive rule is acoustic: crowbar work on the window/register is safe only when the patrol is far enough away.

**Objective:** cash register. Walkthroughs also mention optional low-value objects such as a fire extinguisher and toilet paper.

**Canonical solution skeleton:** wait for patrol window → breach → enter → wait again if needed → force register → take cash → exit → car.

**Why the puzzle works:** first demonstration that *when* an action happens is part of the route.

**Production abstraction:** one tiny shop, one external listener patrol, one noisy breach and one objective. Completely redesign the map/facade.

---

## C2. Aunt Emma's Shop

**Confidence:** STRONG

**Known target data:** police response about **11:40**; no professional guard; low security; maximum noise about **47**. Exact loot totals differ between guides/versions, so do not treat one currency total as canonical.

**Topology:** compact retail interior with several ordinary fixtures/containers (refrigerator/cupboards/showcase-style nodes). A public GameFAQs map exists.

**Security:** low formal security but noticeably lower noise tolerance than Kiosk. It teaches that “no guard” does not imply “loud tools are free.”

**Loot:** distributed low-value retail goods/cash rather than one protected vault.

**Puzzle identity:** quietness/tool choice without guard-management complexity.

**Production abstraction:** small retail level whose correct choice is a slower/quieter entry route.

---

## C3. Old People's Home — Maida Vale

**Confidence:** STRONG

**Known target data:** police response about **10:00**; values around **£1,000**; city escape; guard/security roughly **7%**; no professional guard; max noise about **39**. Public GameFAQs map exists.

**Topology:** multiple interior rooms rather than one shop cell; guide routes use distinct staging and loot areas.

**Actor hazard:** memorable threat is a resident/civilian rather than a conventional guard. The inhabitant's deterministic movement creates a practical deadline/window.

**Security/timing:** extremely low noise allowance plus occupant timing. Public material also associates the target with timing/check-clock-style security information; exact device placement should be verified from map/data before implementing.

**Why it works:** broadens “security actor” to ordinary occupant/world routine.

**Production abstraction:** residential/institutional building with a deterministic civilian cycle and safe side rooms.

---

## C4. Pink Villa — Limehouse

**Confidence:** STRONG

**Known target data:** police response **11:40**; estimated values about **£430**; city escape; very low guard rating; no internal guard; max noise about **86**. Public map exists.

**Topology:** domestic/villa layout with several rooms and wall-mounted/small valuables.

**Security:** little direct electronic/human security. This is a route/loot-selection target rather than a systems graph.

**Design lesson:** guide advice makes some optional loot inefficient because extra doors/time are not justified by value.

**Production abstraction:** small house that teaches `objective success ≠ loot everything`.

---

## C5. Old Curiosity Shop — Kensington Church Street

**Confidence:** STRONG

**Known target data:** police response **14:40**; values about **£900**; city escape; guard/security **35%**; no guard; max noise **66**; **Alarm System Z3**. Public map exists.

**Topology:** compact antique/curiosity shop with many inspectable/value nodes.

**Security/progression:** the building can become available before the player is well equipped to defeat its alarm. Guide progression later recommends an alarm/electronics-capable accomplice.

**Loot examples:** cash, curiosities, a bronze statue, book/autograph-type valuables.

**Why it works:** capability gating without locking the location itself.

**Production abstraction:** show a solvable-looking target early; later tools/skills make it meaningfully practical.

---

## C6. Highgate Cemetery / Karl Marx' Tomb

**Confidence:** STRONG

**Known target data:** police response **6:40**; values around **£1,000**; country-road escape; security **27%**; guard skill about **15%**; max noise **78**.

**Topology:** outdoor cemetery/tomb rather than room network. Vault/tomb contains the special objective.

**Guard:** one watchman patrol. Successful published routes use concealment/staging, a fighting-capable accomplice and a second actor moving to the tomb after the guard is neutralized or safely bypassed.

**Objective:** Karl-Marx-related remains/bones have special story/fence value beyond ordinary loot price.

**Crew/vehicle interaction:** taking a fighter/driver and fitting the team into the getaway vehicle makes preparation part of the mission.

**Puzzle identity:** outdoor patrol + two-actor synchronization + special-objective economy.

**Production abstraction:** outdoor memorial/garden location where actor A creates a temporary safe window for actor B.

---

## C7. Jeweller's — Oxford Street

**Confidence:** STRONG

**Known target data:** police response **15:00**; values about **£3,000**; inner-city escape; security **39%**; no guard; max noise **58**; **Alarm System Z3**. Public map exists.

**Topology:** compact high-value shop centered around a high-security safe and protected showcases.

**Security/progression:** no human guard, but alarm + container difficulty gate the best loot. Guide progression explicitly notes that the safe is not practical until better tools become available.

**Evidence/state:** guide advice emphasizes closing doors because outside patrols may inspect the area while the crew spends time on the safe.

**Loot categories:** gold, cash, jewels, watch, painting.

**Puzzle identity:** long-duration safe work under external inspection risk.

**Production abstraction:** jewelry shop where the hard part is time spent stationary on the objective, not locomotion.

---

## C8. Chiswick House — Turnham Green

**Confidence:** STRONG

**Known target data:** police response **14:20**; values about **£16,000**; motorway escape; security **54%**; radio 0; guard skill around **47%**; max noise **82**; **Alarm System Z3**; **Check Clock about 30 seconds** in odino's data. Public map exists.

**Topology:** historic-house/gallery-like target with multiple protected display cases/art objects.

**Temporal system:** the check clock is the defining design fact. A guard/security routine must satisfy a repeated time obligation; blocking or delaying the route can expose the burglary even without immediate visual detection.

**Why it works:** introduces a periodic “security heartbeat” independent of line of sight.

**Production abstraction:** one guard whose patrol is not merely cosmetic: it must touch a checkpoint on schedule.

---

## C9. Suterby's — Bond Street

**Confidence:** STRONG

**Known target data:** police response **4:00**; values about **£8,000**; city escape; security **82%**; guard skill around **35%**; max noise **70**; **Alarm System Z3**. Public map exists.

**Topology:** high-security auction/valuable interior with a steel-door choke point and broad loot pool.

**Critical persistent state:** guide material explicitly warns that the **steel door must be closed after entering**, otherwise a patrol can detect the abnormal state.

**Loot:** paintings, cash, jewels, statues, curiosities, silverware, historical art, coin collection.

**Why it works:** traversal itself changes world state; the plan must include restoration.

**Production abstraction:** monitored choke door where “open and pass” is incomplete — the door must return to a plausible state before inspection.

---

## C10. Ham House — Richmond

**Confidence:** STRONG

**Known target data:** police response **13:20**; values about **£34,000**; country-road escape; security **62%**; guard skill about **31%**; max noise **94**; **Alarm Z3 + Alarm X3 + Check Clock about 640 seconds**. Public map exists.

**Topology:** larger historic property with multiple security zones and enough scale for route ordering to matter.

**Security:** two alarm types plus long-period check-clock obligation. This is not “one alarm protects one thing”; several state machines overlap across a long operation.

**Puzzle identity:** early security-stack level.

**Production abstraction:** estate with two independent alarm networks plus a slow periodic guard/system heartbeat.

---

## C11. Osterly / Osterley Park House — Isleworth

**Confidence:** STRONG

**Known data:** one guide reports patrol ~**23 min**, loot ~**£20,700**, police response ~**11:40**, noise **90**, security **70**, guard skill **39**. Odino's valuation is higher (~£25,000), so economy values are version/guide-sensitive. Public map exists.

**Security:** defining perimeter mechanic is a **microphone-protected entry**. A loud tool can trigger the site before the crew meaningfully enters. Interior layers include **Alarm Z3 + Alarm X3**, searchlight/control logic and a guard.

**Crew/tool logic:** guide solutions expect quiet drilling/entry plus fighter/electronics coverage.

**Why it works:** the tool/noise decision is evaluated at the first boundary, then the target escalates into layered human/electronic security.

**Production abstraction:** acoustic perimeter sensor → quiet breach → internal multi-system puzzle.

---

## C12. Natural History Museum / Natural Museum — Cromwell Road

**Confidence:** STRONG

**Known target data:** police response **3:40**; values about **£34,000**; inner-city escape; security **66%**; radio about **7%**; guard skill about **19%**; max noise **66**; **Alarm Z3 + protected switchbox/searchlights**. Public map exists.

**Topology:** museum/display space with multiple showcases and a security-control node.

**Security hierarchy:** switchbox/searchlight relation means the device that alters visibility is itself part of the protected graph.

**Why it works:** hierarchical security rather than independent hazards.

**Production abstraction:** exhibition space where control-room access changes the visibility layer but the controller is itself dangerous to reach/use.

---

## C13. Kenwood House — Hampstead Lane

**Confidence:** STRONG

**Known target data:** police response **16:40**; values about **£50,000**; motorway escape; security **74%**; radio 0; guard skill about **50%**; max noise **94**; **Alarm X3 + Alarm Z3 + protected switchbox/searchlights**. Public map exists.

**Topology:** large historic-house target with distributed valuable objects.

**Security:** mature first-game layered stack: human guard + two alarm types + controller + searchlights.

**Why it works:** scale and layered protection force route ordering and crew-role planning.

**Production abstraction:** large estate where disabling one subsystem changes the feasibility of another route.

---

## C14. Victoria & Albert Museum

**Confidence:** STRONG

**Known guide data:** patrol ~**17 min**; loot ~**£59,900**; police response **5:00**; noise **58**; security about **80**; radio **11**; guard skill **54**.

**Topology:** museum with initial control/security node, guarded transition/back room, searchlight exposure and later loot area.

**Security sequence:** published strategy disables an early control box, waits for a guard cycle, crosses into a searchlight-risk area, then neutralizes further control/alarm nodes before looting.

**Crew:** driver + fighter + electrician profile; physical entry, electrical tools and guard-neutralization capability.

**Puzzle identity:** security layers are solved in order; correct ordering temporarily converts a dangerous gallery into a loot zone.

**Production abstraction:** perimeter controller → guarded transition → internal alarm/controller → objective zone.

---

## C15. Bank of England

**Confidence:** STRONG

**Known guide data:** patrol ~**13 min**; total loot ~**£430,000**; police response **2:00**; noise **62**; security **86**; radio **27**; guard skill **90**.

**Critical timing:** **two check clocks**, roughly **250 s** and **280 s**. This creates overlapping temporal obligations rather than one countdown.

**Human security:** initial guards are extremely difficult in the original and guide results can be probabilistic. Our deterministic design should not copy that randomness literally.

**Topology/security:** multi-stage bank/vault structure with guarded and electronic barriers and extremely little alarm-response slack.

**Why it works:** dual periodic obligations + high-value objective + tiny response window force real crew synchronization.

**Production abstraction:** deterministic bank puzzle with two independent security heartbeats and a staged vault chain.

---

## C16. National Gallery

**Confidence:** STRONG

**Known guide data:** patrol **20 min**; loot about **£167,100**; police response **3:00**; noise **62**; security about **76**; radio **11**; guard skill **66**; **Check Clock about 500 s**.

**Topology:** large protected-art target with multiple entry/room choices and central transitions.

**Security:** guards plus alarm/electrical/searchlight-control vocabulary. Exact per-door microphone/controller relationships should be confirmed against the original map/data before coding.

**Puzzle identity:** several route choices funnel into a shared timed security obligation.

**Production abstraction:** large gallery with alternative ingress but one global periodic security deadline.

---

## C17. British Museum

**Confidence:** STRONG

**Known guide data:** patrol ~**18 min**; loot ~**£85,780**; police response **3:00**; noise **62**; security about **78**; radio **11**; guard skill **82**; guide “good time” around **10:30**; **Check Clock about 320 s**.

**Topology:** guarded museum entry followed by internal areas where exact patrol timing/hiding matters.

**Security:** a seemingly easy physical entry is dominated by a very dangerous guard and periodic check-clock requirement.

**Why it works:** entry geometry says “open”, temporal security says “not yet”.

**Production abstraction:** visually accessible entry controlled by one high-value patrol plus medium-period checkpoint timer.

---

## C18. Tower of London

**Confidence:** STRONG

**Role:** Crown Jewels story job / first-game systems capstone.

**Known guide data:** patrol about **1:30**; loot value around **£850,000**; police response **2:00**; noise **58**; security ~**90**; radio ~**47**; guard skill ~**98**; guide “good time” ~**14:40**; **Check Clock about 380 s**.

**Topology:** fortified multi-stage target with searchlights, alarms and several crew/security dependencies around the Crown Jewels.

**Narrative state:** the broader story proceeds into betrayal/capture consequences around this job; “perfect stealth success” is not the only narrative outcome.

**Puzzle identity:** culmination of crew composition, periodic timing, alarms, lights, guards, tools and extraction.

**Production abstraction:** late-game fortress/vault where several parallel tasks converge on one final objective window.

---

## C-FINAL. Starford Barracks

**Confidence:** STRONG

**Role:** scripted final operation after the Tower storyline; structurally different from ordinary selectable robberies.

**Key mechanic:** three accomplices already have authored routes/behavior. The player primarily adds Matt's route around those schedules. This is an **asymmetric synchronization puzzle**, not blank-slate plan authoring.

**Topology:** multi-floor military/barracks complex with doors, stairs, control boxes, alarms, secured areas and gate searchlights.

**Dependency skeleton:** teammate opens access → Matt disables control node → radio coordination advances teammate → upper-floor security/control work → safe-related teammate task → final alarms/doors → gate/searchlight state.

**Narrative/mechanical twist:** desired resolution requires the accomplices to be exposed/caught by gate searchlights while Matt escapes separately. Detection of one actor therefore cannot be modeled as unconditional global mission failure.

**Engine lesson:** mission success must support actor-specific outcome predicates and asymmetric extraction.

**Production abstraction:** mission with pre-scripted allied schedules that the player's plan must interlock with.

---

# PART II — PROFIDISKETTE (1995)

## What is definitely known

MobyGames describes Profidiskette as an add-on adding **8 new locations**, more cars and specialists, plus planning improvements. COSP preserves separate Profidisk game data and explicitly references:

```text
DATA/OBJPROFI/BUILDING.PC
DATA/OBJPROFI/OBJECTS.PC
DATA/OBJPROFI/TCDATA.H
```

Public walkthrough prose is much thinner than for the base game. **Missing topology is intentionally marked OPEN rather than invented.**

## P1. 221B Baker Street

**Confidence:** CONFIRMED location; PARTIAL mechanics

MobyGames explicitly names 221B Baker Street. German community/walkthrough material treats it as a sensible early Profidisk target and associates it with a Sherlock-Holmes-themed objective, commonly described as an opium pipe.

**Likely progression role:** approachable expansion re-entry rather than a late security fortress.

**Open:** exact floorplan, guards, alarm graph, response/noise values and object coordinates must be extracted from Profidisk data/runtime.

**Production abstraction:** compact themed residence/office with one iconic objective.

---

## P2. Buckingham Palace

**Confidence:** CONFIRMED location; OPEN detailed mechanics

MobyGames explicitly names Buckingham Palace. COSP changelog independently records a fixed crash when **visiting Buckingham Palace**, confirming the preserved engine/data recognizes it.

**Likely role:** high-profile/high-security landmark target.

**Open:** exact map, guard routes, alarms, valuables, timing and entrances. Use Profidisk data/runtime, not the real palace plan.

**Production abstraction:** ceremonial/high-profile compound; completely original geometry.

---

## P3. Madame Tussaud's / Wax Museum

**Confidence:** CONFIRMED location; OPEN detailed mechanics

MobyGames explicitly names the wax museum.

**Design interest:** exhibit rooms naturally support dense sightline clutter, display-value inspection and security-control routing.

**Open:** exact original topology, security and loot.

**Production abstraction:** exhibition attraction with display obstacles and security hierarchy.

---

## P4. Post Train / valuables train (`Postzug`)

**Confidence:** CONFIRMED concept/location; PARTIAL mechanics

MobyGames explicitly states the expansion contains a **train carrying valuables**. German community material calls it `Postzug`.

**Topology identity:** intrinsically linear/segmented vehicle layout with compartment choke points, unlike a normal building.

**Community evidence:** recollections suggest strong payout and relatively simple guard setup, but this is not authoritative enough to encode as fact until runtime/data verification.

**Engine/design lesson:** burglary target need not be a static rectangular building.

**Production abstraction:** linear vehicle heist with compartment sequencing and constrained bypass routes.

---

## P5. Westminster Abbey

**Confidence:** CONFIRMED target identity from preserved game logic; OPEN topology

COSP discussion reproduces planning validation that checks `Building_Westminster_Abbey` and requires the selected vehicle to be one of two **Fiat 634 N** variants (1936/1943).

**Important mechanic:** getaway vehicle is a **hard mission prerequisite**, not merely an escape stat.

**Open:** exact building map/security and in-fiction reason for the vehicle requirement.

**Production abstraction:** target with a hard preparation/loadout constraint that changes planning before the map opens.

---

## P6. Downing Street

**Confidence:** PARTIAL identity; OPEN mechanics

The name appears in Profidisk preservation/community/asset references, but the high-authority prose sources recovered in this pass do not enumerate all eight targets.

**Do not treat as fully verified until `OBJPROFI/BUILDING.PC` is decoded.**

**Production abstraction if confirmed:** government-office target with compartmentalized access/security.

---

## P7. Tate Gallery

**Confidence:** PARTIAL identity; OPEN mechanics

Recovered as part of Profidisk preservation/community asset references, but not among the four examples explicitly named by MobyGames.

**Open:** confirm target ID/name and all security/topology from Profidisk data.

**Production abstraction if confirmed:** gallery target extending display/security-control vocabulary.

---

## P8. Chemical Factory / Chemiefabrik

**Confidence:** PARTIAL identity; OPEN mechanics

Associated with Profidisk preservation/community asset references but not yet confirmed by a primary prose list in this research pass.

**Open:** confirm identity and all map/security facts from `OBJPROFI` database/runtime.

**Production abstraction if confirmed:** industrial topology with controlled/hazardous zones rather than museum/house geometry.

---

## Mandatory Profidisk follow-up

To bring P1–P8 to the quality of the base-game entries:

1. unpack preserved `DerClouProfiData.zip`;
2. decode/enumerate `DATA/OBJPROFI/BUILDING.PC`, `OBJECTS.PC`, `TCDATA.H`;
3. recover all eight building IDs/names;
4. recover target stats, object/security relations and guard routes where encoded;
5. run each target in COSP/original DOS build to verify topology;
6. record differences between standard and Profidisk databases;
7. replace every PARTIAL/OPEN statement above with sourced facts.

This is currently the **largest hole** in the historical level archive.

---

# PART III — DER CLOU! 2 / THE STING! (2001): ALL 18 JOBS

The complete Kasey Chang walkthrough is unusually useful because it describes working plans for every job. Speedrun.com independently confirms the exact 18-level set and supplies alternative routes, which proves several maps support multiple valid solutions. The summaries below extract topology/security grammar, not walkthrough prose.

## S1. Gas Station

**Confidence:** STRONG

**Topology:** compact gas-station exterior + shop, breachable window, upstairs/restroom area and nearby getaway car.

**Security:** one cop/guard patrol. Noise from window/register work is the central hazard.

**Objective:** cash register; optional low-value items exist.

**Plan skeleton:** wait until patrol is outside hearing window → breach → approach register → if needed wait through another cycle → force/take → exit.

**Puzzle identity:** one moving listener + known noisy actions.

**Production abstraction:** deterministic noise timing tutorial.

---

## S2. Grocers / Grocery Store

**Confidence:** STRONG

**Topology:** storefront with left-window entry, lower retail area and upper/intermediate floor used as staging/hiding space.

**NPC:** old woman/granny runs a predictable cycle. The player must cross her route more than once.

**Objective:** cash register plus another cash stash/stocking in common walkthrough routes.

**Puzzle identity:** same patrol cycle must be respected inbound and outbound; upstairs zone becomes a safe waiting pocket.

**Production abstraction:** patrol cycle + safe room + repeated crossing.

---

## S3. Cinema

**Confidence:** STRONG

**Topology:** exterior perimeter, alternate entrance near/behind hotdog stand, stairs to upper/projection area, hiding corner/room and outside patrol route.

**Security:** indoor and outdoor patrol timing overlap. Alternate/quiet entry is superior to obvious destructive route.

**Objective:** film reel in projection-related room.

**Plan skeleton:** alternate ingress → start/finish lock work around guard cycle → hide → take reel → exit same side → avoid exterior patrol → car.

**Puzzle identity:** alternate entry + two patrol domains + hiding + door/evidence considerations.

---

## S4. Hotel

**Confidence:** STRONG

**Topology:** multi-floor hotel with front-window/kitchen alternatives, stairs and bedroom/safe/loot rooms.

**Security:** guard/resident cycles across floors. Safe-oriented solution requires long/noisy safe work while the guard is far away. Modern speed route demonstrates a different strategy: bedroom valuables timed around a resident cycle.

**Crew:** safecracker specialist materially changes one solution family.

**Puzzle identity:** long action duration + vertical patrol phase + optional objective strategy.

**Production abstraction:** multi-floor target where loot choice changes which timing window matters.

---

## S5. Greenhouse / Arboretum

**Confidence:** STRONG

**Topology:** exterior/side-window approach, office/corridor/greenhouse spaces and vertical/stair transition.

**NPC:** technician cycles predictably between objective area and another station/office.

**Objective:** cashbox plus special plant/asparagus-like mission item in walkthrough material.

**Key mechanic:** theft can be discovered **later**, when the technician returns to the changed world state.

**Crew:** fast accomplice useful for exploiting the just-departed window.

**Puzzle identity:** delayed discovery + future deadline.

**Production abstraction:** deterministic returning NPC; player has a known escape deadline after changing an inspected object.

---

## S6. Boxing Club

**Confidence:** STRONG

**Progression role:** first explicit electronics/alarm job.

**Topology:** club/locker/shower spaces plus upstairs protected area; side/shower room can stage/hide an actor.

**Security:** alarm bypass uses electronics/soldering capability. Upstairs NPC later inspects a door; wrong door/lock state can expose the burglary after the crew has moved away.

**Objective:** boxing-glove mission item plus optional valuables.

**Puzzle identity:** electronics specialist + delayed inspection + state restoration.

**Production abstraction:** alarmed access where “leave door as found” is part of correctness.

---

## S7. Printing Office

**Confidence:** STRONG

**Topology:** multi-floor printing/office target with alternate/rear access, protected rooms, patrols, safe and alarm work.

**Objective:** two heavy printing plates/templates, around **35 kg each** in the guide.

**Crew:** multiple specialists: locks, safe cracking, electronics/alarm and carrying capacity.

**Evidence mechanic:** guide explicitly notes upstairs patrol checks **damaged locks**, not simply current locked/unlocked state.

**Puzzle identity:** crew composition + parallel tasks + carrying + damage evidence.

**Production abstraction:** heavy mission objects force assignment of the correct carrier while specialists solve separate access nodes.

---

## S8. Undertaker / Funeral Home

**Confidence:** STRONG

**Topology:** obvious front route is inferior; exterior stairs/skybridge-like connection reaches alternate upper entry. Multi-floor interior includes safe/drawer/casket-related loot.

**Security:** patrol moves between floors. After safe/drawer work, closing/restoring the container allows the documented plan to survive a later patrol inspection.

**Objective:** “Cremation of Elvis”/bible-like special item; optional watch/paintings.

**Crew:** safecracker + second actor; useful parallel staging near exit.

**Puzzle identity:** alternate vertical ingress + scene restoration + patrol inspection.

---

## S9. Mausoleum

**Confidence:** STRONG

**Topology:** entrance → B1 security area → deeper B2/corridor/stair route around a laser/trip beam.

**Security graph:** two alarms are **cross-wired** and the guide explicitly warns against attacking them directly. A separate switch controls the trip beam.

**Synchronization:** actor A stays at the switch while actor B approaches/crosses the remote barrier.

**Phase change:** some guards appear only **after objective pickup**, so the escape is a different security state from ingress.

**Puzzle identity:** timed remote switch + cross-linked security + post-objective state transition.

**Production abstraction:** two actors control each other's accessibility; objective triggers phase 2.

---

## S10. Spam Factory

**Confidence:** STRONG

**Topology:** industrial/main building plus smaller office/side building across a compound/yard; operationally separate zones.

**Security dependency:** one actor reaches a lever/control in one area that changes alarm/security access for another area.

**Objective:** certificates/valuable documents in a safe in common guide routes.

**Crew:** safe/lock capability plus remote-security assistance.

**Puzzle identity:** split areas + remote disable + separate patrol clocks.

**Production abstraction:** area A control → area B specialist objective → rendezvous/extraction.

---

## S11. Villa

**Confidence:** STRONG

**Story objective:** **Check Card**.

**Topology:** large house with side-window entry, several floors, garden/exterior guard, internal guard, balcony/roof connection and objective desk room.

**Security:** camera-protected direct routes can be bypassed by topology; internal guard can be followed. Balcony/roof route creates a timed cross-building shortcut.

**Loot:** many optional valuables, but Check Card is the mission-critical object.

**Puzzle identity:** mandatory objective vs greed + alternate vertical/roof route + topology-based camera bypass.

**Production abstraction:** primary objective is simple; optional profit meaningfully changes risk/extraction timing.

---

## S12. neo Office

**Confidence:** STRONG

**Topology:** large corporate office with back/roof/window approaches, multiple internal security zones, safes and laser barriers.

**Crew:** large/multi-role team recommended; lock, safe, electronics and carrying tasks can be split.

**Security:** contemporary guide calls attention to **cause and effect**. Switches, alarms and lasers form dependencies; one actor changes another's route. Rooftop/window routes can bypass some camera exposure.

**Objective/loot:** several neo documents/valuable objects; fuller routes include multiple/heavy targets.

**Puzzle identity:** first true security dependency graph rather than isolated devices.

**Production abstraction:** directed graph whose solution must preserve a reversible extraction path.

---

## S13. Museum

**Confidence:** STRONG

**Topology:** multi-floor museum with displays, patrol zones, control/security areas and multiple team objectives.

**Security hierarchy:** switches/levers disable cameras/lasers; control areas gate protected exhibits. Guards inspect paintings/objects, creating delayed evidence detection.

**Objective:** guide material references a shrunken-head-style mission target plus value/loot requirements; optional paintings create carrying optimization.

**Crew:** multiple actors; locks, electronics/alarm and carrying all matter.

**Puzzle identity:** local device → control area → protected system → exhibit, combined with inspection patrols.

**Production abstraction:** multi-stage museum where optional exhibit greed consumes time/capacity.

---

## S14. Bank

**Confidence:** STRONG

**Topology:** large bank with asymmetric access, stairs, laser/alarm zones, basement/vault stages, steel doors and several control points.

**Crew:** split team; lock, electronics/soldering and safe work distributed among actors; carrying matters for bullion.

**Security graph:** switches/levers open barriers for another actor; steel/vault doors form staged dependencies. Guide routes often use different ingress/egress logic rather than simply reversing the route.

**Objective:** diamond and gold bullion in modern speed route; fuller walkthrough emphasizes multiple safes/vault stages.

**Puzzle identity:** large split-team vault heist.

**Production abstraction:** remote controls + staged vault + asymmetric exit.

---

## S15. Barracks

**Confidence:** STRONG

**Objective type:** **rescue**, not loot.

**Topology:** military compound/building with separated crew paths, guardhouse/restricted area and remote control points.

**Crew/state:** Daisy is story-selected. Teams begin/operate in separate areas.

**Security dependency:** two remote switches/levers must be coordinated in tight windows, more than once. After release, extraction becomes escort/synchronization rather than looting.

**Engine lesson:** success conditions must support `rescue actor + extract`, not only `take object`.

**Production abstraction:** remote switch pair → rescue state change → escort extraction.

---

## S16. Harbour

**Confidence:** STRONG

**Objective:** **Red and Blue power prisms**.

**Topology:** harbour containing ship, tavern/club/office and warehouse/hangar areas. Crew operates across physically distinct structures.

**Dependency chain:** ship desk/key → harbour office/alarmed room → remote lever → temporary hangar/camera/security state → safe alarms → safes → prisms → remote exit window.

**Crew:** lock/key acquisition, electronics/alarm, safe cracking and carrying roles. One guide route repeatedly has Tucker operate a remote lever while another actor advances through the hangar.

**Puzzle identity:** one of the clearest dependency chains in the sequel.

```text
obtain key
→ unlock control room
→ operate remote switch
→ create security window
→ specialist enters
→ disable safe alarms
→ crack two safes
→ take two mission items
→ create exit window
```

**Production abstraction:** long but legible directed security graph across separate buildings.

---

## S17. Power Plant

**Confidence:** STRONG

**Objective type:** **placement/sabotage**, not theft. The two prisms from Harbour are placed on two machines; the plant stops when the objective state is reached.

**Topology:** industrial compound with several guard routines, towers/alternate entrances, internal plant floor and staged barriers/camera coverage.

**Crew:** speed emphasized; one actor can carry both prisms while others manipulate access/security.

**Security:** front door is not preferred; not every camera must be directly disabled. Alternate topology and timing matter.

**Engine lesson:** same planning primitives support `place item at target` mission verbs.

**Production abstraction:** staged multi-team sabotage + item placement + extraction.

---

## S18. Ministry of Light

**Confidence:** STRONG

**Role:** final integrated puzzle.

**Crew/state:** Daisy and Sinclair are story-selected; Sinclair begins imprisoned and cannot be normally equipped. Tucker/Daisy need electronics/soldering capability; lockpicks are not central in documented solutions.

**Topology:** multiple starting sides, front/back approaches, corridors, stairs/platforms, guarded rooms, prison/release area and multiple laser-controlled transitions.

**Security:** guards, cameras, lasers and repeated remote switches. Tucker's progress opens Daisy's path; Daisy later opens Tucker's path; freeing Sinclair adds an actor needed for the final dependency.

**Relay structure:** 

```text
Tucker advances
→ switch helps Daisy
→ Daisy advances
→ switch helps Tucker
→ team frees Sinclair
→ Sinclair + others satisfy final switch dependency
→ final access opens
```

**Puzzle identity:** finale recombines learned primitives rather than inventing arbitrary new rules.

**Production abstraction:** multi-start, multi-actor dependency relay with rescue embedded in the security graph.

---

# 5. Cross-game mechanic matrix

| Primitive | Early clear example | Advanced example |
|---|---|---|
| Noise window | Clue Kiosk / Sting Gas Station | Osterly microphone entry |
| Deterministic patrol | Kiosk / Grocers | Museum / Ministry |
| Safe waiting pocket | Grocers | Ministry guard-following/corners |
| Long interaction duration | Jeweller's safe | Hotel / Bank vault |
| World-state restoration | Suterby's steel door | Boxing Club / Undertaker |
| Delayed discovery | Old People's Home | Greenhouse / Museum inspections |
| Check-clock heartbeat | Chiswick | Bank of England dual clocks |
| Electronics/alarm specialist | Old Curiosity Shop | neo Office / Bank |
| Searchlight/controller graph | Natural Museum | Tower / late museums |
| Remote switch | Mausoleum | Harbour / Ministry |
| Cross-linked security | Mausoleum | neo Office |
| Carrying capacity | Printing Office | Bank / Museum |
| Key dependency | — | Harbour |
| Alternate vertical route | Cinema / Hotel | Undertaker / Villa |
| Split buildings | — | Spam Factory / Harbour |
| Rescue objective | — | Barracks / Ministry |
| Placement/sabotage objective | — | Power Plant |
| Pre-scripted ally schedule | Starford Barracks | reusable future primitive |
| Actor-specific success outcome | Starford Barracks | future narrative missions |
| Vehicle/loadout gate | Westminster Abbey | reusable campaign-prep primitive |

---

# 6. Reconstruction data still worth extracting

## 6.1 First-game blueprint pass

For every public GameFAQs map, transcribe research facts — **not the image** — into an abstract graph:

```text
area / room nodes
connections
windows / doors
stairs
loot clusters
guard/check-clock nodes
alarm/switch/searchlight relations
entry/extraction nodes
```

## 6.2 First-game/COSP data pass

The surviving first-game source/data lineage can potentially reveal:

- building IDs;
- target statistics;
- guard routes;
- object categories;
- security connections;
- edition differences.

COSP GPL code remains research-only unless a separate licensing decision is made. Reimplement behavior independently.

## 6.3 Profidisk database pass — highest-priority historical gap

Decode:

```text
DATA/OBJPROFI/BUILDING.PC
DATA/OBJPROFI/OBJECTS.PC
DATA/OBJPROFI/TCDATA.H
```

Goals:

- prove all eight target names;
- recover target stats;
- recover security/object graph;
- recover patrol paths if encoded;
- verify map topology in runtime;
- replace PARTIAL/OPEN Profidisk entries with sourced facts.

## 6.4 The Sting! visual/runtime graph pass

The walkthrough provides strong causal routes, but each sequel mission can still be normalized into a machine-readable research graph:

```text
areas
vertical transitions
entry/extraction
patrol loops
security devices
switch targets
objective nodes
phase changes
```

That graph is the useful part to compare across missions; exact decorative geometry is not.

---

# 7. Mandatory format for future additions

Whenever a new source reveals more about an original target, update the entry using this schema:

```text
Game / edition:
Target name:
Source confidence:
Progression role:

ENVIRONMENT / TOPOLOGY
- areas / floors
- entry candidates
- exit candidates
- choke points
- alternate routes

ACTORS
- guards / civilians
- patrol topology
- inspections
- state changes

SECURITY GRAPH
- alarms
- cameras / searchlights
- lasers / microphones
- switches / control boxes
- check-clock / timed dependencies

OBJECTIVES
- mandatory state/object
- optional loot
- carrying constraints

TIME
- action durations
- patrol windows
- delayed discovery
- security heartbeats
- police/alarm response

TOOLS / CREW
- required capabilities
- meaningful alternatives

FAILURE / EVIDENCE
- immediate failure
- delayed failure
- state that must be restored

DESIGN EXTRACTION
- why the original puzzle works
- abstract primitive(s) worth preserving

PRODUCTION REDESIGN
- geometry that must change
- patrol topology that must change
- timings that must change
- fiction/names/art that must change

OPEN QUESTIONS
- facts still unverified

SOURCES
- URL + exactly what it supports
```

---

# 8. Agent rule for using this catalog

When asked to create a mission inspired by one of these targets, **do not translate the original map cell-for-cell**. First write an abstraction.

Example:

```text
RESEARCH FACT
Mausoleum:
actor A controls a remote timed barrier for actor B;
objective pickup changes guard state;
return route is different.

ABSTRACTION
remote timed gate + two actors + phase change after objective.

NEW LEVEL
new fiction + new geometry + new route topology + new timings
+ different device placement + different objective + original art.
```

The point of reconstructing the originals in detail is to preserve **why the puzzles work**, not their copyrighted expression.

---

# 9. Current research conclusion

The archive is now strong for:

- the **18 selectable base-game targets** plus **Starford Barracks**;
- the exact **18 The Sting! jobs** and their main route/security grammar;
- Profidisk's existence as an **8-location** expansion and at least five strongly evidenced target identities.

The major remaining gap is **Profidisk exact topology/data**. The preserved data is online, so the correct next step is direct data/runtime extraction rather than further guessing from community prose.
