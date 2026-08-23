# External humanoid animation packs

Heavy source files live under `Sources/` and are intentionally ignored by
Git. Their reproducible structural audit lives in `Catalog/`.

Current source root:

`Sources/ExternalHumanoidPack-2026-08-22/`

- `Basics/` — 24 named Mixamo FBX clips. Directly compatible with DerClou's
  current guard/thief skeletons.
- `Universal Animation Library[Standard]/` — Quaternius UAL1, CC0.
- `Universal Animation Library 2[Standard]/` — Quaternius UAL2, CC0.
- `Universal Base Characters[Standard]/` — Quaternius reference actors and
  hair assets, CC0.
- `Anims_Only_FBX_V1/` — 2548 RancidMilk conversions of CMU mocap clips.

Regenerate a structural audit with Blender using
`ArtSource/Tools/audit_humanoid_pack.py`; merge partitioned output using
`ArtSource/Tools/build_humanoid_audit_catalog.py`.

Do not copy an FBX mesh into the game. Retarget only its action onto an owned
character skeleton, remove gameplay root translation, export a named USDZ
carrier, and validate it with `usdchecker --arkit`.

See `AUDIT.md` for the acceptance decision.
