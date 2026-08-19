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

def convert(char_name: str, fbx_path: str):
    if not os.path.exists(fbx_path):
        print(f"Error: FBX file not found at {fbx_path}")
        sys.exit(1)

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    char_dir = os.path.join(project_root, "ArtSource", "Characters", char_name.capitalize())
    tex_dir = os.path.join(char_dir, "Textures")
    out_usdz = os.path.join(char_dir, f"{char_name.lower()}.usdz")
    runtime_res_dir = os.path.join(project_root, "Packages/HeistEngine/Sources/HeistKit/Resources/Characters")

    os.makedirs(tex_dir, exist_ok=True)
    os.makedirs(runtime_res_dir, exist_ok=True)

    py_script = f"""
import bpy, os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath="{fbx_path}")

# Metric units
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0

# Extract textures
for img in bpy.data.images:
    if img.packed_file:
        clean_name = os.path.basename(img.name)
        if not clean_name.endswith((".png", ".jpg")):
            clean_name += ".png"
        target_path = os.path.join(r"{tex_dir}", clean_name)
        img.filepath_raw = target_path
        img.file_format = "PNG"
        img.save()

# Save blend scene for editing
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(r"{char_dir}", f"{char_name.lower()}.blend"))

# Export USDZ
bpy.ops.wm.usd_export(
    filepath=r"{out_usdz}",
    export_animation=True,
    export_armatures=True,
    export_materials=True,
    generate_preview_surface=True
)
print("USDZ export successful!")
"""

    cmd = [BLENDER_APP, "--background", "--python-expr", py_script]
    print(f"Converting {fbx_path} -> {out_usdz}...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("Blender export failed:")
        print(res.stderr)
        print(res.stdout)
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
