#!/usr/bin/env python3
"""
DerClou Asset Pipeline: Retarget a motion-only Mixamo FBX (skeleton + action,
no mesh — a "Without Skin" download) onto an already-converted character's
own .blend, then re-export usdz.

Different Mixamo downloads name the root of the rig differently depending on
which internal character revision generated them (e.g. "mixamorig:Hips" vs
"mixamorig7:Hips" — the digit is per-source-character, not meaningful to us).
Retargeting is done by renaming the incoming motion armature's bones to the
target character's own bone names wherever the name matches once that digit
is stripped; Blender's bone-rename cascades into the action's own fcurve
data_paths automatically (verified directly: renaming
"mixamorig7:Hips" -> "mixamorig:Hips" on the armature updated the action's
`pose.bones["mixamorig7:Hips"].location` path to
`pose.bones["mixamorig:Hips"].location` with no extra step). Any motion bone
with no equivalent on the target rig (e.g. finger joints on a reduced rig)
is left unrenamed and simply has no effect once the leftover motion armature
is deleted.

Root motion: Mixamo walk/run clips bake real forward travel into the Hips
bone's location curve (this project's own translation for a walking actor
comes entirely from PathWalker in HeistCore, never from animation — see the
"Locomotion versus game movement" comment in PathFollowingSystem.swift), so
this script detects which of the Hips bone's three location axes carries the
large one-way drift (the whole-clip travel) versus which carry only the
small cyclic sway/bob, and linearly detrends the drifting axis in place —
subtracting the straight line from the first to the last keyframe — so the
character's hips still sway and bob naturally but the clip no longer walks
the character out from under RealityKit's own placement of it.

Usage:
    python3 ArtSource/Tools/apply_animation.py <character_name> <path_to_motion_fbx> <action_name>
Example:
    python3 ArtSource/Tools/apply_animation.py guard "/Users/exrector/Downloads/actions/Walking.fbx" Walk
"""

import os
import sys
import subprocess
import shutil

BLENDER_APP = "/Applications/Blender.app/Contents/MacOS/Blender"
USDZIP = "/usr/bin/usdzip"


def apply_animation(char_name: str, motion_fbx: str, action_name: str):
    if not os.path.exists(motion_fbx):
        print(f"Error: motion FBX not found at {motion_fbx}")
        sys.exit(1)

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    char_dir = os.path.join(project_root, "ArtSource", "Characters", char_name.capitalize())
    char_blend = os.path.join(char_dir, f"{char_name.lower()}.blend")
    out_usdc = os.path.join(char_dir, f"{char_name.lower()}.usdc")
    out_usdz = os.path.join(char_dir, f"{char_name.lower()}.usdz")
    runtime_res_dir = os.path.join(project_root, "Packages/HeistEngine/Sources/HeistKit/Resources/Characters")

    if not os.path.exists(char_blend):
        print(f"Error: {char_blend} not found — run convert_character.py for '{char_name}' first")
        sys.exit(1)

    py_script = f"""
import bpy, re

bpy.ops.wm.open_mainfile(filepath=r"{char_blend}")

char_arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
canon_to_char = {{}}
for b in char_arm.data.bones:
    canon = re.sub(r'^(mixamorig)\\d*:', r'\\1:', b.name)
    canon_to_char[canon] = b.name

before_actions = set(bpy.data.actions.keys())
before_objects = set(bpy.data.objects.keys())
bpy.ops.import_scene.fbx(filepath=r"{motion_fbx}")
imported_objects = [o for o in bpy.data.objects if o.name not in before_objects]
motion_arm = next(o for o in imported_objects if o.type == 'ARMATURE')

renamed, missing = 0, []
for b in list(motion_arm.data.bones):
    canon = re.sub(r'^(mixamorig)\\d*:', r'\\1:', b.name)
    target = canon_to_char.get(canon)
    if target and target != b.name:
        b.name = target
        renamed += 1
    elif not target:
        missing.append(b.name)

new_action_keys = [k for k in bpy.data.actions.keys() if k not in before_actions]
if not new_action_keys:
    raise RuntimeError('No action found in motion FBX')
action = bpy.data.actions[new_action_keys[0]]
action.name = "{action_name}"
action.use_fake_user = True

# De-trend root (Hips) location: keep cyclic sway/bob, remove one-way travel.
strip = action.layers[0].strips[0]
detrended_axes = []
for slot in action.slots:
    cb = strip.channelbag(slot)
    if not cb:
        continue
    hips_loc_curves = [
        fc for fc in cb.fcurves
        if fc.data_path.endswith('].location') and 'Hips' in fc.data_path
    ]
    for fc in hips_loc_curves:
        pts = fc.keyframe_points
        if len(pts) < 2:
            continue
        first_frame, first_val = pts[0].co
        last_frame, last_val = pts[len(pts) - 1].co
        span = last_val - first_val
        # Cyclic sway/bob stays within a few units; real travel over a whole
        # walk/run clip is an order of magnitude larger. Threshold picked
        # from this project's own reference clips (~10 units of natural sway
        # vs ~125 units of travel in Walking.fbx).
        if abs(span) > 30:
            detrended_axes.append(fc.array_index)
            duration = last_frame - first_frame
            for kp in pts:
                t = (kp.co[0] - first_frame) / duration if duration else 0
                drift = first_val + span * t
                kp.co[1] -= drift
                kp.handle_left[1] -= drift
                kp.handle_right[1] -= drift
            fc.update()

if not char_arm.animation_data:
    char_arm.animation_data_create()
char_arm.animation_data.action = action

# Every downloaded Mixamo motion clip in this project's library turned out
# to be a "with skin" download — even the ones named just "Walking.fbx" —
# bundling a full copy of whichever character was live in the Mixamo
# preview when it was exported (every single file checked carried Ch33,
# the Thief). Removing only motion_arm left those mesh objects orphaned in
# the scene: unskinned, un-scaled by the character's own ~0.01 import
# scale, and silently included in the next export as giant, wrongly
# positioned duplicate geometry sitting outside the SkelRoot — the "giant
# boot" bug. Fix: remove every object this specific import call created,
# not just the armature we actually wanted from it.
for obj in imported_objects:
    bpy.data.objects.remove(obj, do_unlink=True)

print(f"RETARGET renamed={{renamed}} missing={{len(missing)}} sample_missing={{missing[:8]}}")
print(f"CLEANUP removed_imported_objects={{len(imported_objects)}}")
print(f"DETREND axes={{detrended_axes}}")

bpy.ops.wm.save_as_mainfile(filepath=r"{char_blend}")

# Same axis-conversion parameters as convert_character.py: Blender's exporter
# would otherwise leave this Z-up and just tag upAxis="Z", which RealityKit
# does not reliably re-orient for a skinned/animated SkelRoot. Exporting to
# a plain .usdc (export_textures_mode='NEW') and packaging separately with
# usdzip --arkitAsset, not straight to .usdz — see the long comment in
# convert_character.py's usd_export call for why: asking usd_export itself
# to write a .usdz silently drops every texture whenever the source FBX had
# colliding Blender image names, which this script inherits directly since
# it reopens a .blend convert_character.py already built the same way.
bpy.ops.wm.usd_export(
    filepath=r"{out_usdc}",
    export_animation=True,
    export_armatures=True,
    export_materials=True,
    generate_preview_surface=True,
    export_textures_mode='NEW',
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y"
)
print("USD export successful!")
"""

    cmd = [BLENDER_APP, "--background", "--factory-startup", "--python-expr", py_script]
    print(f"Applying {motion_fbx} -> {char_blend} as action '{action_name}'...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if line.startswith("RETARGET") or line.startswith("DETREND") or line.startswith("CLEANUP"):
            print(line)
    # See convert_character.py: Blender has returned 0 here even after an
    # unhandled Python exception aborted the script before usd_export ran,
    # so the output file actually existing is the only trustworthy signal.
    if res.returncode != 0 or not os.path.exists(out_usdc):
        print("Blender animation apply failed:")
        print(res.stderr)
        print(res.stdout)
        sys.exit(1)

    if os.path.exists(out_usdz):
        os.remove(out_usdz)
    usdc_name = os.path.basename(out_usdc)
    usdz_name = os.path.basename(out_usdz)
    zip_cmd = [USDZIP, "--arkitAsset", usdc_name, usdz_name]
    print(f"Packaging -> {out_usdz}...")
    zip_res = subprocess.run(zip_cmd, capture_output=True, text=True, cwd=char_dir)
    if zip_res.returncode != 0 or not os.path.exists(out_usdz):
        print("usdzip packaging failed:")
        print(zip_res.stderr)
        print(zip_res.stdout)
        sys.exit(1)

    dest_runtime = os.path.join(runtime_res_dir, f"{char_name.lower()}.usdz")
    shutil.copyfile(out_usdz, dest_runtime)
    print("Successfully applied animation and re-exported:")
    print(f" - Working file: {out_usdz}")
    print(f" - Runtime file: {dest_runtime}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: apply_animation.py <character_name> <path_to_motion_fbx> <action_name>")
        sys.exit(1)
    apply_animation(sys.argv[1], sys.argv[2], sys.argv[3])
