#!/usr/bin/env python3
"""
DerClou Asset Pipeline: extract a Mixamo action from an FBX onto an
already-converted character's own .blend, then re-export USDZ. Downloaded FBX
files are treated as untrusted scenes: their meshes, materials, cameras, lights
and source actor are never accepted as game content.

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
comes entirely from the mission-time navigation task, never from animation), so
this script detects which of the Hips bone's three location axes carries the
large one-way drift (the whole-clip travel) versus which carry only the
small cyclic sway/bob, and linearly detrends the drifting axis in place —
subtracting the straight line from the first to the last keyframe — so the
character's hips still sway and bob naturally but the clip no longer walks
the character out from under the mission-time `AgentNavigationTask` and
`AgentLocomotionSystem` that own its RealityKit placement.

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
SEMANTIC_NAMES = [
    "Idle", "StartWalking", "Walk", "TurnLeft", "TurnRight",
    "TurnAround", "StopWalking", "ShortStep", "OpenDoor", "CloseDoor",
    "UnlockDoor", "Lockpick", "PressButton", "PullLever", "Look",
]


def apply_animation(char_name: str, motion_fbx: str, action_name: str):
    if not os.path.exists(motion_fbx):
        print(f"Error: motion FBX not found at {motion_fbx}")
        sys.exit(1)

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    char_dir = os.path.join(project_root, "ArtSource", "Characters", char_name.capitalize())
    char_blend = os.path.join(char_dir, f"{char_name.lower()}.blend")
    out_usdc = os.path.join(char_dir, f"{char_name.lower()}.usdc")
    out_usdz = os.path.join(char_dir, f"{char_name.lower()}.usdz")
    staged_usdc = os.path.join(char_dir, f"{char_name.lower()}.staged.usdc")
    staged_usdz = os.path.join(char_dir, f"{char_name.lower()}.staged.usdz")
    runtime_res_dir = os.path.join(project_root, "Packages/HeistEngine/Sources/HeistKit/Resources/Characters")

    if not os.path.exists(char_blend):
        print(f"Error: {char_blend} not found — run convert_character.py for '{char_name}' first")
        sys.exit(1)

    py_script = rf"""
import bpy, re, os, shutil
from pxr import Sdf, Usd, UsdGeom

bpy.ops.wm.open_mainfile(filepath=r"{char_blend}")

char_arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
canon_to_char = {{}}
for b in char_arm.data.bones:
    canon = re.sub(r'^(mixamorig)\d*:', r'\1:', b.name)
    canon_to_char[canon] = b.name

critical = {{
    'mixamorig:Hips', 'mixamorig:Spine', 'mixamorig:Head',
    'mixamorig:LeftArm', 'mixamorig:RightArm',
    'mixamorig:LeftUpLeg', 'mixamorig:RightUpLeg',
    'mixamorig:LeftLeg', 'mixamorig:RightLeg'
}}
missing_target_critical = sorted(critical.difference(canon_to_char))
if missing_target_critical:
    raise RuntimeError(f'Target rig lacks critical bones: {{missing_target_critical}}')

before_actions = set(bpy.data.actions.keys())
before_objects = set(bpy.data.objects.keys())
before_meshes = set(bpy.data.meshes.keys())
before_armatures = set(bpy.data.armatures.keys())
before_materials = set(bpy.data.materials.keys())
before_images = set(bpy.data.images.keys())
bpy.ops.import_scene.fbx(filepath=r"{motion_fbx}")
imported_objects = [o for o in bpy.data.objects if o.name not in before_objects]
imported_object_names = [o.name for o in imported_objects]
motion_arms = [o for o in imported_objects if o.type == 'ARMATURE']
if len(motion_arms) != 1:
    raise RuntimeError(f'Expected exactly one source armature, got {{len(motion_arms)}}')
motion_arm = motion_arms[0]
imported_mesh_count = sum(1 for o in imported_objects if o.type == 'MESH')
source_canonical_bones = {{
    re.sub(r'^(mixamorig)\d*:', r'\1:', bone.name)
    for bone in motion_arm.data.bones
}}
missing_source_critical = sorted(critical.difference(source_canonical_bones))
if missing_source_critical:
    raise RuntimeError(f'Source action lacks critical bones: {{missing_source_critical}}')

renamed, missing = 0, []
for b in list(motion_arm.data.bones):
    canon = re.sub(r'^(mixamorig)\d*:', r'\1:', b.name)
    target = canon_to_char.get(canon)
    if target and target != b.name:
        b.name = target
        renamed += 1
    elif not target:
        missing.append(b.name)

new_action_keys = [k for k in bpy.data.actions.keys() if k not in before_actions]
if len(new_action_keys) != 1:
    raise RuntimeError(f'Expected exactly one source action, got {{new_action_keys}}')
action = bpy.data.actions[new_action_keys[0]]

# Blender silently turns a second `Walk` into `Walk.001`; USD then exports it
# as `Walk_001`. Remove an older action occupying the same semantic slot so
# the exported clip keeps the stable name expected by the runtime contract.
semantic_action = re.compile(r"^" + re.escape("{action_name}") + r"(?:[._]\d{{3}})?$")
for existing_action in list(bpy.data.actions):
    if existing_action == action or semantic_action.fullmatch(existing_action.name) is None:
        continue
    if char_arm.animation_data and char_arm.animation_data.action == existing_action:
        char_arm.animation_data.action = None
    bpy.data.actions.remove(existing_action)

action.name = "{action_name}"
action.use_fake_user = True

# Turn downloads often describe the right lower-body action but carry a prop
# pose in the arms (torch/rifle/briefcase). For locomotion turns, retain only
# hips and leg tracks. The target rig's neutral rest pose supplies the upper
# body, so downloaded presentation geometry and prop-specific posing never
# leak into the game actor.
if "{action_name}" in {{'TurnLeft', 'TurnRight', 'TurnAround'}}:
    lower_body = (
        'Hips', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase',
        'RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase'
    )
    removed_upper_curves = 0
    for layer in action.layers:
        for action_strip in layer.strips:
            for slot in action.slots:
                channelbag = action_strip.channelbag(slot)
                if not channelbag:
                    continue
                for curve in list(channelbag.fcurves):
                    if not any(name in curve.data_path for name in lower_body):
                        channelbag.fcurves.remove(curve)
                        removed_upper_curves += 1

                # Entity yaw is authoritative and deterministic. Freeze the
                # downloaded Hips quaternion at its first pose so the clip
                # contributes weight transfer and footwork without doubling
                # the turn or fighting the mission-time orientation.
                for curve in channelbag.fcurves:
                    if 'Hips' not in curve.data_path \
                            or not curve.data_path.endswith('].rotation_quaternion') \
                            or not curve.keyframe_points:
                        continue
                    first_value = curve.keyframe_points[0].co[1]
                    for key in curve.keyframe_points:
                        key.co[1] = first_value
                        key.handle_left[1] = first_value
                        key.handle_right[1] = first_value
                    curve.update()
    print(f"TURN_FILTER removed_upper_curves={{removed_upper_curves}} root_yaw=entity")

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
# Blender 5 layered Actions keep the slot identifier of the imported FBX
# armature (usually `OBSlot`). Assigning such an Action to the character does
# not automatically select that slot, so viewport evaluation and USD export
# silently produce an empty SkelAnimation. Bind the action's only imported
# object slot explicitly; the retargeted fcurve paths already name the target
# rig's bones.
if action.slots:
    char_arm.animation_data.action_slot = action.slots[0]

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

for collection, before in (
    (bpy.data.meshes, before_meshes),
    (bpy.data.armatures, before_armatures),
    (bpy.data.materials, before_materials),
    (bpy.data.images, before_images),
):
    for block in list(collection):
        if block.name not in before and block.users == 0:
            collection.remove(block)

# Older versions of this tool removed source objects but left their orphaned
# Ch33 materials/images in the working .blend. Semantic actions carry fake
# users; live character data has real users, so recursive orphan purge removes
# only unreferenced import residue and preserves the actual character library.
bpy.data.orphans_purge(do_recursive=True)

remaining_imported = [name for name in imported_object_names if name in bpy.data.objects]
if remaining_imported:
    raise RuntimeError(f'Source objects survived cleanup: {{remaining_imported}}')

print(f"RETARGET renamed={{renamed}} missing={{len(missing)}} sample_missing={{missing[:8]}}")
print(
    f"CLEANUP removed_imported_objects={{len(imported_objects)}} "
    f"removed_source_meshes={{imported_mesh_count}} remaining=0"
)
print(f"DETREND axes={{detrended_axes}}")

bpy.ops.wm.save_as_mainfile(filepath=r"{char_blend}")

# Blender's USD exporter emits only the armature's active Action. Export each
# semantic Action separately, then compose their SkelAnimation prims into the
# Walk-based character layer. Geometry/materials come from Walk exactly once;
# the other temporary layers contribute only animation specs.
semantic_names = [
    'Idle', 'StartWalking', 'Walk', 'TurnLeft', 'TurnRight',
    'TurnAround', 'StopWalking', 'ShortStep', 'OpenDoor', 'CloseDoor',
    'UnlockDoor', 'Lockpick', 'PressButton', 'PullLever', 'Look'
]
available = {{item.name: item for item in bpy.data.actions if item.name in semantic_names}}
if 'Walk' not in available:
    raise RuntimeError(f'Character has no canonical Walk action; available={{sorted(available)}}')

# `export_textures_mode='NEW'` intentionally refuses to overwrite an existing
# filename. Without this cleanup, a reimport with downscaled textures keeps
# packaging stale high-resolution PNGs from the previous character/export.
# Remove only filenames owned by the currently loaded image datablocks; leave
# unrelated source/legacy files untouched.
texture_directory = os.path.join(r"{char_dir}", 'textures')
for image in bpy.data.images:
    generated_texture = os.path.join(texture_directory, image.name + '.png')
    if os.path.isfile(generated_texture):
        os.remove(generated_texture)

clip_paths = {{}}
for semantic in semantic_names:
    clip_action = available.get(semantic)
    if clip_action is None:
        continue
    char_arm.animation_data.action = clip_action
    if clip_action.slots:
        char_arm.animation_data.action_slot = clip_action.slots[0]
    clip_path = os.path.join(r"{char_dir}", f".{char_name.lower()}.{{semantic}}.usdc")
    if os.path.exists(clip_path):
        os.remove(clip_path)
    bpy.ops.wm.usd_export(
        filepath=clip_path,
        export_animation=True,
        export_armatures=True,
        export_materials=True,
        generate_preview_surface=True,
        export_textures_mode='NEW',
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y"
    )
    if semantic == 'Walk':
        shutil.copyfile(clip_path, r"{staged_usdc}")

    # RealityKit exposes only the animation bound by skel:animationSource
    # from a loaded USD scene. Keep the combined library for interchange, and
    # also produce one unambiguous carrier per semantic. RealityKit only
    # publishes availableAnimations for a skinned scene, so the carrier keeps
    # one minimal target-character skinned mesh but drops every other mesh and
    # all material/texture data.
    # It is loaded only as a resource and is never attached to the scene, hence
    # no second visible character can appear.
    carrier_stage = Usd.Stage.Open(clip_path)
    removable_types = {{
        'Material', 'Shader', 'Camera',
        'DistantLight', 'DiskLight', 'RectLight', 'SphereLight', 'CylinderLight'
    }}
    removable = [
        prim.GetPath() for prim in carrier_stage.Traverse()
        if prim.GetTypeName() in removable_types
    ]
    mesh_prims = [prim for prim in carrier_stage.Traverse() if prim.GetTypeName() == 'Mesh']
    if not mesh_prims:
        raise RuntimeError(f'{{semantic}} carrier has no skinned mesh')
    minimal_mesh = min(
        mesh_prims,
        key=lambda prim: len(UsdGeom.Mesh(prim).GetPointsAttr().Get() or [])
    )
    removable.extend(prim.GetPath() for prim in mesh_prims if prim != minimal_mesh)
    for prim_path in sorted(removable, key=lambda value: len(str(value)), reverse=True):
        carrier_stage.RemovePrim(prim_path)
    for prim in carrier_stage.Traverse():
        if prim.GetTypeName() == 'Mesh':
            for prop in list(prim.GetProperties()):
                if prop.GetName().startswith('material:binding'):
                    prim.RemoveProperty(prop.GetName())
    carrier_stage.GetRootLayer().Save()
    clip_paths[semantic] = clip_path

destination_layer = Sdf.Layer.FindOrOpen(r"{staged_usdc}")
if destination_layer is None:
    raise RuntimeError('Could not open staged USD layer')

for semantic, clip_path in clip_paths.items():
    if semantic == 'Walk':
        continue
    source_stage = Usd.Stage.Open(clip_path)
    animation_prims = [
        prim for prim in source_stage.Traverse()
        if prim.GetTypeName() == 'SkelAnimation'
    ]
    if len(animation_prims) != 1:
        raise RuntimeError(
            f'{{semantic}} export has {{len(animation_prims)}} SkelAnimation prims'
        )
    source_path = animation_prims[0].GetPath()
    destination_path = source_path.GetParentPath().AppendChild(semantic)
    if not Sdf.CopySpec(
        source_stage.GetRootLayer(), source_path,
        destination_layer, destination_path
    ):
        raise RuntimeError(f'Could not compose {{semantic}} into animation library')

destination_layer.Save()
print(f"USD animation library exported={{sorted(clip_paths)}}")
"""

    for staged in (staged_usdc, staged_usdz):
        if os.path.exists(staged):
            os.remove(staged)
    cmd = [BLENDER_APP, "--background", "--factory-startup", "--python-expr", py_script]
    print(f"Applying {motion_fbx} -> {char_blend} as action '{action_name}'...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    for line in res.stdout.splitlines():
        clean = line.strip()
        if (clean.startswith("RETARGET") or clean.startswith("DETREND")
                or clean.startswith("TURN_FILTER")
                or clean.startswith("CLEANUP") or clean.startswith("USD animation library")):
            print(clean)
    # See convert_character.py: Blender has returned 0 here even after an
    # unhandled Python exception aborted the script before usd_export ran,
    # so the output file actually existing is the only trustworthy signal.
    if res.returncode != 0 or not os.path.exists(staged_usdc):
        print("Blender animation apply failed:")
        print(res.stderr)
        print(res.stdout)
        sys.exit(1)

    exported_semantics = [
        semantic for semantic in SEMANTIC_NAMES
        if semantic != "Walk"
        and os.path.exists(os.path.join(char_dir, f".{char_name.lower()}.{semantic}.usdc"))
    ]
    staged_carriers = []
    for semantic in exported_semantics:
        carrier_usdc = f".{char_name.lower()}.{semantic}.usdc"
        carrier_staged_usdz = f"{char_name.lower()}_{semantic}.staged.usdz"
        carrier_out_usdz = os.path.join(char_dir, f"{char_name.lower()}_{semantic}.usdz")
        carrier_result = subprocess.run(
            [USDZIP, "--arkitAsset", carrier_usdc, carrier_staged_usdz],
            capture_output=True,
            text=True,
            cwd=char_dir,
        )
        carrier_staged_path = os.path.join(char_dir, carrier_staged_usdz)
        if carrier_result.returncode != 0 or not os.path.exists(carrier_staged_path):
            print(f"usdzip carrier packaging failed for {semantic}:")
            print(carrier_result.stderr)
            print(carrier_result.stdout)
            sys.exit(1)
        staged_carriers.append((
            semantic,
            os.path.join(char_dir, carrier_usdc),
            carrier_staged_path,
            carrier_out_usdz,
        ))

    usdc_name = os.path.basename(staged_usdc)
    usdz_name = os.path.basename(staged_usdz)
    zip_cmd = [USDZIP, "--arkitAsset", usdc_name, usdz_name]
    print(f"Packaging -> {out_usdz}...")
    zip_res = subprocess.run(zip_cmd, capture_output=True, text=True, cwd=char_dir)
    if zip_res.returncode != 0 or not os.path.exists(staged_usdz):
        print("usdzip packaging failed:")
        print(zip_res.stderr)
        print(zip_res.stdout)
        sys.exit(1)

    os.replace(staged_usdc, out_usdc)
    os.replace(staged_usdz, out_usdz)

    dest_runtime = os.path.join(runtime_res_dir, f"{char_name.lower()}.usdz")
    shutil.copyfile(out_usdz, dest_runtime)
    for semantic, carrier_usdc, carrier_staged_path, carrier_out_usdz in staged_carriers:
        os.replace(carrier_staged_path, carrier_out_usdz)
        shutil.copyfile(
            carrier_out_usdz,
            os.path.join(runtime_res_dir, f"{char_name.lower()}_{semantic}.usdz"),
        )
        os.remove(carrier_usdc)
    walk_carrier_usdc = os.path.join(char_dir, f".{char_name.lower()}.Walk.usdc")
    if os.path.exists(walk_carrier_usdc):
        os.remove(walk_carrier_usdc)
    print("Successfully applied animation and re-exported:")
    print(f" - Working file: {out_usdz}")
    print(f" - Runtime file: {dest_runtime}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: apply_animation.py <character_name> <path_to_motion_fbx> <action_name>")
        sys.exit(1)
    apply_animation(sys.argv[1], sys.argv[2], sys.argv[3])
