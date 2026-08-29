import bpy
import os
from mathutils import Matrix


PROJECT = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort"
POSE_FBX = os.path.join(
    PROJECT,
    "Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx",
)
CHARACTER_FBX = "/Users/exrector/Downloads/character.fbx"
OUTPUT_DIR = os.path.join(PROJECT, "Assets/External_Motorcyclist_Pose")
OUTPUT_FBX = os.path.join(OUTPUT_DIR, "Motorcyclist_FlashlightPose.fbx")


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return list(set(bpy.data.objects) - before)


def find_armature(objects, required_bone):
    return next(
        obj for obj in objects
        if obj.type == "ARMATURE" and required_bone in obj.data.bones
    )


def bone_map():
    result = {
        "mixamorig6:Hips": "pelvis",
        "mixamorig6:Spine": "spine_01",
        "mixamorig6:Spine1": "spine_03",
        "mixamorig6:Spine2": "spine_05",
        "mixamorig6:Neck": "neck_01",
        "mixamorig6:Head": "head",
        "mixamorig6:LeftShoulder": "clavicle_l",
        "mixamorig6:LeftArm": "upperarm_l",
        "mixamorig6:LeftForeArm": "lowerarm_l",
        "mixamorig6:LeftHand": "hand_l",
        "mixamorig6:RightShoulder": "clavicle_r",
        "mixamorig6:RightArm": "upperarm_r",
        "mixamorig6:RightForeArm": "lowerarm_r",
        "mixamorig6:RightHand": "hand_r",
        "mixamorig6:LeftUpLeg": "thigh_l",
        "mixamorig6:LeftLeg": "calf_l",
        "mixamorig6:LeftFoot": "foot_l",
        "mixamorig6:LeftToeBase": "ball_l",
        "mixamorig6:RightUpLeg": "thigh_r",
        "mixamorig6:RightLeg": "calf_r",
        "mixamorig6:RightFoot": "foot_r",
        "mixamorig6:RightToeBase": "ball_r",
    }
    for source_side, target_side in (("Left", "l"), ("Right", "r")):
        for source_finger, target_finger in (
            ("Thumb", "thumb"),
            ("Index", "index"),
            ("Middle", "middle"),
            ("Ring", "ring"),
            ("Pinky", "pinky"),
        ):
            for index in range(1, 4):
                result[f"mixamorig6:{source_side}Hand{source_finger}{index}"] = (
                    f"{target_finger}_{index:02d}_{target_side}"
                )
    return result


def rotation_matrix(quaternion):
    return quaternion.normalized().to_matrix().to_4x4()


def apply_rest_relative_pose(source, target, sample_frame):
    bpy.context.scene.frame_set(sample_frame)
    bpy.context.view_layer.update()

    for pose_bone in source.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()

    mapping = bone_map()
    ordered = sorted(
        mapping.items(),
        key=lambda pair: len(source.data.bones[pair[0]].parent_recursive),
    )

    for source_name, target_name in ordered:
        source_pose = source.pose.bones.get(source_name)
        target_pose = target.pose.bones.get(target_name)
        if source_pose is None or target_pose is None:
            continue

        target_rest_world = target.matrix_world @ target.data.bones[target_name].matrix_local
        target_pose_world = target.matrix_world @ target_pose.matrix
        target_delta = (
            target_pose_world.to_quaternion()
            @ target_rest_world.to_quaternion().inverted()
        )

        source_rest_world = source.matrix_world @ source.data.bones[source_name].matrix_local
        desired_rotation = target_delta @ source_rest_world.to_quaternion()

        current_world = source.matrix_world @ source_pose.matrix
        desired_world = Matrix.Translation(current_world.translation) @ rotation_matrix(desired_rotation)
        source_pose.matrix = source.matrix_world.inverted() @ desired_world
        bpy.context.view_layer.update()


def create_static_action(source):
    action = bpy.data.actions.new("Motorcyclist_FlashlightPose")
    source.animation_data_create()
    source.animation_data.action = action
    for frame in (1, 2):
        bpy.context.scene.frame_set(frame)
        for pose_bone in source.pose.bones:
            pose_bone.rotation_mode = "QUATERNION"
            pose_bone.keyframe_insert("location", frame=frame, group=pose_bone.name)
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=pose_bone.name)
            pose_bone.keyframe_insert("scale", frame=frame, group=pose_bone.name)
    action.frame_start = 1
    action.frame_end = 2
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 2


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    target_objects = import_fbx(POSE_FBX)
    target = find_armature(target_objects, "hand_r")
    source_objects = import_fbx(CHARACTER_FBX)
    source = find_armature(source_objects, "mixamorig6:RightHand")
    source_meshes = [obj for obj in source_objects if obj.type == "MESH"]
    if not source_meshes:
        raise RuntimeError("Motorcyclist FBX contains no mesh")

    target_action = target.animation_data.action
    sample_frame = round(sum(target_action.frame_range) * 0.5)
    apply_rest_relative_pose(source, target, sample_frame)
    create_static_action(source)

    keep = {source, *source_meshes}
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)

    source.name = "Motorcyclist_Armature"
    for mesh in source_meshes:
        mesh.name = "Motorcyclist_Body"

    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    for mesh in source_meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = source

    bpy.ops.export_scene.fbx(
        filepath=OUTPUT_FBX,
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True,
        bake_anim_simplify_factor=0.0,
        use_armature_deform_only=False,
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
    )
    print(f"DERCLOU_OUTPUT={OUTPUT_FBX}")
    print(f"DERCLOU_SAMPLE_FRAME={sample_frame}")
    print(f"DERCLOU_SOURCE_BONES={len(source.data.bones)}")
    print(f"DERCLOU_SOURCE_MESHES={len(source_meshes)}")


if __name__ == "__main__":
    main()
