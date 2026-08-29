import bpy
import os
from mathutils import Vector, Matrix

PROJECT = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort"
POSE_FBX = os.path.join(PROJECT, "Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx")
SOURCE_FBX = "/Users/exrector/Downloads/character.fbx"
OUTPUT_DIR = os.path.join(PROJECT, "Assets/External_Motorcyclist_HandPose")
OUTPUT_FBX = os.path.join(OUTPUT_DIR, "Motorcyclist_Flashlight_HandPose.fbx")

def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return list(set(bpy.data.objects) - before)

def world_rest(arm, name):
    return arm.matrix_world @ arm.data.bones[name].matrix_local

def world_pose(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].matrix

def set_world_rotation(arm, pose_bone, rotation):
    current = world_pose(arm, pose_bone.name)
    desired = Matrix.Translation(current.translation) @ rotation.normalized().to_matrix().to_4x4()
    pose_bone.matrix = arm.matrix_world.inverted() @ desired
    bpy.context.view_layer.update()

def map_fingers():
    result = {}
    for side, s in (("Right", "r"),):
        for finger, f in (("Thumb", "thumb"), ("Index", "index"), ("Middle", "middle"), ("Ring", "ring"), ("Pinky", "pinky")):
            for i in range(1, 4):
                result[f"mixamorig6:{side}Hand{finger}{i}"] = f"{f}_{i:02d}_{s}"
    return result

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    target_objects = import_fbx(POSE_FBX)
    target = next(o for o in target_objects if o.type == "ARMATURE")
    source_objects = import_fbx(SOURCE_FBX)
    source = next(o for o in source_objects if o.type == "ARMATURE")
    meshes = [o for o in source_objects if o.type == "MESH"]
    action = target.animation_data.action
    sample = round(sum(action.frame_range) * 0.5)
    bpy.context.scene.frame_set(sample)
    bpy.context.view_layer.update()

    # Native Mixamo mesh remains untouched. Solve only the visible right arm.
    shoulder = source.pose.bones["mixamorig6:RightArm"]
    forearm = source.pose.bones["mixamorig6:RightForeArm"]
    hand = source.pose.bones["mixamorig6:RightHand"]
    source_shoulder = world_pose(source, shoulder.name).translation
    target_elbow = world_pose(target, "lowerarm_r").translation
    target_wrist = world_pose(target, "hand_r").translation

    source_upper_rest = world_rest(source, shoulder.name)
    upper_rest_dir = (source_upper_rest.to_translation() - source.matrix_world @ source.data.bones[shoulder.name].head_local)
    upper_rest_dir = (source.matrix_world.to_3x3() @ upper_rest_dir).normalized()
    desired_upper_dir = (target_elbow - source_shoulder).normalized()
    set_world_rotation(source, shoulder, desired_upper_dir.rotation_difference(upper_rest_dir).inverted() @ world_rest(source, shoulder.name).to_quaternion())

    current_elbow = world_pose(source, forearm.name).translation
    lower_rest = world_rest(source, forearm.name)
    lower_rest_dir = (lower_rest.to_translation() - source.matrix_world @ source.data.bones[forearm.name].head_local)
    lower_rest_dir = (source.matrix_world.to_3x3() @ lower_rest_dir).normalized()
    desired_lower_dir = (target_wrist - current_elbow).normalized()
    set_world_rotation(source, forearm, desired_lower_dir.rotation_difference(lower_rest_dir).inverted() @ world_rest(source, forearm.name).to_quaternion())

    # Match the authored wrist orientation relative to the target hand.
    source_hand_rest_rot = world_rest(source, hand.name).to_quaternion()
    target_hand_rest_rot = world_rest(target, "hand_r").to_quaternion()
    target_hand_pose_rot = world_pose(target, "hand_r").to_quaternion()
    target_delta = target_hand_pose_rot @ target_hand_rest_rot.inverted()
    set_world_rotation(source, hand, target_delta @ source_hand_rest_rot)

    # Copy only local finger bend, preserving the Mixamo finger axes.
    for source_name, target_name in map_fingers().items():
        sb = source.pose.bones.get(source_name)
        tb = target.pose.bones.get(target_name)
        if sb is None or tb is None:
            continue
        sb.rotation_mode = "QUATERNION"
        sb.rotation_quaternion = tb.matrix_basis.to_quaternion()

    # For the acceptance artifact we bake the authored pose into the native
    # motorcyclist mesh. This is intentionally static: it cannot disturb the
    # source bind matrices and gives an honest visual check of the hand.
    modifier = next((m for m in meshes[0].modifiers if m.type == "ARMATURE" and m.object == source), None)
    if modifier is None:
        raise RuntimeError("Motorcyclist mesh has no source armature modifier")
    bpy.context.scene.frame_set(sample)
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    meshes[0].select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    socket = bpy.data.objects.new("FlashlightSocket", None)
    bpy.context.collection.objects.link(socket)
    socket.matrix_world = world_pose(source, "mixamorig6:RightHand")
    for obj in list(bpy.data.objects):
        if obj not in {source, *meshes, socket}:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    socket.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.export_scene.fbx(filepath=OUTPUT_FBX, use_selection=True, object_types={"EMPTY", "MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False,
        bake_anim=False, bake_anim_use_all_bones=False, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
        bake_anim_simplify_factor=0.0, use_armature_deform_only=False, mesh_smooth_type="FACE",
        path_mode="COPY", embed_textures=True)
    print(f"DERCLOU_OUTPUT={OUTPUT_FBX}")
    print(f"DERCLOU_SAMPLE={sample}")
    print(f"DERCLOU_BONES={len(source.data.bones)}")

if __name__ == "__main__":
    main()
