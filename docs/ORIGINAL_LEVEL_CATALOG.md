# ORIGINAL LEVEL CATALOG — reconstruction dossier

Status: **living research document**. First assembled 2026-08-25.

Purpose: collect every recoverable fact about the burglary targets / missions in the original **Der Clou! / The Clue! (1994)**, the **Profidiskette** expansion, and **Der Clou! 2 / The Sting! (2001)** in one place, so future level design can reproduce the *functional puzzle structure* before deliberately redesigning it into original production content.

This is **not permission to copy original maps, story, names, art, dialogue, exact patrol geometry or distinctive presentation into the commercial game**. `docs/IP_AND_LEGAL_BOUNDARIES.md` remains mandatory. The intended workflow is:

1. reconstruct the original level accurately enough to understand it;
2. extract the abstract puzzle grammar;
3. redesign geometry, patrol topology, timing, security graph, objective context, names and visual expression independently;
4. keep the original reconstruction only as an internal research reference.

---

# 1. Source hierarchy and confidence

## A — primary / near-primary

- Preserved original game data packages via COSP / SourceForge:
  - https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/
  - German base + Profidisk:
    https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/Der%20Clou%21%20%2B%20Profidisk%20%28German%29/
  - English base + Profidisk:
    https://sourceforge.net/projects/cosp/files/Original%20Game%20Files/The%20Clue%21%20%2B%20Profidisk%20%28English%29/
- Official Der Clou! 2 German manual:
  https://www.ds.thqnordic.com/support/Clou2_Handbuch.pdf
- English The Sting! manual:
  https://www.gamewholesale.com/downloads/Sting_Manual.pdf

## B — high-value walkthrough / technical reconstruction sources

- The Clue! 1994 detailed GameFAQs guide by odino:
  https://gamefaqs.gamespot.com/pc/583304-the-clue/faqs/80487
  - unusually valuable because individual buildings include police response, total value, escape route, guard/security percentages, maximum noise, alarm types, blueprint links and loot lists;
  - some later entries are incomplete/TODO in the guide, so missing facts must not be invented.
- The Clue! walkthrough / guide 80167:
  https://gamefaqs.gamespot.com/cd32/961705-the-clue/faqs/80167/introduction
- The Sting! complete 18-job walkthrough by Kasey Chang:
  https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/14674
- Secondary The Sting! mirror:
  https://www.mogelpower.de/cheats/loesung.php?id=38954
- Secondary incomplete The Sting! guide:
  https://gamefaqs.gamespot.com/pc/519682-the-sting/faqs/29111

## C — metadata / corroboration

- MobyGames The Clue!:
  https://www.mobygames.com/game/2568/the-clue/
- MobyGames Profidiskette:
  https://www.mobygames.com/game/57184/der-clou-profidiskette/
- MobyGames The Sting!:
  https://www.mobygames.com/game/4295/the-sting/
- Profidisk contemporary-review index / discussion:
  https://www.kultboy.com/testbericht-uebersicht/7292/
- 2026 playthrough articles with observed first-game behavior:
  https://advgamer.blogspot.com/2026/02/game-167-clue-1994-introduction.html
  https://advgamer.blogspot.com/2026/03/the-clue-das-kapital.html

## Confidence labels

- **CONFIRMED** — directly stated in primary/manual/walkthrough source or preserved game data.
- **STRONG** — independently corroborated or sufficiently specific in a high-quality walkthrough.
- **PARTIAL** — target is confirmed, but exact topology/security/timing is incomplete.
- **UNKNOWN** — do not infer; requires original data extraction, blueprint capture or playthrough.

---

# 2. Reconstruction template

Every target should eventually have the following fields:

```text
Game / edition
Target name
Confidence
Difficulty / progression position
Exterior / entry topology
Interior topology / floors
Entry points
Exit / extraction
Mandatory objective
Optional loot
Guards / civilians
Patrol topology
Vision / inspection behavior
Alarm systems
Microphones / noise limits
Searchlights / cameras / lasers / switches
Doors / windows / locks
Tools / skills required
Crew constraints
Timing constraints
Persistent world-state / evidence
Police response / escape route (first game)
Special mechanic
Canonical solution skeleton
What makes the puzzle interesting
Production abstraction to preserve
Exact facts still missing
Sources
```

---

# 3. Der Clou! / The Clue! (1994) — base game targets

The first game is **not a simple linear list of missions**. Targets become available as the campaign advances and the player can choose among them. The heist layer is therefore best treated as a catalog of target buildings, plus story-specific jobs.

## 3.1 Kiosk

**Confidence:** STRONG.

**Role in progression:** introductory burglary / simplest practical target.

**Topology:** very small single-target commercial structure; minimal traversal compared with later buildings.

**Security:** effectively the tutorial baseline: no sophisticated electronic dependency graph; the challenge is primarily learning planning, tools, entry and extraction.

**Objective / loot:** basic cash / small valuables. The detailed guide notes that the payout is poor relative to later targets.

**Design function:** teaches the complete macro-loop with almost no systemic noise: investigate → choose crew/vehicle/tools → record route/actions → execute → escape.

**Reconstruction requirements:** capture exact blueprint, all containers and exact entry interaction from the archived blueprint/game data before treating geometry as known.

**Production abstraction:** one tiny target, one obvious objective, one exit, no advanced security. Excellent template for a first playable planning tutorial.

**Source:** GameFAQs 80487; MobyGames screenshots; 80167 walkthrough.

---

## 3.2 Aunt Emma's Shop

**Confidence:** STRONG.

**Role:** early alternative to the Kiosk with more work and roughly more loot.

**Topology:** small shop interior; multiple loot containers compared with the Kiosk.

**Security / gameplay:** still early-game physical-entry logic rather than advanced electronic security. Main purpose is to introduce a slightly more involved route and inventory/loot choice without yet requiring a specialist-heavy plan.

**Loot categories observed in source:** cash, delicatessen, a frozen lobster, articles for daily use.

**Production abstraction:** same core system as the Kiosk, but with several loot nodes so route ordering and greed begin to matter.

**Source:** GameFAQs 80487; 2026 Adventurers' Guild playthrough.

---

## 3.3 Old People's Home — Maida Vale

**Confidence:** STRONG.

**Confirmed metrics from GameFAQs 80487:**

- police response distance/time: **10:00**;
- nominal values: **1000**;
- escape route: **city**;
- degree of guard: **7%**;
- radio communication: **0%**;
- guards: **0%**;
- maximum noise level: **39%**.

**Special mechanic:** a **check clock** is explicitly important; the guide recommends postponing the job until the player has the necessary capability/tool.

**Topology:** multi-object interior, but exact room graph should be recovered from the preserved blueprint rather than recreated from memory.

**Difficulty lesson:** even with no conventional guard, a target can be constrained by a non-human security/inspection mechanic and a low noise allowance.

**Production abstraction:** introduce a passive security system before adding patrol AI. The player must understand that “no guard” does not mean “no timing/security constraint.”

**Source:** GameFAQs 80487 blueprint entry and target statistics.

---

## 3.4 Pink Villa — Limehouse

**Confidence:** STRONG.

**Confirmed metrics:**

- police response: **11:40**;
- values: **430**;
- escape route: **city**;
- degree of guard: **3%**;
- radio communication: **0%**;
- guards: **0%**;
- maximum noise: **86%**.

**Topology:** residential/villa layout with multiple valuables and at least one extra door protecting low-value loot.

**Loot examples from the guide:** valuables case and paintings.

**Puzzle shape:** optional loot is explicitly not always worth the route/time cost. The guide recommends skipping low-value objects that require additional traversal.

**Production abstraction:** teach that the shortest safe solution may intentionally leave loot behind; greed is a route-planning decision, not a mandatory checklist.

**Source:** GameFAQs 80487.

---

## 3.5 Old Curiosity Shop

**Confidence:** STRONG / topology PARTIAL.

**Progression:** becomes available very early and is recommended as a better early target than the Old People's Home once suitable tools/specialists are available.

**Security:** alarm work matters; the walkthrough specifically recommends bringing an accomplice capable of disabling alarms.

**Loot categories:** cash, Oscar Wilde autograph, curiosities, bronze statue, Sanskrit book.

**Puzzle shape:** richer interior and specialized loot introduce two ideas: electronic/security specialist choice and fencing/value differences after the heist.

**Production abstraction:** first compact level where “who comes with you” materially changes whether the plan is practical.

**Source:** GameFAQs 80487 / 80167.

---

## 3.6 Karl Marx' Tomb — Highgate Cemetery

**Confidence:** CONFIRMED / STRONG.

**Objective:** steal **Karl Marx' bones** for a story-linked buyer; the source records the bones at about 3.2 kg and a special sale value in the plot.

**Exterior topology:** cemetery gate → outdoor concealment positions (bush/tree) → guard route → tomb → return to vehicle.

**Guard:** one watchman patrols the cemetery. A 2026 playthrough records a concrete successful timing skeleton:

1. protagonist breaks the cemetery gate and waits near cover;
2. accomplice enters later and hides;
3. accomplice approaches the guard from behind and fights/neutralizes him around the third minute;
4. protagonist passes the downed guard, opens the tomb and takes the bones;
5. both return to the car.

The exact quoted timestamps from that playthrough are useful research observations, but should be re-measured directly from the original game before being treated as canonical simulation data.

**Crew constraint:** because the guard must be neutralized, an accomplice with fighting ability is needed; vehicle seat count can indirectly constrain crew choice.

**Special mechanic:** first strong example of a mission where crew composition, vehicle capacity, patrol timing and physical access all intersect.

**Production abstraction:** outdoor patrol + two-actor synchronization + one actor creates a safe window while another performs the objective.

**Sources:** GameFAQs 80487 / 80167; Adventurers' Guild “Das Kapital” playthrough.

---

## 3.7 Jeweller's

**Confidence:** STRONG / topology PARTIAL.

**Progression:** high-value early/mid target. The guide explicitly notes that the safe cannot initially be opened until better tools become available.

**Guarding:** one source recommendation says the Jeweller can be attractive because it has **no guard** at a point where other newly available buildings do.

**Loot categories:** paintings, gold, cash, Cartier watch, jewels.

**Security / constraint:** safe/tool gating is the central progression lock; the target may be known before the player owns the technology to exploit it fully.

**Production abstraction:** show the player a tempting objective before they can efficiently solve it, encouraging later return with improved tools/crew.

**Source:** GameFAQs 80487.

---

## 3.8 Chiswick House

**Confidence:** PARTIAL.

**Confirmed:** named base-game target; detailed blueprint exists in the GameFAQs reconstruction set, but the current textual source coverage available to this document is incomplete.

**What must be extracted before implementation:** exact floor count, room graph, access points, patrol count, electronic protection, loot-node placement, noise threshold, police response, escape route.

**Do not infer topology from the real historical Chiswick House.** The game map is the authority.

**Source:** GameFAQs 80487 / blueprint set.

---

## 3.9 Suterby's

**Confidence:** STRONG / topology PARTIAL.

**Loot categories documented:** paintings, cash, jewels, statues, curiosities, silver tableware, historical art, coin collection.

**Puzzle implication:** unusually broad and valuable loot pool; weight/volume and fencing become meaningful optimization dimensions even before considering security.

**Missing:** exact patrol/security topology must be recovered from the blueprint/game data.

**Production abstraction:** optional-loot optimization level where the target contains far more value than the crew can safely or efficiently remove.

**Source:** GameFAQs 80487.

---

## 3.10 Ham House

**Confidence:** PARTIAL.

The odino guide confirms the target but leaves its detailed loot section as **TODO**. Treat this as a known hole rather than filling it from assumptions.

**Required reconstruction work:** original game-data inspection or direct playthrough capture for blueprint, security, patrols, loot and response metrics.

**Source:** GameFAQs 80487; preserved game data.

---

## 3.11 Osterly / Osterley Park House — Isleworth

**Confidence:** STRONG.

**Confirmed metrics:**

- police response: **11:40**;
- values: **25000**;
- escape route: **motorway**;
- degree of guard: **70%**;
- radio communication: **0%**;
- guards: **39%**;
- maximum noise: **90%**.

**Confirmed security:**

- **Microphone**;
- **Alarm System Z3**;
- **Alarm System X3**.

**Loot:** numerous paintings and additional high-value objects.

**Puzzle shape:** major escalation from small shops: multiple security channels operate simultaneously. High nominal noise allowance does not make the target simple because microphones, alarms and patrol/security density create layered constraints.

**Production abstraction:** first “systems stack” target where the player must reason about several independent detection technologies, not just a single patrol.

**Source:** GameFAQs 80487.

---

## 3.12 Natural Museum

**Confidence:** PARTIAL.

Confirmed base-game target. Detailed section in the currently available guide is incomplete/TODO.

**Required extraction:** map topology, display cases, protection types, guard routes, exact objective/loot, police and noise parameters.

**Production abstraction candidate:** museum/display-space security hierarchy, but do not freeze this until the original data is examined.

**Source:** GameFAQs 80487; preserved game data.

---

## 3.13 Kenwood House — Hampstead Lane

**Confidence:** STRONG.

**Confirmed metrics:**

- police response: **16:40**;
- values: **50000**;
- escape route: **motorway**;
- degree of guard: **74%**;
- radio communication: **0%**;
- guards: **50%**;
- maximum noise: **94%**.

**Confirmed security:**

- **Alarm System X3**;
- **Alarm System Z3**;
- **Switchbox**;
- **Searchlights**, protected.

**Loot examples:** cash box, multiple statues and paintings.

**Puzzle shape:** mature first-game target combining guards, multiple alarm types, a control/switch relationship and searchlight visibility.

**Production abstraction:** late-campaign compound security puzzle: disable/control a subsystem to alter another threat while preserving enough time for extraction.

**Source:** GameFAQs 80487.

---

## 3.14 Additional / late base-game targets

**Status: UNKNOWN / requires complete data extraction.**

The public guide and screenshots establish that more advanced/famous targets appear as the campaign progresses. The current research pass has not yet produced a sufficiently reliable complete textual list with full reconstruction data for every late-game building. Before declaring the base-game catalog complete, parse the preserved game data and/or capture the target list from a full playthrough.

**Rule:** do not silently treat the 13 entries above as the complete base-game count.

---

# 4. Profidiskette expansion (1995)

## 4.1 What is confirmed

**Confidence:** CONFIRMED.

Profidiskette adds **8 new locations/heists**, plus more vehicles and specialists and planning-phase improvements. It does not extend the main story.

MobyGames explicitly names four examples:

1. **Buckingham Palace**;
2. **Madame Tussaud's wax museum**;
3. **a train carrying valuables** (commonly referred to in German discussion as the **Postzug** / valuables train);
4. **221B Baker Street**.

Source:
https://www.mobygames.com/game/57184/der-clou-profidiskette/

A contemporary-review discussion independently confirms that the **Postzug** is available from the start of the expansion content and describes it as comparatively easy with one guard and very high payoff; treat the exact payout figure mentioned by a commenter as anecdotal until verified in-game.

Source:
https://www.kultboy.com/testbericht-uebersicht/7292/

## 4.2 Profidisk target P1 — Buckingham Palace

**Confidence:** target CONFIRMED; topology UNKNOWN.

**Research significance:** palace-scale security target likely intended as one of the expansion's advanced puzzles.

**Do not substitute the real Buckingham Palace floor plan.** Exact game topology, guards, alarm systems, loot and access points must be extracted from Profidisk game data.

---

## 4.3 Profidisk target P2 — Madame Tussaud's

**Confidence:** target CONFIRMED; topology UNKNOWN.

**Research significance:** museum/display-style target with potential object-inspection and security-layer design value.

**Required:** extract original blueprint and device list before deriving mechanics.

---

## 4.4 Profidisk target P3 — valuables train / Postzug

**Confidence:** STRONG for target and broad difficulty note; topology PARTIAL.

**Known:** moving/rail-themed valuables target; community discussion describes only **one guard** and disproportionately large reward compared with difficulty.

**Research value:** unusual non-building heist topology; excellent reference for a compact linear level and for future train/convoy missions.

**Required:** exact carriage graph, entry/extraction rules, guard patrol, containers and timing from original data/playthrough.

---

## 4.5 Profidisk target P4 — 221B Baker Street

**Confidence:** target CONFIRMED; topology UNKNOWN.

**Research value:** compact iconic-location burglary; exact game layout must be recovered rather than inferred from Sherlock Holmes fiction or real-world London.

---

## 4.6 Profidisk targets P5–P8

**Confidence:** UNKNOWN.

The expansion definitely contains eight locations, but the current reliable public text sources found during this pass name only the four above. Search results that merely speculate about Westminster Abbey, Downing Street, Tate Gallery, chemical factories, etc. are **not sufficient evidence** and are therefore deliberately excluded from the canonical list.

**Next required action:** inspect the preserved Profidisk data archive and extract the actual building identifiers / strings / blueprints. Until then P5–P8 remain explicit unknowns.

---

# 5. Der Clou! 2 / The Sting! (2001) — all 18 jobs

The sequel is much better documented than the first game. The Kasey Chang guide contains a complete walkthrough for all 18 jobs. The entries below are reconstruction briefs: enough to reproduce each puzzle's functional structure, while exact geometry should still be independently redrawn from screenshots/playthrough if an internal research replica is required.

## 5.1 Gas Station

**Role:** first real heist tutorial.

**Topology:** compact service-station/commercial target with a short route from entry to money/loot and back to the getaway point.

**Opposition:** one predictable patrol creates basic timing windows.

**Mechanics:** basic entry, noise, waiting, simple loot interaction, extraction.

**Canonical puzzle skeleton:** observe patrol → enter after patrol clears → perform short objective interaction → leave before patrol returns → reach vehicle.

**Production abstraction:** one guard, one objective, one exit, one timing lesson.

---

## 5.2 Grocery Store

**Topology:** multiple rooms plus vertical/floor movement in the original job.

**Opposition:** predictable civilian/patrol cycle.

**Mechanics:** hiding in rooms, moving behind a deterministic cycle, optional valuables, return traversal through the same building.

**Puzzle skeleton:** use safe rooms as temporal buffers; ascent/descent means the patrol phase on the way out differs from the way in.

**Production abstraction:** deterministic inhabitant movement + hiding spaces + repeated traversal of the same choke point.

---

## 5.3 Cinema

**Topology:** main/alternate entry routes, internal hiding room/restroom, interaction between exterior and interior patrol space.

**Mechanics:** alternate entrance, lockpicking, hiding, guard inspection of access points.

**Important rule:** destructive or visibly changed entry can become dangerous later because a guard may inspect it.

**Puzzle skeleton:** choose clean alternate entry → hide during patrol overlap → avoid leaving an inspectable door/window state that reveals the burglary → exit cleanly.

**Production abstraction:** persistent evidence changes which tool is “best.”

---

## 5.4 Hotel

**Topology:** multi-floor target; guard movement crosses floors.

**Crew:** safe-cracking specialist is important.

**Mechanics:** long-duration/noisy safe work, vertical patrol timing, optional loot.

**Puzzle skeleton:** identify a sufficiently long patrol absence → begin safe work only inside that window → resist optional loot if it destroys extraction timing.

**Production abstraction:** long action duration + noise + vertical patrol clock.

---

## 5.5 Greenhouse / Arboretum

**Topology:** alternate entry and objective area visited on a deterministic NPC routine.

**Crew:** faster accomplice / role timing matters.

**Mechanics:** delayed discovery of a missing object; alternate route; first meaningful coordination.

**Puzzle skeleton:** act just after technician/NPC leaves → acquire objective → escape before the NPC returns and discovers the changed world state.

**Production abstraction:** a theft can create a future deadline rather than immediate detection.

---

## 5.6 Boxing Club

**Role:** first explicit alarm-work job in the walkthrough.

**Mechanics:** electronic/alarm bypass, specialist/tool requirement, safe/slow versus fast/risky approach, guard inspection of changed door state.

**Puzzle skeleton:** security specialist disables/bypasses alarm → another route/action occurs → restore or preserve correct state before inspector returns.

**Production abstraction:** physical access and security access are distinct layers.

---

## 5.7 Printing Office

**Crew:** multiple accomplices and specialist roles.

**Mechanics:** carrying capacity, safe cracking, alarm work, lockpicking, hiding idle crew, parallel tasks.

**Puzzle skeleton:** distribute specialists to independent tasks → hide actors who are not currently moving → overlap actions to save shared mission time → extract in a safe order.

**Production abstraction:** first true crew-composition puzzle.

---

## 5.8 Undertaker / Funeral Home

**Topology:** alternate elevated/bridge-like route and multiple floors.

**Mechanics:** safe interaction, restoration/closing behavior, patrol inspection, parallel crew actions.

**Puzzle skeleton:** one actor performs objective while another manages access/restoration → ensure opened/changed containers are returned to a safe state before later inspection.

**Production abstraction:** “restore the scene” becomes a reusable puzzle primitive.

---

## 5.9 Mausoleum

**Security:** walkthrough explicitly discusses cross-wired alarms and a switch controlling a trip beam.

**Mechanics:** remote control, timed access, cross-linked security, synchronized actors.

**Puzzle skeleton:** actor A reaches/holds or triggers remote control → temporary beam/alarm window opens → actor B crosses and reaches second dependency → return path must also be solved.

**Production abstraction:** timed switch + remote dependency + two-way synchronization.

---

## 5.10 Spam Factory

**Topology:** split actors across physically separate buildings/areas.

**Mechanics:** remote security assistance, specialist safe/objective work, multiple NPC route clocks.

**Puzzle skeleton:** actor A disables security in B's area → B advances and performs specialist objective → teams later rendezvous/extract while two patrol schedules remain compatible.

**Production abstraction:** geographically separated teams coupled by security state.

---

## 5.11 The Villa

**Topology:** multiple viable approaches including an alternate high/roof route that can bypass cameras.

**Mechanics:** mandatory objective vs large optional loot pool; solo/crew choice; risk/reward greed.

**Puzzle skeleton:** select route based on camera coverage and crew; complete mandatory objective; decide whether optional valuables are worth the later extraction risk.

**Production abstraction:** clean completion and maximum profit should be different optimization goals.

---

## 5.12 Neo Office

**Role:** major cause-and-effect security graph puzzle.

**Security:** multiple alarms, safes, layered laser barriers, switches controlling access for other team members.

**Crew:** large team / specialists.

**Puzzle skeleton:** solve dependency ordering rather than merely route around cones: control A changes barrier B, allowing actor C to reach control D, which changes another actor's path.

**Production abstraction:** security graph must be inspectable and reversible enough that extraction remains possible.

---

## 5.13 Museum

**Topology:** multiple floors and objective/display areas.

**Security:** switches disabling cameras; security/control-room hierarchy.

**Opposition:** guards inspect paintings/objects, not merely walk routes.

**Mechanics:** multiple team objectives, carrying limits, optional-loot optimization.

**Puzzle skeleton:** disable/route around camera layer → coordinate team across floors → account for guards who will later inspect altered displays → choose loot within capacity/time budget.

**Production abstraction:** hierarchy of security systems plus evidence inspection.

---

## 5.14 Bank

**Role:** large capstone-style conventional heist.

**Topology:** asymmetric front/back routes; multi-stage interior/vault progression; different entry and exit may be preferable.

**Security:** lasers, alarms, multiple protected stages.

**Crew:** multiple specialized roles; split teams.

**Mechanics:** carrying capacity can affect mission completion, not only bonus score.

**Puzzle skeleton:** divide crew by route/function → solve security stages in order → access safes/vault → allocate carrying responsibility → extract through safest remaining route.

**Production abstraction:** broad, open-ended multi-role heist before special narrative mission types.

---

## 5.15 Barracks

**Objective:** rescue rather than theft.

**Topology:** separated teams / controlled passages.

**Mechanics:** preselected rescue character, two remote switches, strict timing window, escort extraction.

**Puzzle skeleton:** two teams coordinate remote access → reach/free rescue target → escort target through now-open dependency chain → extract everyone in correct order.

**Production abstraction:** same engine primitives support rescue without inventing a separate gameplay mode.

---

## 5.16 Harbor

**Mechanics:** mission-specific key acquisition; ship/club/warehouse dependency chain; alarm and safe specialists; runner/carrier roles.

**Canonical dependency skeleton:**

```text
obtain key
→ unlock secure room
→ operate remote switch
→ disable warehouse security
→ specialist opens protected container/safe
→ take mission object
→ coordinated extraction
```

**Production abstraction:** explicit key → room → switch → security → objective chain.

---

## 5.17 Power Plant

**Objective:** placement/sabotage-style mission rather than ordinary theft.

**Topology:** several guarded zones / staged barriers; multiple teams.

**Mechanics:** one team's action creates access for another; tight deterministic timing dominates.

**Puzzle skeleton:** teams progress in relay through staged barriers → objective item is placed/used at target → dependencies are reopened or preserved for extraction.

**Production abstraction:** mission verbs can change while navigation/security/planning systems stay identical.

---

## 5.18 Ministry of Light

**Role:** final integrated puzzle.

**Topology:** multiple starting positions and interdependent routes.

**Security/opposition:** cameras, lasers, guards, hiding/following, remote switches.

**Objective structure:** includes freeing/rescuing another actor and repeated cross-team dependencies.

**Puzzle skeleton:** actor A advances and unlocks B's route → B reaches another control that changes A's route → characters repeatedly alternate progress through guards/security → final group objective/extraction.

**Production abstraction:** finale combines established primitives rather than introducing arbitrary new rules.

---

# 6. Coverage matrix

| Set | Known count | Detailed enough for design abstraction | Exact geometry recovered | Status |
|---|---:|---:|---:|---|
| The Clue! base game | not yet fully verified | 13 documented targets + story observations | partial; blueprint links exist for many | **INCOMPLETE — must parse original data** |
| Profidiskette | 8 confirmed | 4 publicly named, broad details for train | no | **INCOMPLETE — data extraction required** |
| The Sting! | 18 | all 18 | not yet reconstructed room-by-room | **COMPLETE at mechanic level; geometry pass remains** |

---

# 7. Required next research passes

## Pass A — first-game data extraction

From preserved COSP/original game packages, extract:

- canonical target/building string table;
- complete base-game target count;
- all Profidisk P1–P8 names;
- building/map identifiers;
- object/loot placement data if encoded separately;
- alarm/security type identifiers;
- guard/patrol schedules if recoverable;
- police response/noise/security parameters;
- any blueprint/map assets that can be viewed internally as research reference.

**Output:** replace every `UNKNOWN` above with measured data.

## Pass B — blueprint capture

For each first-game/Profidisk target:

- preserve an internal map screenshot or redraw a neutral research schematic;
- label rooms/nodes rather than copying production art;
- mark all entrances, protected doors/windows, devices, guard route nodes and objective containers.

## Pass C — The Sting! geometry pass

For each of the 18 sequel jobs, capture:

- number of floors / separated buildings;
- room adjacency graph;
- actor starting positions;
- guard route nodes and wait/inspection nodes;
- security-device positions and dependency edges;
- objective and extraction positions;
- significant action/timing windows.

The complete walkthrough gives solution order, but a room-by-room map reconstruction still requires screenshots/video or direct play.

## Pass D — production conversion

For every reconstructed original target create a sibling **originalized design brief**:

```text
Original research target: [internal only]
Abstract mechanic: [...]
New setting: [...]
New geometry: [...]
New patrol topology: [...]
New timings: [...]
New security graph: [...]
New objective/story: [...]
What was deliberately changed to avoid map cloning: [...]
```

---

# 8. Rules for agents using this catalog

1. **Never invent missing original facts.** Mark them UNKNOWN and research them.
2. **Never copy an original map directly into production.** Reconstructing it internally for research is not the same as shipping it.
3. The useful unit is the **puzzle grammar**, not the room coordinates.
4. Preserve deterministic cause/effect: patrols, inspections, timers and security dependencies should remain explainable.
5. When a source conflicts with another source, record both and prefer game data/direct measurement over a prose walkthrough.
6. Keep exact source URLs beside every future addition so a later agent can audit it.
7. The Swift/RealityKit and Unity implementations are irrelevant to historical truth; this document describes **game-design evidence**, not engine architecture.
8. Any later discovery from original data should update this file rather than living only in a chat or coding-agent transcript.

---

# 9. Immediate practical conclusion

For implementation work today, **The Sting!'s 18 jobs are already sufficiently understood to drive the mechanic roadmap**, while the **first game + Profidisk still require a dedicated data/blueprint extraction pass** before anyone should claim that every original target can be reconstructed exactly.

The next research priority is therefore not another general web summary. It is:

```text
preserved original data
→ enumerate every target
→ extract every map/security record
→ capture neutral research schematics
→ fill the UNKNOWN fields in this catalog
```
