#!/usr/bin/env python3
"""Import a skinned GLB as a clean DerClou character working blend.

The source scene is never copied wholesale. Unskinned preview geometry,
cameras/lights and non-contract actions are discarded before an atomic replace.
Locomotion and interaction clips are subsequently added by apply_animation.py.

Usage:
  python3 import_animated_character.py guard01 source.glb
"""

import os
import subprocess
import sys


BLENDER_APP = "/Applications/Blender.app/Contents/MacOS/Blender"


def import_character(character_name: str, source_glb: str) -> None:
    if not os.path.isfile(source_glb):
        raise SystemExit(f"Source GLB not found: {source_glb}")

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    character_dir = os.path.join(
        project_root, "ArtSource", "Characters", character_name.capitalize()
    )
    os.makedirs(character_dir, exist_ok=True)
    destination = os.path.join(character_dir, f"{character_name.lower()}.blend")
    staged = os.path.join(character_dir, f"{character_name.lower()}.staged.blend")

    script = rf"""
import bpy, mathutils, os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(
    filepath=r"{os.path.abspath(source_glb)}",
    import_pack_images=True,
    merge_vertices=True
)

armatures = [obj for obj in bpy.data.objects if obj.type == 'ARMATURE']
if len(armatures) != 1:
    raise RuntimeError(f'Expected exactly one armature, got {{len(armatures)}}')
armature = armatures[0]

critical = {{
    'mixamorig:Hips', 'mixamorig:Spine', 'mixamorig:Head',
    'mixamorig:LeftArm', 'mixamorig:RightArm',
    'mixamorig:LeftUpLeg', 'mixamorig:RightUpLeg',
    'mixamorig:LeftLeg', 'mixamorig:RightLeg'
}}
bone_names = {{bone.name for bone in armature.data.bones}}
missing = sorted(critical.difference(bone_names))
if missing:
    raise RuntimeError(f'Character lacks critical humanoid bones: {{missing}}')

def belongs_to_rig(obj):
    current = obj.parent
    while current is not None:
        if current == armature:
            return True
        current = current.parent
    return any(mod.type == 'ARMATURE' and mod.object == armature for mod in obj.modifiers)

removed = []
for obj in list(bpy.data.objects):
    keep = obj == armature or (obj.type == 'MESH' and belongs_to_rig(obj))
    if not keep:
        removed.append((obj.name, obj.type))
        bpy.data.objects.remove(obj, do_unlink=True)

meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH']
if not meshes:
    raise RuntimeError('No skinned character meshes survived cleanup')

# Keep only the source Idle. Movement clips require measured ground-speed
# metadata and are applied later through the common semantic pipeline.
idle = bpy.data.actions.get('Idle')
if idle is None:
    raise RuntimeError(f'Source has no Idle action; actions={{list(bpy.data.actions.keys())}}')
for action in list(bpy.data.actions):
    if action != idle:
        bpy.data.actions.remove(action)
idle.name = 'Idle'
idle.use_fake_user = True
if armature.animation_data is None:
    armature.animation_data_create()
armature.animation_data.action = idle

# glTF PBR materials are authoritative. Remove accidental metallic defaults
# from cloth/skin and let Blender regenerate Apple-compatible USD shaders.
for material in bpy.data.materials:
    if not material.use_nodes:
        continue
    for node in material.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED' and 'Metallic IOR Level' in node.inputs:
            node.inputs['Metallic IOR Level'].default_value = 0.0
        elif node.type == 'BSDF_PRINCIPLED' and 'Metallic' in node.inputs:
            node.inputs['Metallic'].default_value = 0.0

# Characters occupy only a small part of the tactical view. Keeping twelve
# 1024px source maps made this guard more than twice as heavy as the asset it
# replaces without a visible benefit at the tactical camera's on-screen size.
# Preserve aspect ratio and cap the packed source at 256px before export.
resized_images = []
for image in bpy.data.images:
    width, height = image.size
    largest = max(width, height)
    if largest <= 256 or width == 0 or height == 0:
        continue
    scale = 256 / largest
    image.scale(max(1, round(width * scale)), max(1, round(height * scale)))
    image.pack()
    resized_images.append(image.name)

# Put the visible soles on y=0 without baking translation into animation.
corners = [
    obj.matrix_world @ mathutils.Vector(corner)
    for obj in meshes for corner in obj.bound_box
]
minimum_z = min(point.z for point in corners)
armature.location.z -= minimum_z

bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=r"{staged}")
print(
    f'CHARACTER_IMPORT meshes={{len(meshes)}} vertices={{sum(len(obj.data.vertices) for obj in meshes)}} '
    f'bones={{len(armature.data.bones)}} removed={{removed}} resized_images={{resized_images}} '
    f'floor_adjust={{-minimum_z}}'
)
"""

    if os.path.exists(staged):
        os.remove(staged)
    result = subprocess.run(
        [BLENDER_APP, "--background", "--factory-startup", "--python-expr", script],
        capture_output=True,
        text=True,
    )
    for line in result.stdout.splitlines():
        if line.strip().startswith("CHARACTER_IMPORT"):
            print(line.strip())
    if result.returncode != 0 or not os.path.isfile(staged):
        print(result.stdout)
        print(result.stderr)
        raise SystemExit("Blender character import failed")
    os.replace(staged, destination)
    print(f"Installed clean working character: {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: import_animated_character.py <character_name> <source.glb>")
    import_character(sys.argv[1], sys.argv[2])
