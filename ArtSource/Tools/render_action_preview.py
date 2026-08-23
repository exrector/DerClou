#!/usr/bin/env python3
"""Render four read-only pose previews from an action FBX in Blender.

Usage:
  Blender --background --factory-startup --python render_action_preview.py -- input.fbx output-prefix
"""

import bpy
import mathutils
import os
import sys


separator = sys.argv.index("--")
source, output_prefix = sys.argv[separator + 1:separator + 3]
action_query = sys.argv[separator + 3] if len(sys.argv) > separator + 3 else None
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=source)

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if not meshes:
    raise RuntimeError("Action source has no preview mesh")

corners = [obj.matrix_world @ mathutils.Vector(corner) for obj in meshes for corner in obj.bound_box]
minimum = mathutils.Vector(tuple(min(point[index] for point in corners) for index in range(3)))
maximum = mathutils.Vector(tuple(max(point[index] for point in corners) for index in range(3)))
center = (minimum + maximum) / 2
height = max(maximum.z - minimum.z, 1.0)

camera_data = bpy.data.cameras.new("PreviewCamera")
camera = bpy.data.objects.new("PreviewCamera", camera_data)
bpy.context.scene.collection.objects.link(camera)
camera.location = center + mathutils.Vector((height * 1.15, -height * 2.8, height * 0.35))
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.lens = 70
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.render.resolution_x = 420
scene.render.resolution_y = 560
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("PreviewWorld")
scene.world.color = (0.08, 0.08, 0.08)

actions = list(bpy.data.actions)
if action_query:
    matches = [action for action in actions if action_query.lower() in action.name.lower()]
    if len(matches) != 1:
        raise RuntimeError(f"Action query {action_query!r} resolved to {[action.name for action in matches]}")
    action = matches[0]
else:
    action = next(iter(actions))
armature = next((obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"), None)
if armature is not None:
    if not armature.animation_data:
        armature.animation_data_create()
    armature.animation_data.action = action
    if getattr(action, "slots", None):
        armature.animation_data.action_slot = action.slots[0]
start, end = action.frame_range
for index, fraction in enumerate((0.0, 0.25, 0.5, 0.75)):
    scene.frame_set(round(start + (end - start) * fraction))
    scene.render.filepath = os.path.abspath(f"{output_prefix}_{index}.png")
    bpy.ops.render.render(write_still=True)
