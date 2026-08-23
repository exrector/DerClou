#!/usr/bin/env python3
"""Read-only Blender audit for downloaded action FBX files.

Run through Blender so FBX contents, not filenames, determine whether a source
is usable. The script never saves a .blend and never exports source geometry.

Usage:
  Blender --background --factory-startup --python audit_action_fbx.py -- file.fbx [...]
"""

import bpy
import json
import os
import re
import sys


def canonical(name: str) -> str:
    return re.sub(r"^(mixamorig)\d*:", r"\1:", name)


def audit(path: str) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    before_objects = set(bpy.data.objects.keys())
    before_actions = set(bpy.data.actions.keys())
    bpy.ops.import_scene.fbx(filepath=path)

    objects = [obj for obj in bpy.data.objects if obj.name not in before_objects]
    actions = [action for action in bpy.data.actions if action.name not in before_actions]
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in objects if obj.type == "MESH"]
    cameras = [obj for obj in objects if obj.type == "CAMERA"]
    lights = [obj for obj in objects if obj.type == "LIGHT"]

    bones = sorted({canonical(bone.name) for armature in armatures for bone in armature.data.bones})
    critical = {
        "mixamorig:Hips", "mixamorig:Spine", "mixamorig:Head",
        "mixamorig:LeftArm", "mixamorig:RightArm",
        "mixamorig:LeftUpLeg", "mixamorig:RightUpLeg",
        "mixamorig:LeftLeg", "mixamorig:RightLeg",
    }
    root_curves = []
    for action in actions:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    channelbag = strip.channelbag(slot)
                    if not channelbag:
                        continue
                    for curve in channelbag.fcurves:
                        if "Hips" not in curve.data_path or not curve.keyframe_points:
                            continue
                        root_curves.append({
                            "path": curve.data_path,
                            "index": curve.array_index,
                            "first": curve.keyframe_points[0].co[1],
                            "last": curve.keyframe_points[-1].co[1],
                        })
    return {
        "path": os.path.abspath(path),
        "armatures": len(armatures),
        "meshes_to_discard": len(meshes),
        "cameras_to_discard": len(cameras),
        "lights_to_discard": len(lights),
        "actions": [
            {
                "name": action.name,
                "frame_start": action.frame_range[0],
                "frame_end": action.frame_range[1],
            }
            for action in actions
        ],
        "bone_count": len(bones),
        "missing_critical_bones": sorted(critical.difference(bones)),
        "root_curves": root_curves,
        "motion_only_eligible": len(armatures) == 1
            and len(actions) == 1
            and not critical.difference(bones),
    }


if __name__ == "__main__":
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv) - 1
    paths = sys.argv[separator + 1:]
    if not paths:
        raise SystemExit("Provide at least one FBX path after --")
    print("ACTION_AUDIT=" + json.dumps([audit(path) for path in paths], ensure_ascii=False))
