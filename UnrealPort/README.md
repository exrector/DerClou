# Unreal prototype

This folder contains the current Unreal Engine implementation of the project.

## Open

1. Use Unreal Engine 5.8 or a compatible newer release.
2. Open `DerClue.uproject`.
3. Load `/Game/DerClue/Maps/Lvl_GrantDemo` if it is not already open.
4. Press Play. The Top Down template provides click-to-move input; the `DerClue`
   runtime module owns patrol, navigation, perception, alarm and interactions.

`LS_GrantPatrol` is retained as a presentation asset, but autoplay is disabled.
Sequencer is not gameplay authority.

## Current controls

- left click: move the thief through Unreal NavMesh;
- `T`: toggle the technical layer (occlusion-clipped vision footprints, current
  navigation path and security state);
- `N`: emit a test noise from the prototype alarm clock and send the guard to
  investigate it;
- the cyan line is the authored guard patrol loop.

The prototype uses a fixed perspective diorama camera: the whole level stays
in view instead of following the thief. Doors are kept open while the basic
movement and perception layer is being tested.

## Runtime foundation

- dynamic Recast NavMesh for walls, furniture and moving door topology;
- waypoint patrol with occupied-node skipping and nearest-node return;
- local stationary-actor NavModifier activation, RVO and acceleration-driven
  path following;
- 2D authoritative vision with 3D visibility occlusion;
- sweeping security camera whose physical model and light share one rotation;
- hinged door, security panel, safe and alarm-state smart objects;
- `Normal -> Warning -> Alarm` recovery and alarm-light presentation.

The project startup map is already set to the grant demonstration level.

## Repository scope

Only project-owned content and the Unreal template content required by the prototype are versioned here. Large local marketplace packs, generated build folders, caches and editor state are intentionally excluded from the public repository.
