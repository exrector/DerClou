import bpy
import os


PROJECT = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort"
TARGET_FBX = os.path.join(
    PROJECT,
    "Assets/Free Interaction Animation/Assets/Meshes/VoxelVision_Default_Charcter.fbx",
)
SOURCE_FBX = "/Users/exrector/Downloads/character.fbx"
OUTPUT_DIR = os.path.join(PROJECT, "Assets/External_Motorcyclist_Generic")
OUTPUT_FBX = os.path.join(OUTPUT_DIR, "Motorcyclist_Generic.fbx")


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return list(set(bpy.data.objects) - before)


def first(objects, object_type, preferred_name=None):
    matches = [obj for obj in objects if obj.type == object_type]
    if preferred_name:
        preferred = next((obj for obj in matches if obj.name == preferred_name), None)
        if preferred:
            return preferred
    if not matches:
        raise RuntimeError(f"No {object_type} object found")
    return matches[0]


def apply_modifier(obj, modifier):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def mapped_bones():
    mapping = {
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
    side_map = {"Left": "l", "Right": "r"}
    finger_map = {
        "Thumb": "thumb",
        "Index": "index",
        "Middle": "middle",
        "Ring": "ring",
        "Pinky": "pinky",
    }
    for mixamo_side, epic_side in side_map.items():
        for mixamo_finger, epic_finger in finger_map.items():
            for index in range(1, 4):
                mapping[f"mixamorig6:{mixamo_side}Hand{mixamo_finger}{index}"] = (
                    f"{epic_finger}_{index:02d}_{epic_side}"
                )
    return mapping


def pose_source_like_target(source_armature, target_armature):
    for source_name, target_name in mapped_bones().items():
        source_bone = source_armature.pose.bones.get(source_name)
        target_bone = target_armature.pose.bones.get(target_name)
        if source_bone is None or target_bone is None:
            continue
        constraint = source_bone.constraints.new(type="COPY_ROTATION")
        constraint.name = "DerClou_TargetRestRotation"
        constraint.target = target_armature
        constraint.subtarget = target_name
        constraint.target_space = "WORLD"
        constraint.owner_space = "WORLD"
        constraint.mix_mode = "REPLACE"
    bpy.context.view_layer.update()


def bake_source_pose(source_mesh, source_armature):
    armature_modifier = next(
        (modifier for modifier in source_mesh.modifiers if modifier.type == "ARMATURE"),
        None,
    )
    if armature_modifier is None:
        raise RuntimeError("Motorcyclist mesh has no source armature modifier")
    apply_modifier(source_mesh, armature_modifier)
    source_mesh.matrix_world = source_mesh.matrix_world.copy()
    for pose_bone in source_armature.pose.bones:
        for constraint in list(pose_bone.constraints):
            pose_bone.constraints.remove(constraint)


def transfer_target_weights(source_mesh, target_mesh, target_armature):
    source_mesh.vertex_groups.clear()
    for group in target_mesh.vertex_groups:
        source_mesh.vertex_groups.new(name=group.name)

    transfer = source_mesh.modifiers.new("DerClou_TransferEpicWeights", "DATA_TRANSFER")
    transfer.object = target_mesh
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    transfer.mix_mode = "REPLACE"
    transfer.mix_factor = 1.0
    apply_modifier(source_mesh, transfer)

    armature_modifier = source_mesh.modifiers.new("DerClou_EpicSkeleton", "ARMATURE")
    armature_modifier.object = target_armature
    source_mesh.parent = target_armature
    source_mesh.matrix_parent_inverse = target_armature.matrix_world.inverted()


def remove_object(obj):
    if obj and obj.name in bpy.data.objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    target_objects = import_fbx(TARGET_FBX)
    target_armature = first(target_objects, "ARMATURE", "root")
    target_mesh = first(target_objects, "MESH", "SKM_VoxelVision")

    source_objects = import_fbx(SOURCE_FBX)
    source_armature = first(source_objects, "ARMATURE", "Armature")
    source_mesh = first(source_objects, "MESH", "Ch20")

    pose_source_like_target(source_armature, target_armature)
    bake_source_pose(source_mesh, source_armature)
    transfer_target_weights(source_mesh, target_mesh, target_armature)

    source_mesh.name = "Motorcyclist_Body"
    target_armature.name = "root"
    target_armature.data.name = "Motorcyclist_EpicSkeleton"
    target_armature.animation_data_clear()

    for obj in list(bpy.data.objects):
        if obj not in {source_mesh, target_armature}:
            remove_object(obj)

    bpy.ops.object.select_all(action="DESELECT")
    source_mesh.select_set(True)
    target_armature.select_set(True)
    bpy.context.view_layer.objects.active = target_armature

    bpy.ops.export_scene.fbx(
        filepath=OUTPUT_FBX,
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        add_leaf_bones=False,
        bake_anim=False,
        use_armature_deform_only=False,
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
    )
    print(f"DERCLOU_OUTPUT={OUTPUT_FBX}")
    print(f"DERCLOU_VERTICES={len(source_mesh.data.vertices)}")
    print(f"DERCLOU_BONES={len(target_armature.data.bones)}")
    print(f"DERCLOU_GROUPS={len(source_mesh.vertex_groups)}")


if __name__ == "__main__":
    main()
