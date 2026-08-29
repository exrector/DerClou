import bpy, os, math
from mathutils import Matrix
PROJECT='/Users/exrector/Documents/PROJECTS/DerClou/UnityPort'
POSE_FBX=os.path.join(PROJECT,'Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx')
SRC='/Users/exrector/Downloads/character.fbx'
OUTDIR=os.path.join(PROJECT,'Assets/External_Motorcyclist_PoseMatrix')
OUT=os.path.join(OUTDIR,'Motorcyclist_Flashlight_PoseMatrix.fbx')
def imp(p):
 b=set(bpy.data.objects); bpy.ops.import_scene.fbx(filepath=p); return [o for o in bpy.data.objects if o not in b]
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
t=imp(POSE_FBX); ta=next(o for o in t if o.type=='ARMATURE'); ta.data.pose_position='POSE'
sa=imp(SRC); arm=next(o for o in sa if o.type=='ARMATURE'); mesh=next(o for o in sa if o.type=='MESH')
# select actual animation midpoint
if ta.animation_data and ta.animation_data.action:
 a=ta.animation_data.action; bpy.context.scene.frame_set(round((a.frame_range[0]+a.frame_range[1])*0.5))
bpy.context.view_layer.update()
# map by suffix after colon and exact names
src_by={b.name.split(':')[-1].lower():b for b in arm.data.bones}
tgt_by={b.name.split(':')[-1].lower():b for b in ta.data.bones}
# build target pose delta in armature space relative target rest, apply to source rest
for tb in ta.pose.bones:
 key=tb.name.split(':')[-1].lower(); sb=next((p for p in arm.pose.bones if p.name.split(':')[-1].lower()==key),None)
 if not sb: continue
 rest=tb.bone.matrix_local
 delta=tb.matrix @ rest.inverted()
 desired=delta @ sb.bone.matrix_local
 if sb.parent:
  parent_pose=arm.pose.bones.get(sb.parent.name)
  sb.matrix=desired
 else: sb.matrix=desired
bpy.context.view_layer.update()
# remove target and extras; keep source armature+mesh with its original weights
bpy.data.objects.remove(ta,do_unlink=True)
for o in list(bpy.data.objects):
 if o not in {arm,mesh}: bpy.data.objects.remove(o,do_unlink=True)
os.makedirs(OUTDIR,exist_ok=True)
bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); mesh.select_set(True); bpy.context.view_layer.objects.active=arm
bpy.ops.export_scene.fbx(filepath=OUT,use_selection=True,object_types={'ARMATURE','MESH'},apply_unit_scale=True,apply_scale_options='FBX_SCALE_ALL',add_leaf_bones=False,bake_anim=False,use_armature_deform_only=False,mesh_smooth_type='FACE',path_mode='COPY',embed_textures=True)
print('DERCLOU_OUTPUT='+OUT)
print('DERCLOU_SRC_BONES='+str(len(arm.data.bones)))
print('DERCLOU_GROUPS='+str(len(mesh.vertex_groups)))
