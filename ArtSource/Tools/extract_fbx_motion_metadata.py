#!/usr/bin/env python3
"""Extract searchable technical metadata from FBX animation sources in Blender.

The script is read-only with respect to FBX files. It writes resumable NDJSON,
one record per source, and deliberately keeps semantic identity separate from
measured motion facts: hash-named archives do not contain their Mixamo title.

Run through Blender:
  Blender --background --factory-startup \
    --python extract_fbx_motion_metadata.py -- \
    --source .../Library/Sources --output .../Work/audit-0.ndjson \
    --partition-index 0 --partition-count 4
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import traceback
from pathlib import Path

import bpy
from mathutils import Vector


HASH_NAME = re.compile(r"^[0-9a-f]{32}$")
OFFICIAL_NAME = re.compile(r"^(?P<name>.+)__(?P<uuid>[0-9a-f-]{36})$")
DATA_PATH_BONE = re.compile(r'pose\.bones\["([^"]+)"\]')
SAMPLE_BONES = (
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
)
CRITICAL_BONES = {
    "Hips", "Spine", "Head", "LeftArm", "RightArm",
    "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg",
}
SOURCE_FPS = 30.0


def canonical_bone(name: str) -> str:
    return re.sub(r"^mixamorig\d*:", "", name)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fbx_version(path: Path) -> int | None:
    with path.open("rb") as stream:
        header = stream.read(27)
    if header.startswith(b"Kaydara FBX Binary") and len(header) >= 27:
        return struct.unpack("<I", header[23:27])[0]
    return None


def action_curves(action):
    # Blender 5 layered Actions.
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    channelbag = strip.channelbag(slot)
                    if channelbag:
                        yield from channelbag.fcurves
        return
    yield from getattr(action, "fcurves", ())


def normalize_degrees(value: float) -> float:
    return (value + 180.0) % 360.0 - 180.0


def quat_values(quaternion) -> list[float]:
    values = [quaternion.w, quaternion.x, quaternion.y, quaternion.z]
    if values[0] < 0:
        values = [-value for value in values]
    return [round(value, 5) for value in values]


def relative_pose_payload(pose_samples: list[list[float]]) -> str:
    if not pose_samples:
        return "[]"

    def multiply(a: list[float], b: list[float]) -> list[float]:
        aw, ax, ay, az = a
        bw, bx, by, bz = b
        return [
            aw * bw - ax * bx - ay * by - az * bz,
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
        ]

    values: list[float] = []
    first = pose_samples[0]
    for sample in pose_samples:
        for index in range(0, len(sample), 4):
            origin = first[index:index + 4]
            current = sample[index:index + 4]
            conjugate = [origin[0], -origin[1], -origin[2], -origin[3]]
            delta = multiply(conjugate, current)
            if delta[0] < 0:
                delta = [-value for value in delta]
            values.extend(round(value, 4) for value in delta)
    return json.dumps(values, separators=(",", ":"))


def angular_motion_payload(pose_samples: list[list[float]]) -> str:
    if not pose_samples:
        return "[]"

    def multiply(a: list[float], b: list[float]) -> list[float]:
        aw, ax, ay, az = a
        bw, bx, by, bz = b
        return [
            aw * bw - ax * bx - ay * by - az * bz,
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
        ]

    values: list[float] = []
    first = pose_samples[0]
    for sample in pose_samples:
        for index in range(0, len(sample), 4):
            origin = first[index:index + 4]
            current = sample[index:index + 4]
            delta = multiply([origin[0], -origin[1], -origin[2], -origin[3]], current)
            values.append(round(math.degrees(2.0 * math.acos(min(1.0, abs(delta[0])))), 3))
    return json.dumps(values, separators=(",", ":"))


def classify(horizontal_path: float, net: float, yaw: float) -> str:
    if net < 0.25 and horizontal_path < 0.35:
        return "turn-in-place" if abs(yaw) >= 25.0 else "stationary"
    if net >= 0.25:
        return "locomotion-turning" if abs(yaw) >= 25.0 else "locomotion-straight"
    return "complex-in-place"


def technical_description(record: dict, language: str) -> str:
    motion = record["motion"]
    if language == "ru":
        loop = "похож на цикл" if motion["likelyLoop"] else "одноразовый/нециклический"
        return (
            f"Humanoid motion-only; {motion['classification']}; "
            f"{record['timing']['durationSeconds']:.3f} с при 30 fps; "
            f"путь {motion['horizontalPathMeters']:.3f} м; "
            f"смещение {motion['netHorizontalMeters']:.3f} м; "
            f"поворот {motion['rootYawDegrees']:.1f}°; {loop}."
        )
    loop = "likely loop" if motion["likelyLoop"] else "one-shot/non-looping"
    return (
        f"Humanoid motion-only; {motion['classification']}; "
        f"{record['timing']['durationSeconds']:.3f}s at 30 fps; "
        f"path {motion['horizontalPathMeters']:.3f}m; "
        f"net {motion['netHorizontalMeters']:.3f}m; "
        f"turn {motion['rootYawDegrees']:.1f}deg; {loop}."
    )


def source_identity(path: Path, source_root: Path) -> dict:
    stem = path.stem
    relative = path.relative_to(source_root).as_posix()
    official = OFFICIAL_NAME.match(stem)
    receipt_path = Path(f"{path}.source.json")
    receipt = None
    if receipt_path.exists():
        try:
            receipt = json.loads(receipt_path.read_text())
        except Exception as error:
            receipt = {"readError": str(error)}
    if HASH_NAME.fullmatch(stem):
        kind = "hash-archive"
        display_name = None
        provider_id = None
        confidence = "missing"
    elif official:
        kind = "official-export"
        display_name = receipt.get("motionName", official.group("name")) if isinstance(receipt, dict) else official.group("name")
        provider_id = receipt.get("motionID", official.group("uuid")) if isinstance(receipt, dict) else official.group("uuid")
        confidence = "confirmed"
    else:
        kind = "named-local"
        display_name = stem
        provider_id = None
        confidence = "filename-only"
    return {
        "kind": kind,
        "relativePath": relative,
        "fileName": path.name,
        "sourceID": stem if kind == "hash-archive" else provider_id,
        "displayName": display_name,
        "nameConfidence": confidence,
        "receipt": receipt,
    }


def audit(path: Path, source_root: Path) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))

    objects = list(bpy.data.objects)
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in objects if obj.type == "MESH"]
    cameras = [obj for obj in objects if obj.type == "CAMERA"]
    lights = [obj for obj in objects if obj.type == "LIGHT"]
    actions = list(bpy.data.actions)
    identity = source_identity(path, source_root)

    bone_names = sorted({canonical_bone(bone.name) for arm in armatures for bone in arm.data.bones})
    missing = sorted(CRITICAL_BONES.difference(bone_names))
    curves = [curve for action in actions for curve in action_curves(action)]
    animated_bones = sorted({
        canonical_bone(match.group(1))
        for curve in curves
        if (match := DATA_PATH_BONE.search(curve.data_path))
    })
    keyframe_count = sum(len(curve.keyframe_points) for curve in curves)
    frame_start = min((action.frame_range[0] for action in actions), default=0.0)
    frame_end = max((action.frame_range[1] for action in actions), default=0.0)
    frame_span = max(0.0, frame_end - frame_start)
    sample_count = int(round(frame_span)) + 1 if actions else 0
    duration = frame_span / SOURCE_FPS

    root_positions: list[Vector] = []
    root_yaws: list[float] = []
    pose_samples: list[list[float]] = []
    armature = armatures[0] if armatures else None
    bone_map = {canonical_bone(bone.name): bone.name for bone in armature.pose.bones} if armature else {}
    hips = armature.pose.bones.get(bone_map.get("Hips", "")) if armature else None

    if actions and armature and hips:
        integer_start = int(math.floor(frame_start))
        integer_end = int(math.ceil(frame_end))
        for frame in range(integer_start, integer_end + 1):
            bpy.context.scene.frame_set(frame)
            matrix = armature.matrix_world @ hips.matrix
            root_positions.append(matrix.translation.copy())
            forward = matrix.to_quaternion() @ Vector((0.0, -1.0, 0.0))
            root_yaws.append(math.degrees(math.atan2(forward.x, -forward.y)))

        for sample_index in range(17):
            frame = frame_start + frame_span * sample_index / 16.0 if frame_span else frame_start
            whole = math.floor(frame)
            bpy.context.scene.frame_set(int(whole), subframe=frame - whole)
            values: list[float] = []
            for canonical in SAMPLE_BONES:
                actual = bone_map.get(canonical)
                if actual:
                    values.extend(quat_values(armature.pose.bones[actual].matrix_basis.to_quaternion()))
                else:
                    values.extend((0.0, 0.0, 0.0, 0.0))
            pose_samples.append(values)

    horizontal_path = 0.0
    spatial_path = 0.0
    if root_positions:
        for first, second in zip(root_positions, root_positions[1:]):
            delta = second - first
            horizontal_path += math.hypot(delta.x, delta.y)
            spatial_path += delta.length
        delta = root_positions[-1] - root_positions[0]
        net_horizontal = math.hypot(delta.x, delta.y)
        net_vertical = delta.z
        vertical_range = max(item.z for item in root_positions) - min(item.z for item in root_positions)
    else:
        net_horizontal = net_vertical = vertical_range = 0.0
    yaw_delta = normalize_degrees(root_yaws[-1] - root_yaws[0]) if len(root_yaws) >= 2 else 0.0

    pose_error_degrees = 0.0
    if pose_samples:
        errors = []
        first = pose_samples[0]
        last = pose_samples[-1]
        for index in range(0, len(first), 4):
            dot = abs(sum(first[index + part] * last[index + part] for part in range(4)))
            dot = min(1.0, max(-1.0, dot))
            errors.append(math.degrees(2.0 * math.acos(dot)))
        pose_error_degrees = sum(errors) / len(errors) if errors else 0.0

    pose_payload = json.dumps(pose_samples, separators=(",", ":"))
    relative_payload = relative_pose_payload(pose_samples)
    angular_payload = angular_motion_payload(pose_samples)
    normalized_root = []
    if root_positions:
        first = root_positions[0]
        for sample_index in range(17):
            index = round((len(root_positions) - 1) * sample_index / 16.0)
            delta = root_positions[index] - first
            normalized_root.extend(round(value, 4) for value in (delta.x, delta.y, delta.z))
    motion_payload = pose_payload + json.dumps(normalized_root, separators=(",", ":"))

    classification = classify(horizontal_path, net_horizontal, yaw_delta)
    likely_loop = pose_error_degrees <= 8.0 and abs(yaw_delta) <= 12.0
    tags = [
        "humanoid", "motion-only" if not meshes else "contains-mesh", classification,
        "likely-loop" if likely_loop else "one-shot",
        "has-root-motion" if horizontal_path >= 0.1 else "near-in-place",
        "short" if duration < 1.0 else "long" if duration > 5.0 else "medium",
    ]
    record = {
        "schemaVersion": 1,
        "id": identity["sourceID"] or hashlib.sha256(identity["relativePath"].encode()).hexdigest()[:32],
        "identity": identity,
        "file": {
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
            "fbxVersion": fbx_version(path),
        },
        "scene": {
            "armatureCount": len(armatures),
            "meshCount": len(meshes),
            "cameraCount": len(cameras),
            "lightCount": len(lights),
            "actionCount": len(actions),
            "actionNames": [action.name for action in actions],
        },
        "skeleton": {
            "boneCount": len(bone_names),
            "animatedBoneCount": len(animated_bones),
            "missingCriticalBones": missing,
            "mixamoCompatible": len(armatures) == 1 and not missing,
        },
        "timing": {
            "sourceFPS": int(SOURCE_FPS),
            "frameStart": frame_start,
            "frameEnd": frame_end,
            "frameSpan": frame_span,
            "sampleCount": sample_count,
            "durationSeconds": round(duration, 6),
            "curveCount": len(curves),
            "keyframeCount": keyframe_count,
        },
        "motion": {
            "classification": classification,
            "horizontalPathMeters": round(horizontal_path, 6),
            "spatialPathMeters": round(spatial_path, 6),
            "netHorizontalMeters": round(net_horizontal, 6),
            "netVerticalMeters": round(net_vertical, 6),
            "verticalRangeMeters": round(vertical_range, 6),
            "rootYawDegrees": round(yaw_delta, 4),
            "averageHorizontalSpeedMPS": round(horizontal_path / duration, 6) if duration else 0.0,
            "endpointPoseErrorDegrees": round(pose_error_degrees, 4),
            "likelyLoop": likely_loop,
            "poseFingerprint": hashlib.sha256(pose_payload.encode()).hexdigest(),
            "relativePoseFingerprint": hashlib.sha256(relative_payload.encode()).hexdigest(),
            "angularMotionFingerprint": hashlib.sha256(angular_payload.encode()).hexdigest(),
            "motionFingerprint": hashlib.sha256(motion_payload.encode()).hexdigest(),
        },
        "eligibility": {
            "motionOnly": len(meshes) == 0,
            "retargetCandidate": len(armatures) == 1 and len(actions) == 1 and not missing,
            "requiresMeshDiscard": len(meshes) > 0,
        },
        "semantic": {
            "status": "confirmed" if identity["nameConfidence"] == "confirmed" else "unclassified" if identity["displayName"] is None else "filename-unverified",
            "displayName": identity["displayName"],
            "description": identity.get("receipt", {}).get("motionDescription") if isinstance(identity.get("receipt"), dict) else None,
            "tags": tags,
        },
    }
    record["technicalDescription"] = {
        "en": technical_description(record, "en"),
        "ru": technical_description(record, "ru"),
    }
    return record


def main() -> None:
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--partition-index", type=int, default=0)
    parser.add_argument("--partition-count", type=int, default=1)
    args = parser.parse_args(sys.argv[separator + 1:])
    if args.partition_count < 1 or not 0 <= args.partition_index < args.partition_count:
        raise SystemExit("Invalid partition")

    source = args.source.resolve()
    files = sorted(source.rglob("*.fbx"), key=lambda item: item.relative_to(source).as_posix().casefold())
    files = [path for index, path in enumerate(files) if index % args.partition_count == args.partition_index]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    completed: set[str] = set()
    if args.output.exists():
        for line in args.output.read_text(errors="replace").splitlines():
            try:
                completed.add(json.loads(line)["identity"]["relativePath"])
            except Exception:
                pass

    with args.output.open("a", buffering=1) as stream:
        for sequence, path in enumerate(files, 1):
            relative = path.relative_to(source).as_posix()
            if relative in completed:
                continue
            try:
                record = audit(path, source)
            except Exception as error:
                record = {
                    "schemaVersion": 1,
                    "id": hashlib.sha256(relative.encode()).hexdigest()[:32],
                    "identity": {"relativePath": relative, "fileName": path.name, "kind": "error"},
                    "error": {"message": str(error), "traceback": traceback.format_exc()},
                }
            stream.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
            print(f"MOTION_AUDIT {args.partition_index}/{args.partition_count} {sequence}/{len(files)} {relative}", flush=True)


if __name__ == "__main__":
    main()
