# Art Direction

Status: visual baseline agreed in discussion, 2026-08-16.

## 1. Core visual decision

The game is **not a 2D sprite game**.

It uses a true 3D scene and reusable 3D assets, rendered from a high top-down tactical camera so the result reads like a polished 2D/2.5D strategy map.

This solves the original asset problem: a desk, safe, camera, chair or character does not need to be redrawn for every viewing angle. The same model is rotated and reused across missions.

## 2. Target look

Desired visual character:

- dark, polished heist/security aesthetic;
- semi-realistic or stylized-realistic PBR;
- high readability on iPhone;
- architecture and props look believable rather than diagrammatic;
- real volume, shadows and materials;
- clean silhouettes;
- no pixel art;
- no flat programmer-art as final output;
- no cartoon/mobile-F2P look.

The reference concept generated during design discussion had:

- dark blue/charcoal floors;
- thick architectural walls;
- warm wood furniture mixed with metal security equipment;
- soft local lights;
- visible safe, desk, cabinets, plants, camera and guard;
- green planned route;
- blue camera cone;
- red laser/alarm feedback;
- HUD around a largely unobstructed tactical scene.

That *visual language* is the target, not the literal generated image.

## 3. Camera

Primary camera:

- high top-down;
- prefer orthographic projection;
- fixed orientation during ordinary planning;
- scene framed for tactical readability.

Possible later polish:

- subtle zoom toward selected room/object;
- slight cinematic tilt during execution;
- smooth transition to a closer safe/door interaction;
- alarm-state camera emphasis.

Do not sacrifice path-planning readability for cinematic effects.

## 4. Asset philosophy

Build a reusable library.

### Architecture

- floor modules/materials;
- wall modules;
- doors and frames;
- windows;
- stairs;
- pillars;
- railings;
- ceilings only where visually useful (generally hidden/cut away in tactical view).

### Office/interior props

- desks;
- chairs;
- filing cabinets;
- shelves;
- sofas;
- conference tables;
- computers;
- printers;
- lamps;
- plants;
- bins;
- lockers;
- storage crates.

### Security props

- fixed/rotating cameras;
- keypads;
- alarm panels;
- laser emitters/receivers;
- electrical panels;
- security monitors;
- card readers;
- sensors;
- safes/vault elements.

### Loot / objectives

- cash bundles;
- jewelry case;
- gold/valuable objects;
- paintings;
- documents;
- electronics;
- mission-specific containers.

### Characters

At minimum:

- protagonist/thief rig;
- guard rig;
- later multiple thief/guard variants;
- optional civilians.

One rig can potentially support multiple clothing/appearance variants.

## 5. Why 3D is mandatory for this project

With 2D rendered assets, every direction/state creates asset explosion.

With 3D:

- one desk works at every yaw angle;
- one camera physically scans;
- one guard can turn continuously;
- one door opens correctly in either placement direction;
- one chair can be rotated/scaled/placed naturally;
- lighting and shadows update automatically;
- mission layouts can visually differ using the same asset library.

This is both higher quality and more scalable for many missions.

## 6. Animation strategy

### Characters

Use skeletal animation.

Initial clips:

- Idle;
- Walk;
- interact generic;
- lockpick;
- work on panel/electronics;
- safe cracking/drilling;
- pick up loot;
- carry heavy object if needed;
- alert/reaction for guards.

Do not block the first slice on every contextual animation. Idle + Walk + one generic interaction are enough to validate the system, then expand.

Use Reality Composer Pro 3 Animation Graph for state blending where practical.

### Security camera

Do not use sprite frames.

- rotate camera head/entity transform;
- scan between configured yaw limits;
- movement synchronized with the real detection cone;
- optional status LED/material state.

### Door

- actual hinge pivot;
- smooth rotation;
- separate lock/alarm state from visual transform;
- destructive entry can later swap/add damaged geometry/decal.

### Laser

- beam geometry/material;
- subtle emissive pulse;
- off/on/alarm state;
- optional impact/spark effect on trigger;
- visible beam exactly matches gameplay collision/detection.

### Alarm/keypad

- emissive LED blink/pulse;
- clear armed/disabled/triggered state;
- optional small screen material.

### Safe/containers

- articulated door/lid/drawer;
- open/close animation;
- inside contents become interactable after opening.

## 7. Gameplay visualization

Gameplay state must remain readable without making the world look like a debug editor.

### Route

- restrained green/neutral route line;
- animated direction indicator can communicate movement;
- hide or fade route during final execution if visually distracting.

### Selection

- subtle ring/outline beneath selected actor;
- no huge glowing mobile-game aura.

### Camera cone

- translucent cool-blue cone in planning/inspection mode;
- may be hidden/faded in cinematic execution if player already understands it;
- exact geometry must correspond to detection.

### Guard vision

- translucent cone or selective visualization when useful;
- style distinct from security-camera cone if needed;
- avoid saturating the whole map with colored overlays.

### Noise

Potential visualization:

- expanding subtle ring at action point;
- projected affected area when selecting a noisy tool;
- should show the *actual* hearing rule.

### Alarm

- red practical lights/material accents;
- HUD warning;
- optional scene-wide subtle red wash only if it does not obscure navigation.

## 8. Level visual variety without new engines/assets every time

Use the same asset library with different:

- floor/wall materials;
- furniture mixes;
- lighting temperatures;
- prop density;
- layout geometry;
- decals/signage;
- security equipment;
- exterior surroundings.

Potential location families:

- small office;
- retail store;
- warehouse;
- mansion;
- gallery/museum;
- bank;
- industrial plant;
- government facility;
- harbor/terminal.

Create a limited number of coherent environment kits rather than a completely new art style per mission.

## 9. Asset production approach

The exact zero-cost/low-cost 3D asset generation workflow is **not yet finalized**.

Rules:

- do not subscribe to expensive asset-generation services by default;
- prefer tools already included with the Apple development stack or free/local tooling;
- purchased third-party packs are not assumed;
- licensing of every external asset must be known before shipping;
- generated assets must be consistent enough to belong to one game;
- final assets must be editable and reusable, not only rendered pictures.

Reality Composer Pro 3 is the scene/material/animation authoring hub, but it is not itself a complete automatic 3D-model generator.

When selecting a modeling/generation pipeline, evaluate in this order:

1. quality;
2. consistent art direction;
3. commercial license;
4. zero/low recurring cost;
5. easy USD/USDZ/RealityKit integration;
6. ease of modification;
7. automation by Claude/Codex where possible.

## 10. Materials / lighting

Use PBR materials deliberately.

Desired separation:

- metal security devices visibly metal;
- warm wood for desks/doors where appropriate;
- matte walls;
- dark but readable flooring;
- safe/vault steel distinct from ordinary furniture.

Lighting:

- practical ceiling/wall fixtures can create atmosphere;
- avoid pitch-black corners that hide important tactical information;
- shadows need to communicate volume, not obscure the grid/path;
- baked/static lighting vs dynamic lights should be evaluated for performance in RCP3.

## 11. Scale

Use real-world-ish metric scale so navigation and asset reuse remain sane.

Examples as starting points only:

- standard door width ~0.9 m;
- corridor width ~1.2–2.0 m;
- desk ~1.2–1.8 m wide;
- character height around human scale.

Do not scale individual levels arbitrarily to fit the camera. Adjust camera framing instead.

## 12. Interaction affordances

An interactable object should be recognizable by context first, highlight second.

Avoid permanently outlining every interactive prop.

Suggested behavior:

- normal state: visually natural;
- selected/hover-equivalent state: subtle outline/emission;
- unavailable action: muted response;
- objective object: restrained persistent indicator if required.

## 13. HUD

HUD should be compact and native-looking, not a giant console-game overlay.

Potential planning HUD:

- mission clock/timeline;
- alert state;
- selected actor;
- tools/loadout;
- plan/execute control;
- loot/objective progress.

SwiftUI should handle most HUD elements.

## 14. What not to do

- Do not render each level as a single static AI image.
- Do not generate separate PNG furniture for different angles.
- Do not use frame-by-frame animation for rotating cameras/doors/lasers.
- Do not make the final game look like a blueprint or abstract geometry solely because it is easier.
- Do not change art style from mission to mission.
- Do not overuse bloom/neon until tactical information becomes harder to read.

## 15. Visual acceptance criterion for Level 1

A screenshot of the first mission without explanation should already look like a commercially released premium tactical/heist game, even before the player understands the mechanics.

## Prototype look, settled 2026-08-18

The reference is a tabletop diorama — light, airy, made of real materials — and
**not** the original grey-box, which the owner rightly called a prison cell: a
sealed dark box with nothing outside it.

What that means in practice, all of it already in `GreyboxKit`:

- **Pale warm surfaces.** Plaster walls near white, floors a warm off-white,
  painted wood for furniture. The palette is light; contrast comes from shadow
  and from the few saturated pieces, not from a dark base.
- **The building stands somewhere.** Grass around it, a paved apron where it
  meets the ground, a path leading off the near edge with hedging along it,
  shrubs against the outside walls and a couple of trees taller than the roof
  line. None of it is walkable and none of it reaches the navigation grid — it
  is there so the level reads as a place rather than as a box.
- **One warm key with shadows, one cool sky fill, a weak bounce.** The key is
  angled, never overhead: a tilted view lives on the shadows walls and furniture
  throw across the floor. The fill is blue because the light that is not the sun
  comes from the sky, and that is most of what keeps the scene from looking
  sealed.
- **People are pawns.** A base, a tapered body, a head, and a wedge on the base
  for facing. It reads from above and from the tactical angle both, which a
  cylinder does not, and it is the shape a board game would use.
- **Walls get out of the way.** Anything standing between the camera and the
  person being watched fades out — see `WallFadeSystem`. This is what allows the
  view to be tilted far enough to have depth at all.

### Open

**Shadows do not render in the simulator.** The shadow's reach was the first
suspect and is now set correctly — it defaults to five metres, and a level is
twenty-four across, so with the default nothing was ever shadowed. Setting it
did not bring shadows back in the simulator, which points at the simulator's own
Metal support rather than at the scene. To be confirmed on a device before any
further lighting work: the art direction above assumes shadows, and judging it
without them is judging a different picture.
