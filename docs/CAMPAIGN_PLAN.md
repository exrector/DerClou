# Campaign plan — 18 original design references × 10 mobile missions

Status: **master campaign structure / design plan**

Source basis: `docs/ORIGINAL_GAMES_RESEARCH.md`, especially the extracted design grammar of all 18 jobs in *Der Clou! 2 / The Sting!*.

## Core decision

The mobile campaign should **not reproduce the original 18 maps**. Instead, each original job is treated as a **chapter-level design reference**. Its central puzzle grammar is decomposed into **10 short, original mobile missions**.

That produces a long-form campaign of up to **180 missions** while keeping each individual mission compact and readable on iPhone.

The original mission names below are internal research labels only. Production chapter names, locations, layouts, characters, story, art and exact puzzle solutions must be original.

## Mobile mission format

Target for ordinary missions:

- one compact building or one clearly bounded part of a larger building;
- full-screen tactical view;
- tap floor / room to move;
- tap object to approach and interact;
- constant base walking speed;
- deterministic guards and security;
- approximately 1–3 minutes of execution once a plan is understood;
- approximately 3–7 minutes including observation, planning and one or two retries;
- one main idea per early mission;
- later missions combine previously learned ideas;
- mission 10 of each chapter is a **capstone** using the whole chapter grammar.

The campaign must avoid tutorial popups where possible. Teach through level structure and clear failure causes.

## Standard 10-mission chapter rhythm

Each chapter generally follows this pattern:

1. **Isolate** the new primitive.
2. **Repeat** it with a different geometry.
3. Add **timing**.
4. Add a **route choice**.
5. Add a **world-state / evidence** consequence.
6. Combine with one previously learned primitive.
7. Add another actor / device / patrol where appropriate.
8. Introduce a meaningful **risk/reward** or alternative solution.
9. Tight integration / rehearsal.
10. **Capstone:** original map and story, but structurally inspired by the original Der Clou! 2 job.

---

# Chapter 1 — research reference: Gas Station

Chapter purpose: teach the absolute core — movement, one patrol, one objective, one exit, basic timing and noise.

### 1.1 First Step
One room, one corridor, no guard. Walk to a cash box, take the objective, return to extraction.

### 1.2 Closed Door
Add one ordinary door between entry and objective. Teach contextual approach/open behavior.

### 1.3 Eyes Forward
Introduce one stationary guard with a visible field of view. Cross only when safe.

### 1.4 The Loop
Guard now walks a short fixed patrol. Player learns that patrol timing is deterministic.

### 1.5 Wait for It
Objective interaction takes several seconds. Player must wait for a sufficiently long patrol window.

### 1.6 Quiet Entry
Introduce a locked door and a quiet lockpick action.

### 1.7 Loud and Fast
Offer a faster destructive entry method that creates noise. Teach noise as a separate detection channel.

### 1.8 One More Drawer
Add optional loot outside the safest route. Teach that greed changes risk without changing the primary objective.

### 1.9 Round Trip
Entry and extraction are at the same point; patrol timing must work in both directions.

### 1.10 Corner Shop — Capstone
Compact shop with one exterior/one interior patrol path, locked back door, cash objective, optional loot and a clean extraction window. This is the chapter exam.

---

# Chapter 2 — research reference: Grocery Store

Chapter purpose: hiding, deterministic civilian movement, multiple rooms, vertical separation and repeated traversal.

### 2.1 Out of Sight
Introduce a small side room that breaks line of sight. Wait inside while a patrol passes.

### 2.2 Passing Traffic
A civilian follows a fixed cycle through two rooms. The player must move behind the cycle rather than simply avoid one cone.

### 2.3 Two Rooms Ahead
Objective lies beyond two sequential observation zones. Teach staged movement between safe rooms.

### 2.4 Upstairs
Introduce stairs / floor transition in a tiny two-level map.

### 2.5 Coming Back Down
The same staircase is used on return, but the patrol phase is different when leaving.

### 2.6 Shopping List
Several loot objects are available; only one is mandatory.

### 2.7 Occupied Room
A safe room is periodically entered by an NPC. Hiding is no longer permanently safe.

### 2.8 Cross Traffic
Two deterministic NPC cycles overlap at one corridor intersection.

### 2.9 Full Basket
Carrying optional loot lengthens interaction/extraction time or creates a route decision.

### 2.10 Night Market — Capstone
Two floors, multiple rooms, two predictable NPCs, hiding spaces, mandatory objective plus optional valuables, and a return through the same building.

---

# Chapter 3 — research reference: Cinema

Chapter purpose: alternate entrances, guard inspection, clean vs destructive entry and persistent evidence.

### 3.1 Side Door
Main entrance is observed; an alternate side entrance is safer.

### 3.2 Pick the Lock
Locked alternate route requires a quiet tool.

### 3.3 Inside / Outside
One patrol covers exterior access while another timing window exists inside.

### 3.4 Back Room
Use a restroom/storage room as a temporary hiding point.

### 3.5 Broken Seal
A destructive entry leaves a persistent `tampered` state.

### 3.6 Inspection
A guard later inspects the tampered door and triggers failure even if the player is already elsewhere.

### 3.7 No Trace
Same geometry, but player must choose a slower clean method to avoid later discovery.

### 3.8 Two Ways In
Both entrances are viable with different risks and timings.

### 3.9 Clean Exit
Player must restore/close an interacted object before the inspection patrol arrives.

### 3.10 Screening Room — Capstone
Exterior and interior patrols, alternate entry, hidden waiting room, inspectable doors and a tool-choice puzzle where the fastest route is not necessarily safe.

---

# Chapter 4 — research reference: Hotel

Chapter purpose: action duration, specialist roles, safe cracking, noisy work and multi-floor timing.

### 4.1 The Safe
Introduce a safe with a long interaction time.

### 4.2 Specialist
Introduce a safe-cracker whose skill reduces action duration.

### 4.3 Thin Walls
Safe work creates noise; guard must be sufficiently far away before work begins.

### 4.4 Up One Floor
Guard moves between floors on a deterministic schedule.

### 4.5 Long Window
Player must observe enough cycles to identify the only safe cracking interval.

### 4.6 Optional Room
A secondary hotel room contains bonus loot but consumes the next safe timing window.

### 4.7 Wrong Specialist
Show that crew choice matters by making one approach technically possible but too slow.

### 4.8 Elevator vs Stairs
Two routes change arrival timing without changing walking speed.

### 4.9 Pack and Leave
Objective is acquired, but lingering for bonus loot makes extraction collide with the returning guard.

### 4.10 Grand Hotel — Capstone
Two or three floors, one specialist objective, patrol moving vertically, noisy safe work, optional valuables and a strict but readable extraction timing puzzle.

---

# Chapter 5 — research reference: Greenhouse / Arboretum

Chapter purpose: delayed discovery, deadlines created by NPC routines and first meaningful crew coordination.

### 5.1 The Technician
NPC visits the objective on a fixed cycle. Missing objective is only noticed on the next visit.

### 5.2 Borrowed Time
Steal immediately after the technician leaves and escape before return.

### 5.3 Faster Hands
Introduce a faster specialist for an interaction, while base walking speed remains constant.

### 5.4 Alternate Entrance
Shorter route requires a different entry tool or crew member.

### 5.5 The Missing Object
Teach delayed failure: the alarm occurs when an NPC discovers the changed world state.

### 5.6 Restore the Scene
A container/display must be closed or reset after theft to delay discovery.

### 5.7 Two People, One Window
One actor opens access; another performs the objective.

### 5.8 Early Exit / Extra Loot
Choose between guaranteed extraction and one optional item before the technician returns.

### 5.9 Tight Cycle
Same grammar with a shorter NPC cycle and more compact geometry.

### 5.10 Conservatory — Capstone
Alternate entry, two actors, technician routine, delayed discovery, primary objective and optional loot under a clear future deadline.

---

# Chapter 6 — research reference: Boxing Club

Chapter purpose: first electronic alarm systems and the difference between physical access and security access.

### 6.1 Alarmed Door
A door can physically open but doing so while armed triggers failure.

### 6.2 Security Panel
Introduce an alarm panel controlling one protected door.

### 6.3 Electronics Specialist
Only the correct crew member/tool can disable the panel efficiently.

### 6.4 Safe Route
Long but clean alarm bypass versus fast noisy/destructive entry.

### 6.5 Re-Arm
Security state may need to be restored after passage.

### 6.6 Inspector
Guard checks the protected door later; leaving the wrong state exposes the burglary.

### 6.7 Panel Across the Hall
Security control is physically separated from the protected object.

### 6.8 Timed Disable
First short temporary alarm-disable window.

### 6.9 Tool Tradeoff
Different electronic tools vary in interaction duration and noise.

### 6.10 Fight Club — Capstone
Patrol + inspectable door + alarm panel + electronic specialist + optional safe. The clean solution requires understanding both security state and guard timing.

---

# Chapter 7 — research reference: Printing Office

Chapter purpose: multiple accomplices, skill specialization, carrying limits and parallel tasks.

### 7.1 Second Actor
Introduce two selectable thieves with separate positions.

### 7.2 Separate Jobs
Actor A opens the route; actor B takes the objective.

### 7.3 Carry Weight
A heavy objective requires the stronger/correct actor.

### 7.4 Three Skills
Lock, safe and alarm each favor different specialists.

### 7.5 Hide the Crew
Inactive actor must wait in a safe location while another passes a patrol.

### 7.6 Parallel Work
Two interactions happen simultaneously to save time.

### 7.7 Timeline Tracks
Make concurrent actions visible as separate plan tracks.

### 7.8 Extraction Order
One actor must leave before another or block/detection timing fails.

### 7.9 Greed vs Capacity
Optional loot competes with carrying capacity needed for the mission item.

### 7.10 Publishing House — Capstone
Three roles, alarm, safe, locked access, hiding points, parallel actions, carrying limits and synchronized extraction.

---

# Chapter 8 — research reference: Undertaker / Funeral Home

Chapter purpose: alternate vertical routes, scene restoration and delayed evidence in a multi-actor plan.

### 8.1 Upper Route
Introduce an elevated/alternate connection between two areas.

### 8.2 Patrol Between Floors
A guard crosses floors, forcing movement through safe vertical windows.

### 8.3 Open / Close
Container state persists; player must close it after interaction.

### 8.4 Safe and Restore
Crack a safe, take objective, restore visible state before inspection.

### 8.5 Parallel Cleanup
One actor steals while another restores/controls a nearby access state.

### 8.6 Wrong Way Back
Fast entry route is unsafe for extraction because patrol phase changed.

### 8.7 Quiet Passage
Alternate route avoids guard hearing but costs time.

### 8.8 Evidence Chain
One visible anomaly causes an inspector to change behavior and discover another anomaly.

### 8.9 Perfect Scene
Bonus condition: leave no inspectable state changed.

### 8.10 Memorial House — Capstone
Multi-floor layout, alternate bridge/upper route, safe, restoring containers/doors, patrol inspections and parallel crew actions.

---

# Chapter 9 — research reference: Mausoleum

Chapter purpose: cross-linked security and timed remote dependencies.

### 9.1 Beam
Introduce laser/trip beam as a binary barrier.

### 9.2 Remote Switch
Switch is located away from the barrier it controls.

### 9.3 Timed Switch
Barrier disables only for a fixed number of seconds.

### 9.4 Hold the Door
Actor A must remain at a control point while actor B crosses.

### 9.5 Cross-Wired
Two alarms protect each other; direct disabling is impossible from the starting side.

### 9.6 Order Matters
Only one sequence of two switches avoids reactivating the barrier too early.

### 9.7 Return Problem
Getting in is easy; restoring the path for extraction requires another synchronization.

### 9.8 Two Windows
Two timed barriers must be crossed in one continuous route.

### 9.9 Remote Relay
Actor B reaches a second switch that then frees actor A.

### 9.10 Crypt — Capstone
Cross-linked alarms, timed beam, two actors, remote switches and a dependency chain where each actor temporarily controls access for the other.

---

# Chapter 10 — research reference: Spam Factory

Chapter purpose: split teams operating in physically separated areas/buildings.

### 10.1 Across the Yard
Two actors start in separate areas.

### 10.2 Remote Disable
Actor A disables security in actor B's building.

### 10.3 Specialist Inside
Actor B reaches a safe/objective only after remote assistance.

### 10.4 Two Patrol Clocks
Separate NPC cycles must align across both areas.

### 10.5 Rendezvous
Actors must meet at a shared extraction point after independent routes.

### 10.6 Re-Enable Behind You
Remote security returns after a timer; actor B must be through before it does.

### 10.7 Hand-Off
One actor acquires an item/key and passes access responsibility to another.

### 10.8 Asymmetric Risk
One side is stealth-heavy; the other is timing/security-heavy.

### 10.9 Three-Stage Relay
A disables -> B advances -> B activates a new control -> A advances.

### 10.10 Industrial Compound — Capstone
Two buildings, split crew, remote security dependency, separate patrol clocks, specialist objective and coordinated extraction.

---

# Chapter 11 — research reference: The Villa

Chapter purpose: optional loot, route choice, cameras and deliberate greed.

### 11.1 One Objective, Many Valuables
Only one item is mandatory; several bonuses are visible.

### 11.2 Camera Route
Introduce a camera-protected direct path and a longer blind path.

### 11.3 High Route
Alternate upper/roof-style route bypasses one security layer.

### 11.4 Solo Job
Mission is solvable alone but slowly.

### 11.5 Crew Job
Second actor makes bonus loot viable without changing the primary route.

### 11.6 Weight Limit
Taking too much prevents carrying the most valuable optional object.

### 11.7 Camera Timing
Rotating camera creates a predictable moving window.

### 11.8 Rich Exit
Greedy route changes extraction timing enough to intersect a guard.

### 11.9 Clean Score
Reward/grade for objective + no alarm + no evidence, independent of loot value.

### 11.10 Private Estate — Capstone
Multiple entry routes, rotating cameras, optional treasure, solo/crew alternatives and a meaningful choice between clean completion and maximum profit.

---

# Chapter 12 — research reference: Neo Office

Chapter purpose: full security dependency graphs and cause/effect reasoning.

### 12.1 Two Systems
One switch controls one laser and one alarm-controlled door.

### 12.2 Chained Switches
Switch A opens access to switch B; switch B controls the objective barrier.

### 12.3 Layered Lasers
Two laser layers require different controls.

### 12.4 Shared Alarm
One alarm protects multiple objects, creating side effects when disabled/re-enabled.

### 12.5 Crew Graph
Different actors start near different graph nodes.

### 12.6 Exit Dependency
The action that opens the objective path can accidentally close the extraction path.

### 12.7 Deadlock
Teach that a legal action can create an unwinnable world state; planning must consider future access.

### 12.8 Parallel Graph
Two independent security branches can be solved concurrently.

### 12.9 Full Rehearsal
Compact puzzle combining alarms, lasers, safes and remote switches.

### 12.10 Corporate HQ — Capstone
Large but readable security graph with several alarms, layered barriers, multiple actors, cause/effect dependencies and a planned route that must remain reversible through extraction.

---

# Chapter 13 — research reference: Museum

Chapter purpose: security hierarchy, control rooms, object inspection and multi-floor team objectives.

### 13.1 Watching Art
Guard periodically checks a specific display/object.

### 13.2 Camera Switch
Local switch disables one camera.

### 13.3 Control Room
A protected room controls multiple downstream security devices.

### 13.4 Missing Exhibit
Removing a visible object becomes evidence when the guard reaches it.

### 13.5 Floor Above
Objective and control system exist on different floors.

### 13.6 Team Objectives
Two actors must steal/control different targets before extraction.

### 13.7 Carrying Curator
High-value optional art competes with mission-item carrying capacity.

### 13.8 Security Hierarchy
Reach local switch -> access control room -> disable gallery security -> steal objective.

### 13.9 Closing Time
Several patrol cycles converge near extraction late in the plan.

### 13.10 Gallery — Capstone
Multi-floor museum, control room, camera hierarchy, inspectable displays, optional valuables, carrying limits and multiple team tasks.

---

# Chapter 14 — research reference: Bank

Chapter purpose: large heist, asymmetric routes, split teams, vault stages and extraction logistics.

### 14.1 Front and Back
Two distinct entry routes teach asymmetry.

### 14.2 Laser Lobby
Front route is short but heavily protected.

### 14.3 Service Route
Back route is longer but gives access to security controls.

### 14.4 Split Team
One team attacks security; another positions near the objective.

### 14.5 First Vault Door
Multi-stage objective: outer security before inner container.

### 14.6 Inner Safe
Second specialist interaction after the first barrier is solved.

### 14.7 Heavy Take
Mission item requires carrying capacity / dedicated carrier.

### 14.8 Different Exit
Best extraction is not the entry route.

### 14.9 Bonus Deposit Boxes
Optional loot exists after the primary objective, creating a greed decision under rising timing pressure.

### 14.10 Central Bank — Capstone
Large multi-zone heist with front/back asymmetry, split crew, alarms, lasers, staged vault access, heavy objective and a different extraction path.

---

# Chapter 15 — research reference: Barracks

Chapter purpose: prove that the engine supports rescue/escort missions, not only theft.

### 15.1 Find the Prisoner
Objective is a person, not loot.

### 15.2 Locked Cell
Remote access must be opened before the rescued actor becomes controllable.

### 15.3 Two Switches
Two controls affect one secure door.

### 15.4 Synchronized Press
Controls must be activated within a narrow shared timing window.

### 15.5 Separate Teams
Actors begin in separated zones.

### 15.6 Free and Hide
Rescued character must remain hidden while the route is reopened.

### 15.7 Escort
Extraction fails if the rescued character is left behind.

### 15.8 Patrol Window
Escort movement is slower/more constrained by group positioning, while base individual walking speed remains fixed.

### 15.9 No Loot
A mission intentionally rewards speed/clean rescue rather than valuables.

### 15.10 Detention Center — Capstone
Separated teams, synchronized switches, prisoner release, guard timing and coordinated escort extraction.

---

# Chapter 16 — research reference: Harbor

Chapter purpose: long dependency chains involving keys, remote rooms, specialists and staged objectives.

### 16.1 Find the Key
Acquire a mission-specific key before the real objective is reachable.

### 16.2 Keyed Room
Key opens a secure room containing a control device.

### 16.3 Warehouse Switch
Control device disables security elsewhere on the map.

### 16.4 Alarm Specialist
Remote warehouse still requires electronic bypass after the first dependency.

### 16.5 Safe Specialist
Objective container introduces another role in the chain.

### 16.6 Runner
One actor must traverse the chain quickly after a temporary state change.

### 16.7 Carrier
Mission object requires a dedicated carrier or inventory slot.

### 16.8 Repeated Coordination
The team must use remote access more than once, not just on entry.

### 16.9 Shortcut
Optional secondary control creates a faster extraction route if solved.

### 16.10 Dockyards — Capstone
Key -> secure room -> remote switch -> warehouse security -> specialist container -> mission object -> coordinated extraction. The chapter is a readable dependency chain, not a maze for its own sake.

---

# Chapter 17 — research reference: Power Plant

Chapter purpose: sabotage/placement objectives, three-team synchronization and staged barriers.

### 17.1 Plant the Device
Objective is to place an item at a target point, not steal anything.

### 17.2 Timed Work
Placement itself takes time and can create noise.

### 17.3 Barrier One
Team A creates access for team B.

### 17.4 Barrier Two
Team B reaches a control that creates access for team C.

### 17.5 Three Teams
Introduce three simultaneous timeline tracks in a compact map.

### 17.6 Guard Routines
Several fixed patrols create synchronized safe windows.

### 17.7 No Return Route
A security change closes the original path; extraction requires the planned alternative.

### 17.8 Sabotage Clock
After placement, a countdown forces immediate extraction.

### 17.9 Full Sequence
Three-stage relay + placement + countdown in a small rehearsal map.

### 17.10 Power Facility — Capstone
Three teams, staged remote barriers, multiple guard cycles, sabotage placement, post-objective countdown and coordinated extraction.

---

# Chapter 18 — research reference: Ministry of Light

Chapter purpose: campaign finale combining the complete vocabulary without inventing arbitrary new mechanics.

### 18.1 Separate Starts
Multiple actors begin in different secured zones.

### 18.2 Camera and Laser
Combine rotating camera and timed laser in one compact route.

### 18.3 Follow the Guard
Safe progress requires using a predictable guard path as a timing reference.

### 18.4 Remote Freedom
Actor A's switch releases access for actor B.

### 18.5 Return Favor
Actor B then controls a system needed by actor A.

### 18.6 Free the Third
Rescue/unlock another actor and add a third timeline track.

### 18.7 Security Cascade
One switch changes several downstream devices, demanding full dependency awareness.

### 18.8 Evidence and Exit
After solving the objective path, the team must avoid leaving a state that causes delayed discovery before extraction.

### 18.9 Final Rehearsal
Compact all-systems puzzle: patrol, camera, laser, alarm, timed switch, remote actor dependency, rescue and extraction.

### 18.10 Finale — Capstone
Original large final mission using multiple starting positions, guards, cameras, lasers, remote switches, actor-to-actor unlocking, rescue/objective dependency and synchronized extraction. It should feel like the player is executing a machine they designed, not improvising an action game.

---

# Production strategy

## Do not build 180 missions before proving the game

The 180-mission list is a **content architecture**, not an instruction to produce all content before testing fun.

Recommended production gates:

### Gate A — vertical slice
Build Chapter 1 missions 1.1, 1.4, 1.7 and 1.10 only.

Purpose: prove movement, patrol, noise, interaction, planning and deterministic execution.

### Gate B — first complete chapter
Finish all 10 Chapter 1 missions.

Purpose: prove whether ten short missions built from one design grammar feel varied enough.

### Gate C — first campaign block
Build Chapters 1–3 = 30 missions.

Purpose: validate retention, progression, difficulty and production cost.

### Gate D — initial commercial release candidate
A realistic initial target is **50–60 polished missions** (approximately Chapters 1–6), if playtesting shows the format works.

The remaining chapter architecture provides expansion content without redesigning the game systems.

## Level reuse philosophy

Reuse code and 3D assets aggressively; do **not** reuse exact solutions.

The same reusable entities can appear everywhere:

- wall/floor modules;
- doors;
- safes;
- desks/cabinets;
- cameras;
- alarm panels;
- switches;
- lasers;
- guards;
- loot containers;
- stairs/elevators;
- extraction markers.

Variety comes from:

- geometry;
- placement;
- security graph;
- patrol route;
- timing;
- objective type;
- available crew/tools;
- optional loot;
- entry/extraction asymmetry.

## Legal / originality rule

The original games are a **design research source**. We may study progression and systemic ideas. We should not reproduce copyrighted maps, mission scripts, dialogue, story, art, names or exact level solutions.

Each capstone should answer this question:

> If someone knows the original mission, can they recognize the design idea while still seeing a completely new map and a new puzzle?

That is the intended relationship.
