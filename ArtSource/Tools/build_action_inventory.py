#!/usr/bin/env python3
"""Build a non-destructive inventory of downloaded Mixamo FBX motions.

The FBX filename is not an identity: Mixamo reuses display names. This tool
joins local files to the captured catalog, preserves all candidate UUIDs, and
adds Blender audit facts when an ACTION_AUDIT log is supplied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


COPY_SUFFIX = re.compile(r"\s*\((\d+)\)$")
TRAILING_COPY = re.compile(r"(?<!\d)(\d+)$")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def name_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.casefold()).strip()


def candidate_stems(path: Path, catalog_keys: set[str]) -> list[str]:
    stem = path.stem
    values = [stem]
    without_copy = COPY_SUFFIX.sub("", stem)
    if without_copy != stem:
        values.append(without_copy)
    without_trailing = TRAILING_COPY.sub("", stem)
    if without_trailing != stem and name_key(without_trailing) in catalog_keys:
        values.append(without_trailing)
    return list(dict.fromkeys(values))


def load_audit(path: Path | None) -> dict[str, dict]:
    if path is None or not path.exists():
        return {}
    text = path.read_text(errors="replace")
    marker = "ACTION_AUDIT="
    start = text.rfind(marker)
    if start < 0:
        return {}
    line = text[start + len(marker):].splitlines()[0]
    return {str(Path(item["path"]).resolve()): item for item in json.loads(line)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--audit-log", type=Path)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-tsv", type=Path, required=True)
    args = parser.parse_args()

    catalog = json.loads(args.catalog.read_text())
    by_name: dict[str, list[dict]] = defaultdict(list)
    for motion in catalog["items"]:
        by_name[name_key(motion["name"])].append(motion)
    audit = load_audit(args.audit_log)

    files = sorted(args.source.glob("*.fbx"), key=lambda item: item.name.casefold())
    hashes = {str(path.resolve()): sha256(path) for path in files}
    hash_counts = Counter(hashes.values())
    first_for_hash: dict[str, str] = {}
    records = []

    for path in files:
        resolved = str(path.resolve())
        digest = hashes[resolved]
        stems = candidate_stems(path, set(by_name))
        candidates = []
        matched_stem = None
        for stem in stems:
            found = by_name.get(name_key(stem), [])
            if found:
                candidates = found
                matched_stem = stem
                break

        facts = audit.get(resolved)
        meshes = facts.get("meshes_to_discard") if facts else None
        actions = facts.get("actions", []) if facts else []
        frame_start = actions[0].get("frame_start") if len(actions) == 1 else None
        frame_end = actions[0].get("frame_end") if len(actions) == 1 else None
        frames = frame_end - frame_start + 1 if frame_start is not None else None
        if not candidates:
            match_status = "unmatched"
        elif len(candidates) == 1:
            match_status = "unique-name"
        else:
            match_status = "ambiguous-name"

        duplicate_of = first_for_hash.get(digest)
        first_for_hash.setdefault(digest, path.name)
        records.append({
            "file": path.name,
            "path": resolved,
            "bytes": path.stat().st_size,
            "sha256": digest,
            "byteIdenticalCopies": hash_counts[digest],
            "duplicateOf": duplicate_of,
            "matchedCatalogName": matched_stem,
            "matchStatus": match_status,
            "catalogCandidates": [
                {
                    "id": item["id"],
                    "name": item["name"],
                    "description": item.get("description", ""),
                    "characterType": item.get("characterType"),
                    "thumbnail": item.get("thumbnail"),
                }
                for item in candidates
            ],
            "fbxAudit": None if facts is None else {
                "armatures": facts["armatures"],
                "meshes": meshes,
                "actions": actions,
                "boneCount": facts["bone_count"],
                "missingCriticalBones": facts["missing_critical_bones"],
                "motionOnlyEligible": facts["motion_only_eligible"],
                "frameCount": frames,
                "durationAt30FPS": None if frames is None else round(frames / 30, 4),
                "exportProfile": "without-skin" if meshes == 0 else "with-skin",
                "rootCurves": facts["root_curves"],
            },
        })

    summary = {
        "files": len(records),
        "withSkin": sum(r["fbxAudit"] is not None and r["fbxAudit"]["exportProfile"] == "with-skin" for r in records),
        "withoutSkin": sum(r["fbxAudit"] is not None and r["fbxAudit"]["exportProfile"] == "without-skin" for r in records),
        "uniqueNameMatches": sum(r["matchStatus"] == "unique-name" for r in records),
        "ambiguousNameMatches": sum(r["matchStatus"] == "ambiguous-name" for r in records),
        "unmatched": sum(r["matchStatus"] == "unmatched" for r in records),
        "redundantByteIdenticalFiles": sum(r["duplicateOf"] is not None for r in records),
    }
    document = {
        "schemaVersion": 1,
        "sourceDirectory": str(args.source.resolve()),
        "catalog": str(args.catalog.resolve()),
        "identityWarning": "A filename is not a Mixamo identity; ambiguous candidates require UUID/provenance or visual verification.",
        "summary": summary,
        "files": records,
    }
    args.output_json.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")

    header = ["file", "bytes", "skin", "frames", "seconds30", "match", "candidateCount", "candidateUUIDs", "descriptions", "sha256", "duplicateOf"]
    rows = ["\t".join(header)]
    for record in records:
        facts = record["fbxAudit"] or {}
        candidates = record["catalogCandidates"]
        values = [
            record["file"], str(record["bytes"]), facts.get("exportProfile", "unknown"),
            str(facts.get("frameCount", "")), str(facts.get("durationAt30FPS", "")),
            record["matchStatus"], str(len(candidates)),
            " | ".join(item["id"] for item in candidates),
            " | ".join(item["description"] for item in candidates),
            record["sha256"], record["duplicateOf"] or "",
        ]
        rows.append("\t".join(value.replace("\t", " ").replace("\n", " ") for value in values))
    args.output_tsv.write_text("\n".join(rows) + "\n")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
