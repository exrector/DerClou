import bpy
import os

PROJECT = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort"
POSE_FBX = os.path.join(PROJECT, "Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx")
SOURCE_FBX = "/Users/exrector/Downloads/character.fbx"
OUT_DIR = os.path.join(PROJECT, "Assets/External_Motorcyclist_AutoRig")
OUT_FBX = os.path.join(OUT_DIR, "Motorcyclist_Epic_AutoWeights.fbx")

def import_fbx(path):
    before = set(bpy.data.objects); bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before]

bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete(use_global=False)
target_objects = import_fbx(POSE_FBX)
target = next(o for o in target_objects if o.type == "ARMATURE")
target.data.pose_position = "REST"
source_objects = import_fbx(SOURCE_FBX)
source_arm = next(o for o in source_objects if o.type == "ARMATURE")
source_mesh = next(o for o in source_objects if o.type == "MESH")

# Both imported rigs are in their bind/T pose. Let Blender compute actual
# surface weights against the Epic skeleton instead of guessing group names.
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
source_mesh.select_set(True); target.select_set(True); bpy.context.view_layer.objects.active = target
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

if source_arm.name in bpy.data.objects:
    bpy.data.objects.remove(source_arm, do_unlink=True)
target.data.pose_position = "POSE"
if target.animation_data and target.animation_data.action:
    bpy.context.scene.frame_set(round(sum(target.animation_data.action.frame_range) * 0.5))
bpy.context.view_layer.update()

for obj in list(bpy.data.objects):
    if obj not in {target, source_mesh}:
        bpy.data.objects.remove(obj, do_unlink=True)
os.makedirs(OUT_DIR, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT"); target.select_set(True); source_mesh.select_set(True); bpy.context.view_layer.objects.active = target
bpy.ops.export_scene.fbx(filepath=OUT_FBX, use_selection=True, object_types={"ARMATURE", "MESH"}, apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False, bake_anim=True, bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
    bake_anim_simplify_factor=0.0, use_armature_deform_only=False, mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True)
print(f"DERCLOU_OUTPUT={OUT_FBX}")
print(f"DERCLOU_BONES={len(target.data.bones)}")
print(f"DERCLOU_GROUPS={len(source_mesh.vertex_groups)}")
