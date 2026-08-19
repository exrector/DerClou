#!/usr/bin/env python3
"""
DerClou Custom Procedural 3D Character Generator
Builds a stylized, rigged, animated heist operator matching the game's art direction.
Features distinct front/back visual landmarks (visor, collar, belt buckle, backpack)
and correctly oriented forward locomotion (+Z in RealityKit / USD).
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
    # 1. Materials (PBR Heist Aesthetic)
    # ----------------------------------------------------
    def create_pbr_material(name, base_color, roughness=0.6, metallic=0.0):
        mat = bpy.data.materials.new(name=name)
        if hasattr(mat, "use_nodes"):
            mat.use_nodes = True
            nodes = mat.node_tree.nodes
            bsdf = nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = base_color
                bsdf.inputs["Roughness"].default_value = roughness
                bsdf.inputs["Metallic"].default_value = metallic
        return mat

    mat_jacket = create_pbr_material("Mat_Jacket", (0.10, 0.12, 0.16, 1.0), roughness=0.8, metallic=0.0)
    mat_shirt = create_pbr_material("Mat_Shirt", (0.85, 0.85, 0.88, 1.0), roughness=0.9, metallic=0.0)
    mat_pants = create_pbr_material("Mat_Pants", (0.07, 0.08, 0.10, 1.0), roughness=0.9, metallic=0.0)
    mat_boots = create_pbr_material("Mat_Boots", (0.04, 0.03, 0.03, 1.0), roughness=0.35, metallic=0.05)
    mat_gloves = create_pbr_material("Mat_Gloves", (0.03, 0.03, 0.04, 1.0), roughness=0.4, metallic=0.0)
    mat_skin = create_pbr_material("Mat_Skin", (0.82, 0.65, 0.54, 1.0), roughness=0.55, metallic=0.0)
    mat_hair = create_pbr_material("Mat_Hair", (0.08, 0.06, 0.04, 1.0), roughness=0.85, metallic=0.0)
    mat_belt = create_pbr_material("Mat_Belt", (0.02, 0.02, 0.02, 1.0), roughness=0.3, metallic=0.2)
    mat_buckle = create_pbr_material("Mat_Buckle", (0.80, 0.82, 0.85, 1.0), roughness=0.2, metallic=1.0)
    mat_visor = create_pbr_material("Mat_Visor", (0.05, 0.75, 0.90, 1.0), roughness=0.1, metallic=0.8)
    mat_backpack = create_pbr_material("Mat_Backpack", (0.18, 0.15, 0.12, 1.0), roughness=0.7, metallic=0.0)

    # ----------------------------------------------------
    # 2. Armature (Oriented so Front = -Y in Blender -> +Z in USD)
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

    # Left Arm
    add_bone("Shoulder_L", (0.05, 0, 1.44), (0.18, 0, 1.42), "Chest")
    add_bone("UpperArm_L", (0.18, 0, 1.42), (0.19, -0.01, 1.14), "Shoulder_L")
    add_bone("Forearm_L", (0.19, -0.01, 1.14), (0.20, -0.03, 0.88), "UpperArm_L")
    add_bone("Hand_L", (0.20, -0.03, 0.88), (0.20, -0.04, 0.76), "Forearm_L")

    # Right Arm
    add_bone("Shoulder_R", (-0.05, 0, 1.44), (-0.18, 0, 1.42), "Chest")
    add_bone("UpperArm_R", (-0.18, 0, 1.42), (-0.19, -0.01, 1.14), "Shoulder_R")
    add_bone("Forearm_R", (-0.19, -0.01, 1.14), (-0.20, -0.03, 0.88), "UpperArm_R")
    add_bone("Hand_R", (-0.20, -0.03, 0.88), (-0.20, -0.04, 0.76), "Forearm_R")

    # Legs (Feet pointing forward towards -Y)
    add_bone("Thigh_L", (0.11, 0, 0.90), (0.11, 0, 0.50), "Hips")
    add_bone("Shin_L", (0.11, 0, 0.50), (0.11, 0, 0.12), "Thigh_L")
    add_bone("Foot_L", (0.11, 0, 0.12), (0.11, -0.16, 0.0), "Shin_L")

    add_bone("Thigh_R", (-0.11, 0, 0.90), (-0.11, 0, 0.50), "Hips")
    add_bone("Shin_R", (-0.11, 0, 0.50), (-0.11, 0, 0.12), "Thigh_R")
    add_bone("Foot_R", (-0.11, 0, 0.12), (-0.11, -0.16, 0.0), "Shin_R")

    bpy.ops.object.mode_set(mode="OBJECT")

    # ----------------------------------------------------
    # 3. Geometry Construction with Distinct Front & Back
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

    # FRONT DETAIL: Light shirt opening on front chest (-Y)
    make_primitive("Shirt_Front", "box", (0, -0.112, 1.40), (0.12, 0.01, 0.16), mat_shirt, "Chest")

    # FRONT DETAIL: Metallic belt buckle on front waist (-Y)
    make_primitive("Belt_Buckle", "box", (0, -0.11, 0.90), (0.07, 0.02, 0.07), mat_buckle, "Hips")

    # BACK DETAIL: Tactical backpack on back (+Y)
    make_primitive("Backpack", "box", (0, 0.14, 1.34), (0.24, 0.10, 0.28), mat_backpack, "Chest")

    # Head & Neck
    make_primitive("Neck_Mesh", "cylinder", (0, 0, 1.52), (0.12, 0.12, 0.10), mat_skin, "Neck")
    make_primitive("Head_Mesh", "sphere", (0, 0, 1.66), (0.20, 0.22, 0.22), mat_skin, "Head")

    # FRONT DETAIL: Tactical Visor / Goggles on front of face (-Y)
    make_primitive("Face_Visor", "box", (0, -0.105, 1.67), (0.16, 0.04, 0.06), mat_visor, "Head")

    # BACK DETAIL: Hair on top and back of head (+Y)
    make_primitive("Hair_Mesh", "sphere", (0, 0.04, 1.70), (0.22, 0.22, 0.18), mat_hair, "Head")

    # Arms Left
    make_primitive("UpperArm_L_Mesh", "cylinder", (0.185, 0, 1.28), (0.09, 0.09, 0.28), mat_jacket, "UpperArm_L")
    make_primitive("Forearm_L_Mesh", "cylinder", (0.195, -0.015, 1.01), (0.08, 0.08, 0.26), mat_jacket, "Forearm_L")
    make_primitive("Hand_L_Mesh", "box", (0.20, -0.03, 0.82), (0.07, 0.09, 0.12), mat_gloves, "Hand_L")

    # Arms Right
    make_primitive("UpperArm_R_Mesh", "cylinder", (-0.185, 0, 1.28), (0.09, 0.09, 0.28), mat_jacket, "UpperArm_R")
    make_primitive("Forearm_R_Mesh", "cylinder", (-0.195, -0.015, 1.01), (0.08, 0.08, 0.26), mat_jacket, "Forearm_R")
    make_primitive("Hand_R_Mesh", "box", (-0.20, -0.03, 0.82), (0.07, 0.09, 0.12), mat_gloves, "Hand_R")

    # Legs Left (Toes extending forward towards -Y)
    make_primitive("Thigh_L_Mesh", "cylinder", (0.11, 0, 0.70), (0.13, 0.13, 0.38), mat_pants, "Thigh_L")
    make_primitive("Shin_L_Mesh", "cylinder", (0.11, 0, 0.31), (0.11, 0.11, 0.38), mat_pants, "Shin_L")
    make_primitive("Foot_L_Mesh", "box", (0.11, -0.06, 0.06), (0.11, 0.24, 0.12), mat_boots, "Foot_L")

    # Legs Right (Toes extending forward towards -Y)
    make_primitive("Thigh_R_Mesh", "cylinder", (-0.11, 0, 0.70), (0.13, 0.13, 0.38), mat_pants, "Thigh_R")
    make_primitive("Shin_R_Mesh", "cylinder", (-0.11, 0, 0.31), (0.11, 0.11, 0.38), mat_pants, "Shin_R")
    make_primitive("Foot_R_Mesh", "box", (-0.11, -0.06, 0.06), (0.11, 0.24, 0.12), mat_boots, "Foot_R")

    # Join meshes into single character object
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_parts[0]
    bpy.ops.object.join()

    char_mesh = bpy.context.active_object
    char_mesh.name = "Thief_Mesh"

    # Parent mesh to armature
    mod = char_mesh.modifiers.new(name="ArmatureModifier", type="ARMATURE")
    mod.object = arm_obj
    char_mesh.parent = arm_obj

    # ----------------------------------------------------
    # 4. Natural Forward Locomotion Walk Animation
    # ----------------------------------------------------
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    pose_bones = arm_obj.pose.bones
    for b in pose_bones:
        b.rotation_mode = "XYZ"

    # --- ACTION: Walk (Natural 30-frame seamless loop @ 30fps) ---
    walk_action = bpy.data.actions.new("Walk")
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = walk_action

    # Walk cycle keyframes
    # In Blender bone coordinates with -Y forward:
    # A negative rotation_euler[0] tilts the thigh forward towards -Y (forward step).
    # A positive rotation_euler[0] bends the knee backward towards +Y.
    for f in range(1, 31):
        phase = ((f - 1) / 30.0) * math.pi * 2

        # 1. Legs (stride forward towards -Y)
        # leg_l < 0 = forward step
        leg_l = -math.sin(phase) * 24.0
        leg_r = -leg_l

        # Knee bending: bends backward (+X rotation) during recovery swing
        knee_l = max(0.0, math.sin(phase) * 42.0)
        knee_r = max(0.0, -math.sin(phase) * 42.0)

        # Foot roll (heel strike -> flat -> toe push)
        foot_l = -math.sin(phase) * 15.0
        foot_r = -foot_l

        pose_bones["Thigh_L"].rotation_euler = (math.radians(leg_l), 0, 0)
        pose_bones["Thigh_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Shin_L"].rotation_euler = (math.radians(knee_l), 0, 0)
        pose_bones["Shin_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Foot_L"].rotation_euler = (math.radians(foot_l), 0, 0)
        pose_bones["Foot_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Thigh_R"].rotation_euler = (math.radians(leg_r), 0, 0)
        pose_bones["Thigh_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Shin_R"].rotation_euler = (math.radians(knee_r), 0, 0)
        pose_bones["Shin_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Foot_R"].rotation_euler = (math.radians(foot_r), 0, 0)
        pose_bones["Foot_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        # 2. Arms (Natural swing with arms hanging down)
        # Left arm swings forward when Right leg steps forward
        arm_l_swing = math.sin(phase) * 16.0
        arm_r_swing = -arm_l_swing

        # Natural elbow flex on forward swing
        elbow_l = max(0.0, math.sin(phase) * 12.0) + 4.0
        elbow_r = max(0.0, -math.sin(phase) * 12.0) + 4.0

        pose_bones["UpperArm_L"].rotation_euler = (math.radians(arm_l_swing), 0, 0)
        pose_bones["UpperArm_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Forearm_L"].rotation_euler = (math.radians(-elbow_l), 0, 0)
        pose_bones["Forearm_L"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["UpperArm_R"].rotation_euler = (math.radians(arm_r_swing), 0, 0)
        pose_bones["UpperArm_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Forearm_R"].rotation_euler = (math.radians(-elbow_r), 0, 0)
        pose_bones["Forearm_R"].keyframe_insert(data_path="rotation_euler", frame=f)

        # 3. Torso / Pelvis
        pelvis_yaw = math.sin(phase) * 2.5
        chest_yaw = -pelvis_yaw
        pelvis_bounce = -math.cos(phase * 2) * 0.015

        pose_bones["Hips"].location = (0, 0, pelvis_bounce)
        pose_bones["Hips"].keyframe_insert(data_path="location", frame=f)

        pose_bones["Hips"].rotation_euler = (0, math.radians(pelvis_yaw), 0)
        pose_bones["Hips"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Chest"].rotation_euler = (0, math.radians(chest_yaw), 0)
        pose_bones["Chest"].keyframe_insert(data_path="rotation_euler", frame=f)

        pose_bones["Head"].rotation_euler = (0, math.radians(pelvis_yaw * 0.5), 0)
        pose_bones["Head"].keyframe_insert(data_path="rotation_euler", frame=f)

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
        generate_preview_surface=True,
        # Without this, Blender exports its own native Z-up data verbatim and
        # just tags the file `upAxis = "Z"` for whoever reads it to sort out —
        # it does not rotate anything itself. RealityKit's USDZ pipeline
        # handles that correctly for a plain static mesh, but not reliably
        # for a *skinned/animated* SkelRoot: the bind pose and animation
        # channels stay in Z-up numbers while the visual mesh ends up
        # Y-up-ish, so the skeleton and the geometry disagree about which way
        # is "up" — this is what produced the floating, bunched-looking
        # character in-game even though every bone and mesh coordinate in
        # Blender itself was correctly grounded at Z=0. Forcing the
        # conversion here bakes Y-up into the actual exported numbers, so
        # there is nothing left for the consumer to get wrong.
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y"
    )
    print(f"Exported USDZ to: {output_usdz_path}")

if __name__ == "__main__":
    usdz_out = "/Users/exrector/Documents/PROJECTS/DerClou/Packages/HeistEngine/Sources/HeistKit/Resources/Characters/thief.usdz"
    blend_out = "/Users/exrector/Documents/PROJECTS/DerClou/ArtSource/Characters/Thief/thief.blend"
    build_character(usdz_out, blend_out)
