Character usdz assets were soft-deleted to Корзина/characters-2026-08-20/
on 2026-08-20 pending a decision on a new character model source. Until a
new .usdz lands here, PropCatalog's `asset: "thief"` / `asset: "guard"`
wiring falls back to LevelSceneBuilder's greybox pawn.

This file exists only so SwiftPM's `.process("Resources")` resource bundle
is never completely empty — an empty bundle fails codesign at build time.
Delete it once real assets are back.
