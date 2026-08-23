# DerClou Mixamo motion intake

The game uses an Apple-native Swift/RealityKit runtime. Source animations may
come from Adobe Mixamo and are converted offline; Apple is not the animation
content provider.

The complete authenticated Motion catalog snapshot is stored in
`mixamo-motion-catalog.json` (machine-readable) and
`mixamo-motion-catalog.tsv` (searchable table). It contains 2446/2446 unique
Mixamo motion UUIDs. The exact DerClou download shortlist is
`mixamo-required-downloads.md`; use its name + description + UUID together,
because Mixamo contains many ambiguous duplicate names.

## 1. Authenticate without saving the token

1. Sign in at <https://www.mixamo.com> with an Adobe ID.
2. Select or upload the humanoid whose skeleton will be used for export.
3. In the browser console run:

```javascript
copy(localStorage.getItem('access_token'))
```

4. In a local terminal run the project tool. If `MIXAMO_ACCESS_TOKEN` is not
   set, it prompts for the copied value with hidden input. The token exists
   only in that process and is never written to a file.

The DOM-name collector below is useful for checking the currently rendered
cards, but it is not the production catalog because infinite scrolling and CSS
class changes make it incomplete:

```javascript
var names = Array.from(document.querySelectorAll('[class*="title"], .name, .product-name'))
  .map(el => el.innerText.trim()).filter(Boolean);
console.log([...new Set(names)].join('\n'));
```

## 2. Search by semantic

Use the queries in `mixamo-search-plan.json`. Example:

```sh
ArtSource/Tools/mixamo_selective_download.py search "stop walking"
ArtSource/Tools/mixamo_selective_download.py search "close door"
ArtSource/Tools/mixamo_selective_download.py search "lockpick"
```

The result is `motion-id<TAB>display name`. Search does not download anything.

## 3. Download candidates, not the whole library

Download a chosen ID into the local source library:

```sh
ArtSource/Tools/mixamo_selective_download.py download MOTION_ID \
  --output ArtSource/Animations/Library/Sources/OfficialExports
```

The export is motion-only FBX 7.4/2019 at 30 fps, with no key reduction. A
`.source.json` provenance receipt is written beside it. The tool refuses to
overwrite an existing file and exports sequentially so Mixamo's per-character
monitor endpoint cannot mix concurrent jobs.

For the project-owned complete offline archive, use the captured 2446-ID
catalog. The bulk queue is sequential, resumable, and stores the UUID in every
filename, so duplicate Mixamo display names cannot overwrite each other:

```sh
ArtSource/Tools/mixamo_selective_download.py bulk \
  --catalog ArtSource/Animations/mixamo-motion-catalog.json \
  --output ArtSource/Animations/Library/Sources/OfficialExports \
  --require-character "Y Bot"
```

The bearer token remains memory-only. `_bulk-state.json` stores completion and
errors but never credentials. Re-running the same command skips completed
UUIDs and resumes after interruption or token expiry.

## 4. Accept and retarget

For every candidate:

1. run `audit_action_fbx.py`;
2. render and inspect a preview from the tactical camera;
3. reject props, unsuitable gender/style, sliding feet or the wrong semantic;
4. run `apply_animation.py` for the accepted semantic;
5. verify RealityKit exposes the named carrier on both actor rigs;
6. update `actions-manifest.json`.

Never copy source meshes, materials, cameras or lights into the character
library. Never publish raw Mixamo FBX files as an asset pack or public mirror.

## Source decision

The separately downloaded RancidMilk/CMU, Quaternius UAL and named Basics
packs are stored under `Packs/`. Their full compatibility decision is recorded
in `Packs/AUDIT.md`; do not mix their unlike skeletons into the direct Mixamo
pipeline merely because every source is humanoid.

- `jasongzy/Mixamo`: retained only as a local, non-redistributed discovery
  archive. Its 2453 FBX filenames are opaque hashes and the files contain only
  the generic `mixamo.com` action name, so they are not production identities.
  `Library/Catalog` stores extracted technical facts; a clip enters production
  only after semantic review and the normal retarget/export pipeline.
- `paulpierre/MixamoHarvester`: useful API reference, but its unmodified mode
  downloads all motions for all characters, stores the bearer token in a text
  file and concurrently shares a per-character export monitor.
- `juanjo4martinez/Mixamo-Downloader`: not adopted; it is a PySide2 GUI last
  committed in June 2024 and its query pagination does not update the page
  parameter.
- Accepted: authenticated first-party Mixamo export through the small
  project-owned selective adapter.

Adobe's current published FAQ permits royalty-free Mixamo characters and
animations in commercial video games. Raw animation files may not be
redistributed as an asset library; provenance receipts remain with the project.
