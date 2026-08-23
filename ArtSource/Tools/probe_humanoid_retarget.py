#!/usr/bin/env python3
"""Bake and visually/ numerically probe a foreign humanoid action on DerClou's guard.

This is a compatibility probe, not a runtime importer. It uses an explicit
semantic bone map and rest-axis conjugation; no source mesh is retained.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


MAPS = {
    "mixamo": {
        "hips": "Hips", "spine_lower": "Spine", "spine_mid": "Spine1", "spine_upper": "Spine2",
        "neck": "Neck", "head": "Head", "shoulder_l": "LeftShoulder", "upper_arm_l": "LeftArm",
        "lower_arm_l": "LeftForeArm", "hand_l": "LeftHand", "shoulder_r": "RightShoulder",
        "upper_arm_r": "RightArm", "lower_arm_r": "RightForeArm", "hand_r": "RightHand",
        "upper_leg_l": "LeftUpLeg", "lower_leg_l": "LeftLeg", "foot_l": "LeftFoot", "toe_l": "LeftToeBase",
        "upper_leg_r": "RightUpLeg", "lower_leg_r": "RightLeg", "foot_r": "RightFoot", "toe_r": "RightToeBase",
    },
    "quaternius": {
        "hips": "pelvis", "spine_lower": "spine_01", "spine_mid": "spine_02", "spine_upper": "spine_03",
        "neck": "neck_01", "head": "Head", "shoulder_l": "clavicle_l", "upper_arm_l": "upperarm_l",
        "lower_arm_l": "lowerarm_l", "hand_l": "hand_l", "shoulder_r": "clavicle_r",
        "upper_arm_r": "upperarm_r", "lower_arm_r": "lowerarm_r", "hand_r": "hand_r",
        "upper_leg_l": "thigh_l", "lower_leg_l": "calf_l", "foot_l": "foot_l", "toe_l": "ball_l",
        "upper_leg_r": "thigh_r", "lower_leg_r": "calf_r", "foot_r": "foot_r", "toe_r": "ball_r",
    },
    "cmu": {
        "hips": "hip", "spine_lower": "abdomen", "spine_upper": "chest", "neck": "neck", "head": "head",
        "shoulder_l": "lCollar", "upper_arm_l": "lShldr", "lower_arm_l": "lForeArm", "hand_l": "lHand",
        "shoulder_r": "rCollar", "upper_arm_r": "rShldr", "lower_arm_r": "rForeArm", "hand_r": "rHand",
        "upper_leg_l": "lThigh", "lower_leg_l": "lShin", "foot_l": "lFoot",
        "upper_leg_r": "rThigh", "lower_leg_r": "rShin", "foot_r": "rFoot",
    },
}


def canon(name):
    return re.sub(r"^mixamorig\d*:", "", name)


def family(bones):
    canonical = {canon(name) for name in bones}
    if {"Hips", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg"} <= canonical:
        return "mixamo"
    if {"pelvis", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"} <= bones:
        return "quaternius"
    if {"hip", "lShldr", "rShldr", "lThigh", "rThigh"} <= bones:
        return "cmu"
    raise RuntimeError(f"Unknown skeleton: {sorted(bones)[:20]}")


def lookup(armature, rig_family):
    by_name = {canon(b.name): b.name for b in armature.data.bones} if rig_family == "mixamo" else {b.name: b.name for b in armature.data.bones}
    return {semantic: by_name[name] for semantic, name in MAPS[rig_family].items() if name in by_name}


def skeleton_height(armature, mapping):
    head = armature.data.bones[mapping["head"]].head_local
    feet = [armature.data.bones[mapping[name]].head_local for name in ("foot_l", "foot_r")]
    arm_matrix = armature.matrix_world.to_3x3()
    return max(1e-6, ((arm_matrix @ head) - sum((arm_matrix @ p for p in feet), Vector()) / 2).length)


def mesh_bounds(meshes, depsgraph):
    points = []
    for mesh in meshes:
        evaluated = mesh.evaluated_get(depsgraph)
        data = evaluated.to_mesh()
        try:
            points.extend(mesh.matrix_world @ vertex.co for vertex in data.vertices)
        finally:
            evaluated.to_mesh_clear()
    if not points:
        return None
    if any(not all(math.isfinite(value) for value in point) for point in points):
        raise RuntimeError("Non-finite evaluated mesh vertex")
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def assign_source_action(source_arm, action):
    if not source_arm.animation_data:
        source_arm.animation_data_create()
    source_arm.animation_data.action = action
    if getattr(action, "slots", None):
        source_arm.animation_data.action_slot = action.slots[0]


def find_action(actions, query):
    exact = [a for a in actions if a.name == query]
    candidates = exact or [a for a in actions if query.lower() in a.name.lower()]
    if len(candidates) != 1:
        raise RuntimeError(f"Action query {query!r} resolved to {[a.name for a in candidates]}")
    return candidates[0]


def aim(object_, target):
    object_.rotation_euler = (Vector(target) - object_.location).to_track_quat("-Z", "Y").to_euler()


def render_probe(scene, meshes, output_dir, frames):
    ground = bpy.data.meshes.new("ProbeGroundMesh")
    ground_obj = bpy.data.objects.new("ProbeGround", ground)
    bpy.context.collection.objects.link(ground_obj)
    vertices = [(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)]
    ground.from_pydata(vertices, [], [(0, 1, 2, 3)])
    material = bpy.data.materials.new("ProbeGroundMaterial")
    material.diffuse_color = (0.08, 0.08, 0.08, 1)
    ground_obj.data.materials.append(material)
    camera_data = bpy.data.cameras.new("ProbeCamera")
    camera = bpy.data.objects.new("ProbeCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (3.8, -5.8, 2.5)
    aim(camera, (0, 0, 0.95))
    camera_data.lens = 62
    scene.camera = camera
    key_data = bpy.data.lights.new("ProbeKey", "AREA")
    key_data.energy = 1000
    key_data.shape = "DISK"
    key_data.size = 4
    key = bpy.data.objects.new("ProbeKey", key_data)
    bpy.context.collection.objects.link(key)
    key.location = (3, -4, 6)
    aim(key, (0, 0, 1))
    fill_data = bpy.data.lights.new("ProbeFill", "AREA")
    fill_data.energy = 700
    fill_data.size = 3
    fill = bpy.data.objects.new("ProbeFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-3, -1, 3)
    aim(fill, (0, 0, 1))
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("ProbeWorld")
    scene.world.color = (0.025, 0.025, 0.025)
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = []
    for index, frame in enumerate(frames):
        scene.frame_set(frame)
        output = output_dir / f"frame-{index + 1:02d}-{frame:04d}.png"
        scene.render.filepath = str(output)
        bpy.ops.render.render(write_still=True)
        outputs.append(str(output))
    return outputs


def main():
    split = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--action", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--no-render", action="store_true")
    parser.add_argument("--export-usdc", action="store_true")
    args = parser.parse_args(sys.argv[split + 1:])

    bpy.ops.wm.open_mainfile(filepath=str(args.target))
    target_arm = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    target_meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    target_family = family({bone.name for bone in target_arm.data.bones})
    target_map = lookup(target_arm, target_family)
    before_objects = set(bpy.data.objects.keys())
    before_actions = set(bpy.data.actions.keys())
    bpy.ops.import_scene.fbx(filepath=str(args.source))
    imported = [obj for obj in bpy.data.objects if obj.name not in before_objects]
    source_arm = next(obj for obj in imported if obj.type == "ARMATURE")
    source_actions = [action for action in bpy.data.actions if action.name not in before_actions]
    source_action = find_action(source_actions, args.action)
    source_family = family({bone.name for bone in source_arm.data.bones})
    source_map = lookup(source_arm, source_family)
    common = [semantic for semantic in MAPS["mixamo"] if semantic in source_map and semantic in target_map]
    required = {"hips", "spine_lower", "spine_upper", "neck", "head", "upper_arm_l", "lower_arm_l", "hand_l", "upper_arm_r", "lower_arm_r", "hand_r", "upper_leg_l", "lower_leg_l", "foot_l", "upper_leg_r", "lower_leg_r", "foot_r"}
    missing = sorted(required - set(common))
    if missing:
        raise RuntimeError(f"Missing required semantic bones: {missing}")
    assign_source_action(source_arm, source_action)
    if not target_arm.animation_data:
        target_arm.animation_data_create()
    target_arm.animation_data.action = None
    baked = bpy.data.actions.new(f"Probe_{source_action.name}")
    target_arm.animation_data.action = baked
    frame_start = int(math.floor(source_action.frame_range[0]))
    frame_end = int(math.ceil(source_action.frame_range[1]))
    scene = bpy.context.scene
    source_height = skeleton_height(source_arm, source_map)
    target_height = skeleton_height(target_arm, target_map)
    height_scale = target_height / source_height
    scene.frame_set(frame_start)
    source_hips = source_arm.pose.bones[source_map["hips"]]
    first_hips_armature = source_hips.matrix.translation.copy()

    source_rest_rotations = {
        semantic: source_arm.data.bones[source_map[semantic]].matrix_local.to_quaternion().normalized()
        for semantic in common
    }
    target_rest_rotations = {
        semantic: target_arm.data.bones[target_map[semantic]].matrix_local.to_quaternion().normalized()
        for semantic in common
    }
    source_arm_world_rotation = source_arm.matrix_world.to_quaternion().normalized()
    target_arm_world_rotation = target_arm.matrix_world.to_quaternion().normalized()
    def depth(semantic):
        bone = target_arm.data.bones[target_map[semantic]]
        value = 0
        while bone.parent:
            value += 1
            bone = bone.parent
        return value
    ordered_semantics = sorted(common, key=depth)

    for frame in range(frame_start, frame_end + 1):
        scene.frame_set(frame)
        for pose_bone in target_arm.pose.bones:
            pose_bone.matrix_basis = Matrix.Identity(4)
        for semantic in ordered_semantics:
            source_pose = source_arm.pose.bones[source_map[semantic]]
            target_pose = target_arm.pose.bones[target_map[semantic]]
            source_global_world = (source_arm_world_rotation @ source_pose.matrix.to_quaternion()).normalized()
            source_rest_world = (source_arm_world_rotation @ source_rest_rotations[semantic]).normalized()
            target_rest_world = (target_arm_world_rotation @ target_rest_rotations[semantic]).normalized()
            target_rotation_world = (
                target_rest_world @ source_rest_world.inverted() @ source_global_world
            ).normalized()
            target_rotation = (target_arm_world_rotation.inverted() @ target_rotation_world).normalized()
            translation = target_pose.matrix.translation.copy()
            target_pose.matrix = Matrix.Translation(translation) @ target_rotation.to_matrix().to_4x4()
            target_pose.rotation_mode = "QUATERNION"
            target_pose.keyframe_insert("rotation_quaternion", frame=frame, group=target_pose.name)
            target_pose.keyframe_insert("location", frame=frame, group=target_pose.name)

    # Remove every imported object: only the baked target action is allowed to survive.
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    scene.frame_start = frame_start
    scene.frame_end = frame_end
    sample_frames = sorted({frame_start, frame_start + (frame_end - frame_start) // 4, frame_start + (frame_end - frame_start) // 2, frame_start + 3 * (frame_end - frame_start) // 4, frame_end})
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bounds = []
    foot_heights = []
    for frame in sample_frames:
        scene.frame_set(frame)
        depsgraph.update()
        minimum, maximum = mesh_bounds(target_meshes, depsgraph)
        bounds.append({"frame": frame, "min": list(minimum), "max": list(maximum), "size": list(maximum - minimum)})
        foot_heights.append({
            "frame": frame,
            "left": (target_arm.matrix_world @ target_arm.pose.bones[target_map["foot_l"]].matrix.translation).z,
            "right": (target_arm.matrix_world @ target_arm.pose.bones[target_map["foot_r"]].matrix.translation).z,
        })
    maximum_extent = max(max(row["size"]) for row in bounds)
    result = {
        "target": str(args.target), "source": str(args.source), "sourceFamily": source_family,
        "action": source_action.name, "frameStart": frame_start, "frameEnd": frame_end,
        "mappedSemanticCount": len(common), "mappedSemantics": common,
        "sourceHeight": source_height, "targetHeight": target_height, "heightScale": height_scale,
        "sampleBounds": bounds, "sampleFootHeights": foot_heights,
        "maximumMeshExtent": maximum_extent,
        "geometryFinite": True, "explodedGeometry": maximum_extent > 5.0,
    }
    result["renders"] = [] if args.no_render else render_probe(scene, target_meshes, args.output, sample_frames)
    args.output.mkdir(parents=True, exist_ok=True)
    if args.export_usdc:
        exported = args.output / "probe.usdc"
        bpy.ops.wm.usd_export(
            filepath=str(exported), export_animation=True, export_armatures=True,
            export_materials=True, generate_preview_surface=True,
            convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
            export_global_up_selection="Y",
        )
        result["exportedUSDC"] = str(exported)
    (args.output / "probe.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("RETARGET_PROBE=" + json.dumps(result))


if __name__ == "__main__":
    main()
