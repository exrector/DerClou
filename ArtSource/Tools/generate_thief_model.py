#!/usr/bin/env python3
"""
DerClou Custom Procedural 3D Character Generator
Builds a stylized, rigged, animated heist operator matching the game's art direction.
Exports both .blend source and runtime .usdz.
"""

import bpy
import math
import os
import sys

def build_character(output_usdz_path, output_blend_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30

    # ----------------------------------------------------
    # 1. Materials
    # ----------------------------------------------------
    def create_pbr_material(name, base_color, roughness=0.6, metallic=0.0):
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = base_color
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = metallic
        return mat

    mat_jacket = create_pbr_material("Mat_Jacket", (0.12, 0.14, 0.18, 1.0), roughness=0.8, metallic=0.0)
    mat_pants = create_pbr_material("Mat_Pants", (0.08, 0.09, 0.11, 1.0), roughness=0.9, metallic=0.0)
    mat_boots = create_pbr_material("Mat_Boots", (0.05, 0.04, 0.04, 1.0), roughness=0.35, metallic=0.05)
    mat_gloves = create_pbr_material("Mat_Gloves", (0.04, 0.04, 0.05, 1.0), roughness=0.4, metallic=0.0)
    mat_skin = create_pbr_material("Mat_Skin", (0.82, 0.65, 0.54, 1.0), roughness=0.55, metallic=0.0)
    mat_hair = create_pbr_material("Mat_Hair", (0.10, 0.08, 0.06, 1.0), roughness=0.85, metallic=0.0)
    mat_belt = create_pbr_material("Mat_Belt", (0.03, 0.03, 0.03, 1.0), roughness=0.3, metallic=0.2)

    # ----------------------------------------------------
    # 2. Armature
    # ----------------------------------------------------
    arm_data = bpy.data.armatures.new("ThiefArmature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def add_bone(name, head, tail, parent_name=None):
        b = arm_data.edit_bones.new(name)
        b.head = head
        b.tail = tail
        if parent_name and parent_name in bones:
            b.parent = bones[parent_name]
        bones[name] = b
        return b

    # Spine
    add_bone("Hips", (0, 0, 0.90), (0, 0, 1.08))
    add_bone("Spine", (0, 0, 1.08), (0, 0, 1.28), "Hips")
    add_bone("Chest", (0, 0, 1.28), (0, 0, 1.48), "Spine")
    add_bone("Neck", (0, 0, 1.48), (0, 0, 1.56), "Chest")
    add_bone("Head", (0, 0, 1.56), (0, 0, 1.76), "Neck")

    # Arms
    add_bone("Shoulder_L", (0.05, 0, 1.44), (0.16, 0, 1.44), "Chest")
    add_bone("UpperArm_L", (0.16, 0, 1.44), (0.38, 0, 1.44), "Shoulder_L")
    add_bone("Forearm_L", (0.38, 0, 1.44), (0.58, 0, 1.44), "UpperArm_L")
    add_bone("Hand_L", (0.58, 0, 1.44), (0.70, 0, 1.44), "Forearm_L")

    add_bone("Shoulder_R", (-0.05, 0, 1.44), (-0.16, 0, 1.44), "Chest")
    add_bone("UpperArm_R", (-0.16, 0, 1.44), (-0.38, 0, 1.44), "Shoulder_R")
    add_bone("Forearm_R", (-0.38, 0, 1.44), (-0.58, 0, 1.44), "UpperArm_R")
    add_bone("Hand_R", (-0.58, 0, 1.44), (-0.70, 0, 1.44), "Forearm_R")

    # Legs
    add_bone("Thigh_L", (0.11, 0, 0.90), (0.11, 0, 0.50), "Hips")
    add_bone("Shin_L", (0.11, 0, 0.50), (0.11, 0, 0.12), "Thigh_L")
    add_bone("Foot_L", (0.11, 0, 0.12), (0.11, 0.16, 0.0), "Shin_L")

    add_bone("Thigh_R", (-0.11, 0, 0.90), (-0.11, 0, 0.50), "Hips")
    add_bone("Shin_R", (-0.11, 0, 0.50), (-0.11, 0, 0.12), "Thigh_R")
    add_bone("Foot_R", (-0.11, 0, 0.12), (-0.11, 0.16, 0.0), "Shin_R")

    bpy.ops.object.mode_set(mode="OBJECT")

    # ----------------------------------------------------
    # 3. Geometry Construction
    # ----------------------------------------------------
    mesh_parts = []

    def make_primitive(name, mesh_type, location, scale, material, vertex_group_name):
        if mesh_type == "box":
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
        elif mesh_type == "cylinder":
            bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.0, vertices=16, location=location)
        elif mesh_type == "sphere":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=16, ring_count=12, location=location)

        obj = bpy.context.active_object
        obj.name = name
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.data.materials.append(material)

        # Assign vertex group
        vg = obj.vertex_groups.new(name=vertex_group_name)
        vg.add(range(len(obj.data.vertices)), 1.0, "REPLACE")

        mesh_parts.append(obj)
        return obj

    # Torso & Jacket
    make_primitive("Torso_Chest", "box", (0, 0, 1.38), (0.34, 0.22, 0.24), mat_jacket, "Chest")
    make_primitive("Torso_Spine", "box", (0, 0, 1.18), (0.30, 0.20, 0.20), mat_jacket, "Spine")
    make_primitive("Torso_Hips", "box", (0, 0, 0.98), (0.31, 0.20, 0.18), mat_jacket, "Hips")
    make_primitive("Belt", "box", (0, 0, 0.90), (0.32, 0.21, 0.06), mat_belt, "Hips")

    # Head & Neck
    make_primitive("Neck_Mesh", "cylinder", (0, 0, 1.52), (0.12, 0.12, 0.10), mat_skin, "Neck")
    make_primitive("Head_Mesh", "sphere", (0, 0, 1.66), (0.20, 0.22, 0.22), mat_skin, "Head")
    make_primitive("Hair_Mesh", "sphere", (0, -0.02, 1.70), (0.22, 0.24, 0.18), mat_hair, "Head")

    # Arms Left
    make_primitive("UpperArm_L_Mesh", "cylinder", (0.27, 0, 1.44), (0.11, 0.11, 0.22), mat_jacket, "UpperArm_L")
    bpy.context.active_object.rotation_euler = (0, math.radians(90), 0)
    bpy.ops.object.transform_apply(rotation=True)

    make_primitive("Forearm_L_Mesh", "cylinder", (0.48, 0, 1.44), (0.09, 0.09, 0.20), mat_jacket, "Forearm_L")
    bpy.context.active_object.rotation_euler = (0, math.radians(90), 0)
    bpy.ops.object.transform_apply(rotation=True)

    make_primitive("Hand_L_Mesh", "box", (0.64, 0, 1.44), (0.10, 0.08, 0.06), mat_gloves, "Hand_L")

    # Arms Right
    make_primitive("UpperArm_R_Mesh", "cylinder", (-0.27, 0, 1.44), (0.11, 0.11, 0.22), mat_jacket, "UpperArm_R")
    bpy.context.active_object.rotation_euler = (0, math.radians(-90), 0)
    bpy.ops.object.transform_apply(rotation=True)

    make_primitive("Forearm_R_Mesh", "cylinder", (-0.48, 0, 1.44), (0.09, 0.09, 0.20), mat_jacket, "Forearm_R")
    bpy.context.active_object.rotation_euler = (0, math.radians(-90), 0)
    bpy.ops.object.transform_apply(rotation=True)

    make_primitive("Hand_R_Mesh", "box", (-0.64, 0, 1.44), (0.10, 0.08, 0.06), mat_gloves, "Hand_R")

    # Legs Left
    make_primitive("Thigh_L_Mesh", "cylinder", (0.11, 0, 0.70), (0.13, 0.13, 0.38), mat_pants, "Thigh_L")
    make_primitive("Shin_L_Mesh", "cylinder", (0.11, 0, 0.31), (0.11, 0.11, 0.38), mat_pants, "Shin_L")
    make_primitive("Foot_L_Mesh", "box", (0.11, 0.06, 0.06), (0.11, 0.24, 0.12), mat_boots, "Foot_L")

    # Legs Right
    make_primitive("Thigh_R_Mesh", "cylinder", (-0.11, 0, 0.70), (0.13, 0.13, 0.38), mat_pants, "Thigh_R")
    make_primitive("Shin_R_Mesh", "cylinder", (-0.11, 0, 0.31), (0.11, 0.11, 0.38), mat_pants, "Shin_R")
    make_primitive("Foot_R_Mesh", "box", (-0.11, 0.06, 0.06), (0.11, 0.24, 0.12), mat_boots, "Foot_R")

    # Join meshes into single character object
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_parts[0]
    bpy.ops.object.join()

    char_mesh = bpy.context.active_object
    char_mesh.name = "Thief_Mesh"

    # Parent mesh to armature with armature modifier
    mod = char_mesh.modifiers.new(name="ArmatureModifier", type="ARMATURE")
    mod.object = arm_obj
    char_mesh.parent = arm_obj

    # ----------------------------------------------------
    # 4. Animation Baking (Idle & Walk)
    # ----------------------------------------------------
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    # Neutral pose arms down slightly
    arm_obj.pose.bones["UpperArm_L"].rotation_mode = "XYZ"
    arm_obj.pose.bones["UpperArm_R"].rotation_mode = "XYZ"
    arm_obj.pose.bones["Forearm_L"].rotation_mode = "XYZ"
    arm_obj.pose.bones["Forearm_R"].rotation_mode = "XYZ"

    arm_obj.pose.bones["UpperArm_L"].rotation_euler = (0, 0, math.radians(-65))
    arm_obj.pose.bones["UpperArm_R"].rotation_euler = (0, 0, math.radians(65))

    # --- ACTION 1: Idle (30 frames) ---
    idle_action = bpy.data.actions.new("Idle")
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = idle_action

    for f in [1, 15, 30]:
        t = (f - 1) / 29.0
        breath = math.sin(t * math.pi * 2)

        # Chest breath
        arm_obj.pose.bones["Chest"].rotation_mode = "XYZ"
        arm_obj.pose.bones["Chest"].rotation_euler = (math.radians(breath * 1.5), 0, 0)
        arm_obj.pose.bones["Chest"].keyframe_insert(data_path="rotation_euler", frame=f)

        # Head slight tilt
        arm_obj.pose.bones["Head"].rotation_mode = "XYZ"
        arm_obj.pose.bones["Head"].rotation_euler = (math.radians(breath * -0.8), math.radians(breath * 1.0), 0)
        arm_obj.pose.bones["Head"].keyframe_insert(data_path="rotation_euler", frame=f)

        # Arms subtle sway
        arm_obj.pose.bones["UpperArm_L"].rotation_euler = (math.radians(breath * 2.0), 0, math.radians(-65 + breath * 1.0))
        arm_obj.pose.bones["UpperArm_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        arm_obj.pose.bones["UpperArm_R"].rotation_euler = (math.radians(breath * -2.0), 0, math.radians(65 - breath * 1.0))
        arm_obj.pose.bones["UpperArm_R"].keyframe_insert(data_path="rotation_euler", frame=f)

    # --- ACTION 2: Walk (30 frames loop) ---
    walk_action = bpy.data.actions.new("Walk")
    arm_obj.animation_data.action = walk_action

    pose_bones = arm_obj.pose.bones
    for name in ["Hips", "Chest", "Thigh_L", "Shin_L", "Foot_L", "Thigh_R", "Shin_R", "Foot_R", "UpperArm_L", "UpperArm_R"]:
        pose_bones[name].rotation_mode = "XYZ"

    frames = list(range(1, 31))
    for f in frames:
        phase = ((f - 1) / 30.0) * math.pi * 2

        # Legs swing
        leg_l_angle = math.sin(phase) * 28.0
        leg_r_angle = -leg_l_angle

        # Knee bend (only bends backwards when leg moves back)
        knee_l = max(0, -math.sin(phase) * 35.0)
        knee_r = max(0, math.sin(phase) * 35.0)

        # Arms counter swing
        arm_l_angle = -math.sin(phase) * 22.0
        arm_r_angle = -arm_l_angle

        # Hips vertical bounce and yaw
        hips_yaw = math.sin(phase) * 3.0
        chest_yaw = -hips_yaw

        pose_bones["Thigh_L"].rotation_euler = (math.radians(leg_l_angle), 0, 0)
        pose_bones["Thigh_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Shin_L"].rotation_euler = (math.radians(-knee_l), 0, 0)
        pose_bones["Shin_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Thigh_R"].rotation_euler = (math.radians(leg_r_angle), 0, 0)
        pose_bones["Thigh_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Shin_R"].rotation_euler = (math.radians(-knee_r), 0, 0)
        pose_bones["Shin_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["UpperArm_L"].rotation_euler = (math.radians(arm_l_angle), 0, math.radians(-65))
        pose_bones["UpperArm_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["UpperArm_R"].rotation_euler = (math.radians(arm_r_angle), 0, math.radians(65))
        pose_bones["UpperArm_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Hips"].rotation_euler = (0, math.radians(hips_yaw), 0)
        pose_bones["Hips"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Chest"].rotation_euler = (0, math.radians(chest_yaw), 0)
        pose_bones["Chest"].keyframe_insert(data_path="rotation_euler", frame=f)

    bpy.ops.object.mode_set(mode="OBJECT")

    # Save Blend file
    blend_dir = os.path.dirname(os.path.abspath(output_blend_path))
    if blend_dir:
        os.makedirs(blend_dir, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(output_blend_path))
    print(f"Saved blend file to: {output_blend_path}")

    # Export USDZ
    usdz_dir = os.path.dirname(os.path.abspath(output_usdz_path))
    if usdz_dir:
        os.makedirs(usdz_dir, exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=os.path.abspath(output_usdz_path),
        export_animation=True,
        export_armatures=True,
        export_materials=True,
        generate_preview_surface=True
    )
    print(f"Exported USDZ to: {output_usdz_path}")

if __name__ == "__main__":
    usdz_out = "/Users/exrector/Documents/PROJECTS/DerClou/Packages/HeistEngine/Sources/HeistKit/Resources/Characters/thief.usdz"
    blend_out = "/Users/exrector/Documents/PROJECTS/DerClou/ArtSource/Characters/Thief/thief.blend"
    build_character(usdz_out, blend_out)
