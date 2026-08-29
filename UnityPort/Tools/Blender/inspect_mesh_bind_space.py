import bpy
import json

TARGET = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort/Assets/Free Interaction Animation/Assets/Meshes/VoxelVision_Default_Charcter.fbx"
SOURCE = "/Users/exrector/Downloads/character.fbx"

def bounds(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    return {"min": mn, "max": mx, "size": [mx[i] - mn[i] for i in range(3)]}

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
b = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=TARGET)
target = [o for o in bpy.data.objects if o not in b]
b = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=SOURCE)
source = [o for o in bpy.data.objects if o not in b]
data = {}
for group, objs in (("target", target), ("source", source)):
    arm = next(o for o in objs if o.type == "ARMATURE")
    mesh = next(o for o in objs if o.type == "MESH")
    arm_inv = arm.matrix_world.inverted()
    arm_points = [arm_inv @ (mesh.matrix_world @ v.co) for v in mesh.data.vertices]
    data[group] = {
        "armature_matrix": [list(r) for r in arm.matrix_world],
        "mesh_matrix": [list(r) for r in mesh.matrix_world],
        "mesh_bounds_world": bounds(mesh),
        "mesh_bounds_armature": {
            "min": [min(p[i] for p in arm_points) for i in range(3)],
            "max": [max(p[i] for p in arm_points) for i in range(3)],
        },
    }
print("DERCLOU_BIND_SPACE=" + json.dumps(data))
