#!/usr/bin/env python3
"""
DerClou Asset Pipeline: Character FBX to USDZ Converter
Usage:
    python3 ArtSource/Tools/convert_character.py <character_name> <path_to_fbx>
Example:
    python3 ArtSource/Tools/convert_character.py thief ArtSource/Characters/Thief/Source/Reaction.fbx
"""

import os
import sys
import subprocess
import shutil

BLENDER_APP = "/Applications/Blender.app/Contents/MacOS/Blender"
USDZIP = "/usr/bin/usdzip"

def convert(char_name: str, fbx_path: str):
    if not os.path.exists(fbx_path):
        print(f"Error: FBX file not found at {fbx_path}")
        sys.exit(1)

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    char_dir = os.path.join(project_root, "ArtSource", "Characters", char_name.capitalize())
    out_usdc = os.path.join(char_dir, f"{char_name.lower()}.usdc")
    out_usdz = os.path.join(char_dir, f"{char_name.lower()}.usdz")
    runtime_res_dir = os.path.join(project_root, "Packages/HeistEngine/Sources/HeistKit/Resources/Characters")

    os.makedirs(char_dir, exist_ok=True)
    os.makedirs(runtime_res_dir, exist_ok=True)

    py_script = f"""
import bpy, os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath="{fbx_path}")

# Metric units
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0

# Mixamo (and most Mixamo-derived downloads, hence the "_nonPBR" filename
# tag) authors materials in the old Phong style, which has no Metallic
# concept at all. Blender's FBX importer has to guess a Principled BSDF
# Metallic value when converting a Phong material and lands on ~0.5 by
# default. Cloth, skin and hair are never metallic (0.0); left at ~0.5,
# the diffuse texture's actual colour gets replaced by an unlit-looking
# black reflection everywhere there is no real environment map to reflect
# — verified directly: re-rendering the same imported mesh with Metallic
# forced to 0 was the difference between a flat near-black silhouette and
# correctly coloured skin/cloth. Roughness is left alone since it comes
# from an actual glossiness texture the importer wires up, not a guess.
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            node.inputs['Metallic'].default_value = 0.0

# Save blend scene for editing. NOTE: no manual texture-extraction step here
# any more — see the comment above usd_export below for why that used to
# silently corrupt every character this script has ever produced.
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(r"{char_dir}", f"{char_name.lower()}.blend"))

# Export to a plain (non-.usdz) layer with textures written by Blender's own
# exporter, THEN hand the result to Apple's usdzip --arkitAsset separately
# (see convert() below) instead of asking usd_export to write straight to a
# .usdz path.
#
# The earlier version of this script pre-extracted every packed image to
# disk itself (img.filepath_raw = <path>; img.save()) before calling
# usd_export(filepath=".../x.usdz", ...) directly. That silently produced
# usdz archives containing ONLY the .usdc and NOT a single texture — every
# character converted through this script before this fix (Thief, Guard,
# Civilian01) shipped completely textureless, which is why they all
# rendered as flat black silhouettes in-game regardless of the Metallic
# fix above. Root cause, found by instrumenting the exact same import with
# res.stdout captured instead of only printed on failure: when a Mixamo FBX
# has multiple embedded images whose raw names collide after Blender's own
# datablock-uniquing (e.g. "file9", "file9.001", "file9.002" all belonging
# to logically different textures), Blender's *internal* usdz-packaging
# step computes its own staging filename for each image — independently of
# whatever filename our manual extraction loop had already saved it under
# — and for several of them the two names diverged, so its "AddFile" step
# tried to zip a temp path that our pre-extraction never wrote:
#   Runtime Error: ... Failed to map '.../textures/file10.png': No such
#   file or directory
# printed as a non-fatal USD warning, past which usd_export still returned
# {{'FINISHED'}}, so convert()'s `res.returncode != 0` check never caught it.
# Skipping our own extraction and letting Blender name+write the textures
# itself (export_textures_mode='NEW') avoids the collision entirely, and
# usdzip packages the result as a completely separate, verified step.
bpy.ops.wm.usd_export(
    filepath=r"{out_usdc}",
    export_animation=True,
    export_armatures=True,
    export_materials=True,
    generate_preview_surface=True,
    export_textures_mode='NEW',
    # See the matching comment in generate_thief_model.py: Blender's exporter
    # leaves Z-up data as-is and just tags `upAxis = "Z"` unless told
    # otherwise, which RealityKit does not reliably re-orient for a skinned/
    # animated SkelRoot (a plain static mesh is fine; a rig is not).
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y"
)
print("USD export successful!")
"""

    cmd = [BLENDER_APP, "--background", "--factory-startup", "--python-expr", py_script]
    print(f"Converting {fbx_path} -> {out_usdc}...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    # Blender's --python-expr has returned 0 here even after an unhandled
    # Python exception aborted the script partway through (caught once: a
    # stray os.path.join with no `import os` killed the script right before
    # usd_export ran, and this returncode check alone said nothing was
    # wrong). The output file actually existing is the only trustworthy
    # signal.
    if res.returncode != 0 or not os.path.exists(out_usdc):
        print("Blender export failed:")
        print(res.stderr)
        print(res.stdout)
        sys.exit(1)

    # Package the plain .usdc + its textures/ folder into a proper,
    # RealityKit-compatible .usdz — the step that was silently failing
    # inside usd_export itself (see the long comment above). usdzip is
    # Apple's own tool (part of the USD toolchain Xcode ships), so this is
    # the same packaging RealityKit's own asset pipeline expects, not a
    # third-party approximation of it.
    if os.path.exists(out_usdz):
        os.remove(out_usdz)
    # Relative filenames, run from char_dir: usdzip's --arkitAsset resolver
    # failed outright ("Failed to author USDZ file", no further detail) when
    # given the same two paths as absolute — it wants to resolve the asset
    # relative to the working directory it runs in.
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

    # Copy to runtime resources
    dest_runtime = os.path.join(runtime_res_dir, f"{char_name.lower()}.usdz")
    shutil.copyfile(out_usdz, dest_runtime)
    print(f"Successfully generated and installed asset:")
    print(f" - Working file: {out_usdz}")
    print(f" - Runtime file: {dest_runtime}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: convert_character.py <character_name> <path_to_fbx>")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
