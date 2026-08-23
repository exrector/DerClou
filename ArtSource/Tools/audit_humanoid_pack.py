#!/usr/bin/env python3
"""Audit FBX humanoid compatibility against DerClou's Mixamo actors.

Run with Blender. The tool is read-only: it imports each FBX into a fresh scene,
inspects the actual armature/action data, and writes one NDJSON record per file.
It does not infer compatibility from filenames.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import traceback
from pathlib import Path

import bpy


SEMANTICS = (
    "hips", "spine_lower", "spine_mid", "spine_upper", "neck", "head",
    "shoulder_l", "upper_arm_l", "lower_arm_l", "hand_l",
    "shoulder_r", "upper_arm_r", "lower_arm_r", "hand_r",
    "upper_leg_l", "lower_leg_l", "foot_l", "toe_l",
    "upper_leg_r", "lower_leg_r", "foot_r", "toe_r",
)

CRITICAL = {
    "hips", "spine_lower", "spine_upper", "neck", "head",
    "upper_arm_l", "lower_arm_l", "hand_l",
    "upper_arm_r", "lower_arm_r", "hand_r",
    "upper_leg_l", "lower_leg_l", "foot_l",
    "upper_leg_r", "lower_leg_r", "foot_r",
}

MAPS = {
    "mixamo": {
        "hips": "Hips", "spine_lower": "Spine", "spine_mid": "Spine1",
        "spine_upper": "Spine2", "neck": "Neck", "head": "Head",
        "shoulder_l": "LeftShoulder", "upper_arm_l": "LeftArm",
        "lower_arm_l": "LeftForeArm", "hand_l": "LeftHand",
        "shoulder_r": "RightShoulder", "upper_arm_r": "RightArm",
        "lower_arm_r": "RightForeArm", "hand_r": "RightHand",
        "upper_leg_l": "LeftUpLeg", "lower_leg_l": "LeftLeg",
        "foot_l": "LeftFoot", "toe_l": "LeftToeBase",
        "upper_leg_r": "RightUpLeg", "lower_leg_r": "RightLeg",
        "foot_r": "RightFoot", "toe_r": "RightToeBase",
    },
    "quaternius": {
        "hips": "pelvis", "spine_lower": "spine_01", "spine_mid": "spine_02",
        "spine_upper": "spine_03", "neck": "neck_01", "head": "Head",
        "shoulder_l": "clavicle_l", "upper_arm_l": "upperarm_l",
        "lower_arm_l": "lowerarm_l", "hand_l": "hand_l",
        "shoulder_r": "clavicle_r", "upper_arm_r": "upperarm_r",
        "lower_arm_r": "lowerarm_r", "hand_r": "hand_r",
        "upper_leg_l": "thigh_l", "lower_leg_l": "calf_l",
        "foot_l": "foot_l", "toe_l": "ball_l",
        "upper_leg_r": "thigh_r", "lower_leg_r": "calf_r",
        "foot_r": "foot_r", "toe_r": "ball_r",
    },
    "cmu": {
        "hips": "hip", "spine_lower": "abdomen", "spine_upper": "chest",
        "neck": "neck", "head": "head",
        "shoulder_l": "lCollar", "upper_arm_l": "lShldr",
        "lower_arm_l": "lForeArm", "hand_l": "lHand",
        "shoulder_r": "rCollar", "upper_arm_r": "rShldr",
        "lower_arm_r": "rForeArm", "hand_r": "rHand",
        "upper_leg_l": "lThigh", "lower_leg_l": "lShin", "foot_l": "lFoot",
        "upper_leg_r": "rThigh", "lower_leg_r": "rShin", "foot_r": "rFoot",
    },
}


def action_curves(action):
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag:
                        yield from bag.fcurves
        return
    yield from getattr(action, "fcurves", ())


def mixamo_canonical(name: str) -> str:
    return re.sub(r"^mixamorig\d*:", "", name)


def family_for(bones: set[str]) -> str:
    canonical = {mixamo_canonical(name) for name in bones}
    if {"Hips", "LeftUpLeg", "RightUpLeg", "LeftArm", "RightArm"} <= canonical:
        return "mixamo"
    if {"pelvis", "thigh_l", "thigh_r", "upperarm_l", "upperarm_r"} <= bones:
        return "quaternius"
    if {"hip", "lThigh", "rThigh", "lShldr", "rShldr"} <= bones:
        return "cmu"
    return "unknown"


def semantic_bones(family: str, bones: set[str]) -> dict[str, str]:
    lookup = {mixamo_canonical(name): name for name in bones} if family == "mixamo" else {name: name for name in bones}
    return {
        semantic: lookup[source_name]
        for semantic, source_name in MAPS.get(family, {}).items()
        if source_name in lookup
    }


def skeleton_fingerprint(armature) -> str:
    rows = []
    for bone in armature.data.bones:
        name = mixamo_canonical(bone.name)
        parent = mixamo_canonical(bone.parent.name) if bone.parent else ""
        rows.append((name, parent))
    payload = json.dumps(sorted(rows), separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


def root_motion(action, armature, hips_name: str | None) -> dict:
    if not hips_name:
        return {"translationCurveCount": 0, "maxAxisSpan": 0.0, "nonFiniteValues": 0}
    translation = []
    nonfinite = 0
    for curve in action_curves(action):
        values = [point.co[1] for point in curve.keyframe_points]
        nonfinite += sum(not math.isfinite(value) for value in values)
        if hips_name in curve.data_path and curve.data_path.endswith("].location") and values:
            translation.append(max(values) - min(values))
    return {
        "translationCurveCount": len(translation),
        "maxAxisSpan": round(max(translation, default=0.0), 6),
        "nonFiniteValues": nonfinite,
    }


def audit(path: Path) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    objects = list(bpy.data.objects)
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    actions = list(bpy.data.actions)
    if len(armatures) != 1:
        return {
            "path": str(path), "status": "incompatible",
            "reason": f"expected-one-armature-got-{len(armatures)}",
            "armatureCount": len(armatures), "actionCount": len(actions),
        }
    armature = armatures[0]
    bones = {bone.name for bone in armature.data.bones}
    family = family_for(bones)
    mapped = semantic_bones(family, bones)
    missing = sorted(CRITICAL - set(mapped))
    direct_target = family == "mixamo" and not missing
    grade = "A-direct" if direct_target else ("B-retarget" if not missing else "D-incompatible")
    action_rows = []
    for action in actions:
        curves = list(action_curves(action))
        animated_paths = {curve.data_path for curve in curves}
        action_rows.append({
            "name": action.name,
            "frameStart": round(action.frame_range[0], 3),
            "frameEnd": round(action.frame_range[1], 3),
            "frameSpan": round(action.frame_range[1] - action.frame_range[0], 3),
            "curveCount": len(curves),
            "keyframeCount": sum(len(curve.keyframe_points) for curve in curves),
            "animatedPathCount": len(animated_paths),
            "rootMotion": root_motion(action, armature, mapped.get("hips")),
        })
    meshes = [obj for obj in objects if obj.type == "MESH"]
    return {
        "path": str(path), "status": "ok" if actions else "no-actions",
        "family": family, "compatibilityGrade": grade,
        "directBoneNameCompatibility": direct_target,
        "requiresRetargeting": grade == "B-retarget",
        "boneCount": len(bones), "mappedSemanticCount": len(mapped),
        "mappedSemantics": sorted(mapped), "missingCriticalSemantics": missing,
        "skeletonFingerprint": skeleton_fingerprint(armature),
        "meshCount": len(meshes), "cameraCount": sum(o.type == "CAMERA" for o in objects),
        "lightCount": sum(o.type == "LIGHT" for o in objects),
        "actionCount": len(actions), "actions": action_rows,
    }


def parse_args(argv: list[str]):
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--partition-index", type=int, default=0)
    parser.add_argument("--partition-count", type=int, default=1)
    return parser.parse_args(argv)


def main():
    split = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    args = parse_args(sys.argv[split + 1:])
    paths = sorted(args.source.rglob("*.fbx"))
    paths = [path for index, path in enumerate(paths) if index % args.partition_count == args.partition_index]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as stream:
        for index, path in enumerate(paths, 1):
            try:
                row = audit(path)
            except Exception as error:
                row = {"path": str(path), "status": "error", "error": str(error), "traceback": traceback.format_exc()}
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
            stream.flush()
            if index % 100 == 0:
                print(f"AUDIT_PROGRESS partition={args.partition_index} processed={index}/{len(paths)}")


if __name__ == "__main__":
    main()
