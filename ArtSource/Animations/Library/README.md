# DerClou local animation library

This directory is the single workstation-local source library for character
motions. Runtime builds never load raw FBX files directly.

## Layout

- `Sources/HashArchive` — 2453 motion-only FBX files from the gated research
  dataset. Their hash filenames are stable IDs, not semantic names.
- `Sources/NamedDownloads` — manually downloaded, filename-labelled sources;
  names are useful search hints but are not unique Mixamo identities.
- `Sources/OfficialExports` — first-party Mixamo exports with UUID-bearing
  filenames and `.source.json` receipts.
- `Catalog/animation-library.json` — complete machine-readable facts.
- `Catalog/animation-library.tsv` — searchable spreadsheet-style view.
- `Catalog/search-index.json` — compact index for tools and future level editor.
- `Views/ByTechnicalClass` — generated symlink views; no FBX duplication.
- `Selected` — curated semantic clips accepted for the game pipeline.
- `Work` — resumable Blender audit output and logs.

`Sources`, `Views`, and `Work` are ignored by Git because raw third-party
animations must not be published as a redistributable asset pack. Catalogs and
selection policy remain versioned.

## Identity rule

The FBX action name `Armature|mixamo.com|Layer0` is not a semantic identity.
The catalog never invents a title for a hash file. A name is confirmed only by
a first-party receipt or an identical extracted motion fingerprint matching one
confirmed receipt. All other entries retain technical descriptions until they
are visually classified.

## Runtime intake

1. Search `Catalog/animation-library.tsv` or `search-index.json`.
2. Preview candidates from `Views/ByTechnicalClass`.
3. Accept one clip into a semantic slot under `Selected`.
4. Run `audit_action_fbx.py`, then `apply_animation.py`.
5. Export a named USDZ carrier for `CharacterAnimationLibrary`.

Gameplay movement remains deterministic Swift data. FBX root motion is measured
for synchronization and then removed/detrended during retargeting; it never
becomes navigation authority.

Examples:

```sh
# Semantic text search.
ArtSource/Tools/query_animation_library.py opening door

# Short motion-only turns suitable for tactical movement review.
ArtSource/Tools/query_animation_library.py turn \
  --class turn-in-place --motion-only --max-seconds 2

# Only identities backed by a first-party receipt.
ArtSource/Tools/query_animation_library.py walk --confirmed-only

# Full source/catalog integrity check after importing or moving files.
ArtSource/Tools/validate_animation_library.py --deep
```

`Catalog/gameplay-candidates.md` contains the generated ranked shortlist for
the shared gameplay vocabulary. `Selected/current-selections.json` resolves the
existing `actions-manifest.json` choices to stable library IDs and paths.
