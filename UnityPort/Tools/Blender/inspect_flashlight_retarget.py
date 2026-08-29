import bpy
import json


TARGET = "/Users/exrector/Documents/PROJECTS/DerClou/UnityPort/Assets/DerClou/CharacterReview/A_Flashlight_Idle_01_R_EpicGeneric.fbx"
SOURCE = "/Users/exrector/Downloads/character.fbx"


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def import_group(path, prefix):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    objects = list(set(bpy.data.objects) - before)
    for obj in objects:
        obj.name = f"{prefix}_{obj.name}"
    return objects


def armature_summary(objects):
    armature = next(obj for obj in objects if obj.type == "ARMATURE")
    action = armature.animation_data.action if armature.animation_data else None
    return {
        "object": armature.name,
        "matrix": [list(row) for row in armature.matrix_world],
        "bones": [bone.name for bone in armature.data.bones],
        "action": action.name if action else None,
        "frame_range": list(action.frame_range) if action else None,
    }


reset()
target = import_group(TARGET, "TARGET")
source = import_group(SOURCE, "SOURCE")
print("DERCLOU_RETARGET_INSPECT=" + json.dumps({
    "target": armature_summary(target),
    "source": armature_summary(source),
}, ensure_ascii=False))
