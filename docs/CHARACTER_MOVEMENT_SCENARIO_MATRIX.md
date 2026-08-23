# Character Movement Scenario Matrix

Status: normative regression gate, 2026-08-22.

Visual playtesting is acceptance evidence, not the discovery mechanism for
basic locomotion. Every character role uses the same contracts below. A change
to planning, collision, animation, doors or mission time must pass the relevant
equivalence classes before it is considered complete.

## Command handoff

| Current phase | New command | Required result |
|---|---|---|
| Idle | Move/interact | Turn if physically required, start, walk, brake, align/action |
| Starting | New destination | Old task remains live until atomic handoff |
| Walking | 0–110° retarget | Preserve live speed and join by a legal tangent curve |
| Walking | 110–180° retarget | Brake/pivot block; never translate along an invented U-turn arc |
| Braking | New destination | Handoff from live pose/speed; no forced idle frame |
| Turning | New destination | Latest request wins; no stale worker may commit |
| Interacting | New command | Explicit cancellation, then the new semantic command |

## Obstacle and actor equivalence classes

| Change | Ahead and intersecting | Ahead but already avoided | Behind | Other room |
|---|---:|---:|---:|---:|
| Add/move solid object | One background replan | No replan | No replan | No replan |
| Remove solid object | Preserve valid path | Preserve path | Preserve path | Preserve path |
| Remove/re-add same object | At most one necessary replan | No replan | No replan | No replan |
| Stationary actor | Early stable detour | Preserve detour | Ignore | Ignore |
| Moving actor crossing | Resolve by commitment time | Preserve reservations | Ignore | Ignore |
| Two solids + actor in their gap | Treat as one combined blocked corridor | Preserve one legal detour | Ignore | Ignore |
| One-body-wide portal, same direction | First committed actor reserves the interval; follower waits before entry | — | — | — |
| One-body-wide portal, opposing directions | First committed actor exits; later actor waits outside or takes a real alternate corridor | — | — | — |

The test is the remaining capsule-safe corridor against the newly published
navigation field. Revision count, ray hits, animation events and collision
callbacks are never themselves reasons to stop or replan.

## Animation/action blocks

One `CharacterActionStateComponent` and Apple `GKStateMachine` adapter owns
presentation transitions for thief, guard and future civilians:

`Idle → Turn → Start → Walk → Brake → Align → Interact → Idle/Resume`

- short distances select `ShortStep`;
- left, right and around are distinct phases;
- terminal alignment is distinct from the initial route turn;
- interaction verbs map centrally to semantic clips;
- left, right and around use extracted lower-body footwork; source prop posing
  and root yaw are removed, while the authoritative entity supplies direction;
- animation never owns position, facing, collision or completion time.

## Automated coverage

- headings: −180° through +180°, including every 15° retarget class;
- route lengths: short step, ordinary segment and long segment;
- incoming speeds: stopped, partial speed and full speed;
- repeated obstacle add/remove cycles;
- idle, start, walk, brake, turn, align, interact and blocked phases;
- stationary/moving body encounters and first-committed right of way;
- compound blockers and an actor occupying their remaining gap;
- moving crossings at −450 ms through +450 ms command offsets;
- a hard swept-capsule gate beneath every planner result;
- 60 Hz fixed-step mission state, coarse render cadence and direct time seek;
- every generated chord checked against eroded walkability.

New movement bugs must first be expressed as a missing equivalence class here,
then fixed in the shared layer and covered automatically. Per-character and
per-level motion patches are prohibited.
