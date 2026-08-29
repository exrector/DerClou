import bpy
import os

PROJECT = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort"
POSE_FBX = os.path.join(PROJECT, "Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx")
SOURCE_FBX = "/Users/exrector/Downloads/character.fbx"
OUTPUT_DIR = os.path.join(PROJECT, "Assets/External_Motorcyclist_Epic")
OUTPUT_FBX = os.path.join(OUTPUT_DIR, "Motorcyclist_Epic_Flashlight.fbx")

def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return list(set(bpy.data.objects) - before)

def map_groups():
    m = {
        "Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_03", "Spine2": "spine_05",
        "Neck": "neck_01", "Head": "head", "LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l",
        "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l", "RightShoulder": "clavicle_r", "RightArm": "upperarm_r",
        "RightForeArm": "lowerarm_r", "RightHand": "hand_r", "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l",
        "LeftFoot": "foot_l", "LeftToeBase": "ball_l", "RightUpLeg": "thigh_r", "RightLeg": "calf_r",
        "RightFoot": "foot_r", "RightToeBase": "ball_r",
    }
    for side, s in (("Left", "l"), ("Right", "r")):
        for finger, f in (("Thumb", "thumb"), ("Index", "index"), ("Middle", "middle"), ("Ring", "ring"), ("Pinky", "pinky")):
            for i in range(1, 5):
                m[f"{side}Hand{finger}{i}"] = f"{f}_{min(i, 3):02d}_{s}"
    return m

def remap_vertex_groups(mesh, target_armature):
    mapping = map_groups()
    target_names = {b.name for b in target_armature.data.bones}
    for group in list(mesh.vertex_groups):
        short = group.name.split(":", 1)[-1]
        target_name = mapping.get(short)
        if target_name not in target_names:
            mesh.vertex_groups.remove(group)
            continue
        existing = mesh.vertex_groups.get(target_name)
        if existing is not None and existing != group:
            for vertex in mesh.data.vertices:
                for weight in vertex.groups:
                    if weight.group == group.index:
                        existing.add([vertex.index], weight.weight, "ADD")
            mesh.vertex_groups.remove(group)
        else:
            group.name = target_name

def apply_source_bind_pose(mesh, source_armature):
    bpy.context.scene.frame_set(0)
    source_armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    modifier = next((m for m in mesh.modifiers if m.type == "ARMATURE" and m.object == source_armature), None)
    if modifier is None:
        raise RuntimeError("Motorcyclist mesh has no source armature modifier")
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.modifier_apply(modifier=modifier.name)

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    target_objects = import_fbx(POSE_FBX)
    target_armature = next(o for o in target_objects if o.type == "ARMATURE")
    source_objects = import_fbx(SOURCE_FBX)
    source_armature = next(o for o in source_objects if o.type == "ARMATURE")
    source_mesh = next(o for o in source_objects if o.type == "MESH")
    target_action = target_armature.animation_data.action
    if target_action is None:
        raise RuntimeError("Flashlight pose FBX has no action")

    apply_source_bind_pose(source_mesh, source_armature)
    remap_vertex_groups(source_mesh, target_armature)
    modifier = source_mesh.modifiers.new("EpicSkeletonDeform", "ARMATURE")
    modifier.object = target_armature
    source_mesh.parent = target_armature
    source_mesh.matrix_parent_inverse = target_armature.matrix_world.inverted()
    target_armature.name = "Motorcyclist_Epic_Armature"
    target_armature.data.name = "EpicSkeleton"
    source_mesh.name = "Motorcyclist_Body"
    target_armature.animation_data.action = target_action

    for obj in list(bpy.data.objects):
        if obj not in {target_armature, source_mesh}:
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.context.scene.frame_set(round(sum(target_action.frame_range) * 0.5))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    target_armature.select_set(True)
    source_mesh.select_set(True)
    bpy.context.view_layer.objects.active = target_armature
    bpy.ops.export_scene.fbx(filepath=OUTPUT_FBX, use_selection=True, object_types={"ARMATURE", "MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False,
        bake_anim=True, bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
        bake_anim_simplify_factor=0.0, use_armature_deform_only=False, mesh_smooth_type="FACE",
        path_mode="COPY", embed_textures=True)
    print(f"DERCLOU_OUTPUT={OUTPUT_FBX}")
    print(f"DERCLOU_BONES={len(target_armature.data.bones)}")
    print(f"DERCLOU_GROUPS={len(source_mesh.vertex_groups)}")
    print(f"DERCLOU_ACTION={target_action.name}")

if __name__ == "__main__":
    main()
