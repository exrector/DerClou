import bpy, sys, os, math

def fcurves_of(ac):
    if hasattr(ac,"fcurves"):
        return list(ac.fcurves)
    out=[]
    for layer in getattr(ac,"layers",[]):
        for strip in getattr(layer,"strips",[]):
            for cb in getattr(strip,"channelbags",[]):
                out.extend(cb.fcurves)
    return out

def bone_of(fc):
    return fc.data_path.split('"')[1] if 'pose.bones[' in fc.data_path else None

args=sys.argv[sys.argv.index("--")+1:]
BODY, ARM, OUT = args[0], args[1], args[2]

# ---- 1. тело: оно и станет основой файла
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=BODY)
body_arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
body_act=body_arm.animation_data.action
body_fcs=fcurves_of(body_act)
body_bones={b.name for b in body_arm.data.bones}
bf0,bf1=body_act.frame_range
print(f"тело: {body_arm.name}, костей {len(body_bones)}, кадры {bf0:.0f}..{bf1:.0f}, кривых {len(body_fcs)}")

# ---- 2. рука: читаем во ВТОРУЮ сцену, чтобы не смешать арматуры
before={o.name for o in bpy.data.objects}
bpy.ops.import_scene.fbx(filepath=ARM)
arm_obj=[o for o in bpy.data.objects if o.type=='ARMATURE' and o.name not in before][0]
arm_act=arm_obj.animation_data.action
arm_fcs=fcurves_of(arm_act)
af0,af1=arm_act.frame_range
print(f"рука: {arm_obj.name}, кадры {af0:.0f}..{af1:.0f}, кривых {len(arm_fcs)}")

# ---- 3. какие кости переносим: вся правая рука от ключицы + правые пальцы
def is_target(name):
    n=name.lower()
    if not n.endswith("_r"): return False
    if any(k in n for k in ("clavicle","upperarm","lowerarm","hand")): return True
    if any(k in n for k in ("index","middle","ring","pinky","thumb")): return True
    return False
targets={b for b in body_bones if is_target(b)}
print("костей-целей в теле:",len(targets))

src={}
for fc in arm_fcs:
    b=bone_of(fc)
    if b in targets:
        src[(b,fc.data_path,fc.array_index)]=fc
print("кривых-источников найдено:",len(src))

# ---- 4. перенос: время растягиваем из диапазона руки в диапазон тела
def remap(f):
    if af1==af0: return bf0
    return bf0 + (f-af0)*(bf1-bf0)/(af1-af0)

replaced=0; added=0
body_by_key={(bone_of(fc),fc.data_path,fc.array_index):fc for fc in body_fcs}
for key,sfc in src.items():
    tfc=body_by_key.get(key)
    if tfc is None:
        added+=1
        continue
    # стереть старые ключи и переложить исходные
    while len(tfc.keyframe_points):
        tfc.keyframe_points.remove(tfc.keyframe_points[0], fast=True)
    pts=sorted(sfc.keyframe_points, key=lambda k:k.co[0])
    tfc.keyframe_points.add(len(pts))
    for i,kp in enumerate(pts):
        tfc.keyframe_points[i].co = (remap(kp.co[0]), kp.co[1])
        tfc.keyframe_points[i].interpolation='LINEAR'
    tfc.update()
    replaced+=1
print(f"кривых заменено: {replaced}, без пары в теле: {added}")

# ---- 5. убрать арматуру руки и выгнать FBX
bpy.data.objects.remove(arm_obj, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = body_arm
bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True,
    add_leaf_bones=False, bake_anim=True, bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=True, armature_nodetype='NULL',
    object_types={'ARMATURE','MESH'})
print("записан:",OUT, os.path.getsize(OUT),"байт")

# Запуск:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
#     --python Tools/merge_arm_onto_body.py -- <тело.fbx> <рука.fbx> <выход.fbx>
#
# Зачем: анимации фонаря в паке FPFlashlightAnims импортированы в Unreal на
# скелет рук от первого лица, у которого нет ног. Но СЫРОЙ FBX содержит полный
# скелет (160 костей) с ключами на всех, включая ноги и таз — обрезка произошла
# только при импорте. Скрипт берёт тело от одной анимации и правую руку от
# другой, сопоставляя кости по именам, и пишет обычный FBX.
#
# Переносится вся правая рука от ключицы плюс правые пальцы (22 кости).
# Время источника растягивается в диапазон тела, поэтому длины могут не совпадать.
