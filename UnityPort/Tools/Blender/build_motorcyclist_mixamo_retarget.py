import bpy
import os

PROJECT = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort"
POSE_FBX = os.path.join(PROJECT, "Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx")
SOURCE_FBX = "/Users/exrector/Downloads/character.fbx"
OUTPUT_DIR = os.path.join(PROJECT, "Assets/External_Motorcyclist_Retargeted")
OUTPUT_FBX = os.path.join(OUTPUT_DIR, "Motorcyclist_Flashlight_Mixamo.fbx")

def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return list(set(bpy.data.objects) - before)

def mapping():
    m = {
        "mixamorig6:Hips": "pelvis", "mixamorig6:Spine": "spine_01", "mixamorig6:Spine1": "spine_03", "mixamorig6:Spine2": "spine_05",
        "mixamorig6:Neck": "neck_01", "mixamorig6:Head": "head", "mixamorig6:LeftShoulder": "clavicle_l", "mixamorig6:LeftArm": "upperarm_l",
        "mixamorig6:LeftForeArm": "lowerarm_l", "mixamorig6:LeftHand": "hand_l", "mixamorig6:RightShoulder": "clavicle_r", "mixamorig6:RightArm": "upperarm_r",
        "mixamorig6:RightForeArm": "lowerarm_r", "mixamorig6:RightHand": "hand_r", "mixamorig6:LeftUpLeg": "thigh_l", "mixamorig6:LeftLeg": "calf_l",
        "mixamorig6:LeftFoot": "foot_l", "mixamorig6:LeftToeBase": "ball_l", "mixamorig6:RightUpLeg": "thigh_r", "mixamorig6:RightLeg": "calf_r",
        "mixamorig6:RightFoot": "foot_r", "mixamorig6:RightToeBase": "ball_r",
    }
    for side, s in (("Left", "l"), ("Right", "r")):
        for finger, f in (("Thumb", "thumb"), ("Index", "index"), ("Middle", "middle"), ("Ring", "ring"), ("Pinky", "pinky")):
            for i in range(1, 4):
                m[f"mixamorig6:{side}Hand{finger}{i}"] = f"{f}_{i:02d}_{s}"
    return m

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    target_objects = import_fbx(POSE_FBX)
    target = next(o for o in target_objects if o.type == "ARMATURE")
    source_objects = import_fbx(SOURCE_FBX)
    source = next(o for o in source_objects if o.type == "ARMATURE")
    meshes = [o for o in source_objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("Motorcyclist mesh missing")
    action = target.animation_data.action
    if action is None:
        raise RuntimeError("Flashlight action missing")

    # Native Mixamo mesh and armature stay together. Constraints only copy the
    # authored pose; no mesh weights or bind matrices are touched.
    for source_name, target_name in mapping().items():
        source_bone = source.pose.bones.get(source_name)
        target_bone = target.pose.bones.get(target_name)
        if source_bone is None or target_bone is None:
            continue
        constraint = source_bone.constraints.new("COPY_ROTATION")
        constraint.name = "DerClou_FlashlightRetarget"
        constraint.target = target
        constraint.subtarget = target_name
        constraint.target_space = "WORLD"
        constraint.owner_space = "WORLD"
        constraint.mix_mode = "REPLACE"

    bpy.context.scene.frame_start = int(action.frame_range[0])
    bpy.context.scene.frame_end = int(action.frame_range[1])
    bpy.context.scene.frame_set(bpy.context.scene.frame_start)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.nla.bake(frame_start=bpy.context.scene.frame_start, frame_end=bpy.context.scene.frame_end,
        only_selected=False, visual_keying=True, clear_constraints=True, clear_parents=False,
        use_current_action=True, bake_types={"POSE"})

    for obj in list(bpy.data.objects):
        if obj not in {source, *meshes}:
            bpy.data.objects.remove(obj, do_unlink=True)
    source.name = "Motorcyclist_Mixamo_Armature"
    for mesh in meshes:
        mesh.name = "Motorcyclist_Body"
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.export_scene.fbx(filepath=OUTPUT_FBX, use_selection=True, object_types={"ARMATURE", "MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False,
        bake_anim=True, bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
        bake_anim_simplify_factor=0.0, use_armature_deform_only=False, mesh_smooth_type="FACE",
        path_mode="COPY", embed_textures=True)
    print(f"DERCLOU_OUTPUT={OUTPUT_FBX}")
    print(f"DERCLOU_BONES={len(source.data.bones)}")
    print(f"DERCLOU_ACTION={source.animation_data.action.name if source.animation_data and source.animation_data.action else 'none'}")

if __name__ == "__main__":
    main()
