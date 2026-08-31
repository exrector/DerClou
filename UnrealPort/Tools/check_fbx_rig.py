"""Report what rig a raw FBX actually carries, before wasting time importing it.

Fab listings routinely promise a "game-engine compatible humanoid skeleton"
and ship a Blender Rigify rig instead, which needs a full IK Retargeter per
character rather than Unreal's free Compatible Skeletons path.

Handles FBX, USD/USDZ, glTF/GLB and OBJ, because Fab and Sketchfab hand out
whichever of those they feel like for the same character.

Usage:
  /Applications/Blender.app/Contents/MacOS/Blender -b -P check_fbx_rig.py -- <file>
"""
import bpy, sys

EPIC_CORE = ["root", "pelvis", "spine_01", "clavicle_l", "upperarm_l",
             "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l",
             "neck_01", "head"]

src = sys.argv[sys.argv.index('--') + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)

ext = src.lower().rsplit('.', 1)[-1]
if ext == 'fbx':
    bpy.ops.import_scene.fbx(filepath=src)
elif ext in ('usd', 'usda', 'usdc', 'usdz'):
    bpy.ops.wm.usd_import(filepath=src)
elif ext in ('glb', 'gltf'):
    bpy.ops.import_scene.gltf(filepath=src)
elif ext == 'obj':
    bpy.ops.wm.obj_import(filepath=src)
else:
    print(f"неизвестное расширение: {ext}")
    raise SystemExit

meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
arms = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
print(f"\nмешей: {len(meshes)}   арматур: {len(arms)}")
if len(meshes) > 6:
    print("  ! много отдельных кусков — проверь, не развалена ли сборка")

if not arms:
    print("РИГА НЕТ — это статичная модель, не персонаж")
    raise SystemExit

bones = [b.name for b in arms[0].data.bones]
lower = {b.lower() for b in bones}
hits = [c for c in EPIC_CORE if c in lower]
print(f"костей: {len(bones)}")
print(f"ядро Epic: {len(hits)}/{len(EPIC_CORE)}")

if len(hits) == len(EPIC_CORE):
    print("ГОДЕН: имена Epic. Хватит Compatible Skeletons, ретаргетер не нужен.")
else:
    # Naming the actual scheme saves guessing at what the retarget source is.
    # Numbered bones ("n44", "Bone_012", "joint7") mean the exporter threw the
    # original names away. That is worse than a foreign naming scheme: an IK
    # Retargeter still has to be told which bone is the pelvis, and there is
    # nothing left to tell it with short of clicking each one in the viewport.
    import re as _re
    numbered = sum(1 for b in bones if _re.fullmatch(r"(n|bone|joint|node)[_-]?\d+", b.lower()))
    if numbered > len(bones) * 0.5:
        print(f"НЕ ГОДЕН: {numbered} из {len(bones)} костей — безымянные номера.")
        print("Ретаргетер настроить нечем; кость-таз пришлось бы искать вручную.")
        print("первые кости:", bones[:12])
        raise SystemExit

    scheme = ("Blender Rigify" if any(b.startswith("f_index") or b == "spine.001" for b in bones)
              else "Mixamo" if any("mixamorig" in b.lower() for b in bones)
              else "3ds Max Biped" if any(b.lower().startswith("bip01") for b in bones)
              else "Maya HumanIK / Mixamo-подобная" if any(b in ("Hips", "hips") for b in bones)
              else "неизвестная")
    print(f"НЕ ГОДЕН напрямую: схема костей — {scheme}.")
    print("Нужен IK Retargeter на каждого такого персонажа.")
    print("первые кости:", bones[:12])
