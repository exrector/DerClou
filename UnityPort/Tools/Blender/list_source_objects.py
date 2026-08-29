import bpy
SOURCE="/Users/exrector/Downloads/character.fbx"
bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=SOURCE)
for o in bpy.data.objects:
 print("SRC_OBJ",o.name,o.type, len(o.data.vertices) if o.type=="MESH" else "", len(o.data.bones) if o.type=="ARMATURE" else "")
