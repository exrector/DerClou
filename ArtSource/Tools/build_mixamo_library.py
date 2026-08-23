#!/usr/bin/env python3
"""Merge FBX audit partitions into the searchable DerClou animation catalog."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
from collections import Counter, defaultdict
from pathlib import Path


def clean(value) -> str:
    return "" if value is None else str(value).replace("\t", " ").replace("\n", " ")


def load_records(work: Path) -> list[dict]:
    by_path = {}
    for path in sorted(work.glob("audit-*.ndjson")):
        for line in path.read_text(errors="replace").splitlines():
            if not line.strip():
                continue
            item = json.loads(line)
            by_path[item["identity"]["relativePath"]] = item
    return sorted(by_path.values(), key=lambda item: item["identity"]["relativePath"].casefold())


GAMEPLAY_QUERIES = {
    "Idle": ["idle", "unarmed idle", "standing idle"],
    "StartWalking": ["start walking", "walk start", "idle to walk"],
    "Walk": ["standard walk", "walking", "walk"],
    "StopWalking": ["stop walking", "walk stop", "walking stop"],
    "ShortStep": ["short step", "step forward", "small step"],
    "TurnLeft": ["turn left", "left turn"],
    "TurnRight": ["turn right", "right turn"],
    "TurnAround": ["180 turn", "turn around", "turn 180"],
    "OpenDoor": ["opening door", "open door"],
    "CloseDoor": ["closing door", "close door"],
    "UnlockDoor": ["unlocking door", "unlock door", "key door"],
    "Lockpick": ["lockpick", "lock picking", "pick lock"],
    "PressButton": ["button pushing", "push button", "press button"],
    "PullLever": ["pulling lever", "pull lever"],
    "Look": ["looking", "look around", "look"],
}
PROP_WORDS = {"rifle", "pistol", "gun", "sword", "shield", "briefcase", "torch", "dagger", "axe"}


def words(value: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", value.casefold())


def candidate_score(semantic: str, record: dict) -> int:
    name = record["semantic"].get("displayName") or ""
    description = record["semantic"].get("description") or ""
    normalized = " ".join(words(f"{name} {description}"))
    name_normalized = " ".join(words(name))
    score = 0
    for query in GAMEPLAY_QUERIES[semantic]:
        query_words = words(query)
        query_normalized = " ".join(query_words)
        if name_normalized == query_normalized:
            score = max(score, 120)
        elif query_normalized in normalized:
            score = max(score, 80)
        else:
            score = max(score, 8 * len(set(query_words).intersection(words(normalized))))
    motion_class = record["motion"]["classification"]
    if semantic in {"Idle", "Look", "PressButton", "PullLever", "OpenDoor", "CloseDoor", "UnlockDoor", "Lockpick"} and motion_class in {"stationary", "complex-in-place"}:
        score += 15
    if semantic in {"Walk", "StartWalking", "StopWalking", "ShortStep"} and motion_class.startswith("locomotion"):
        score += 15
    if semantic in {"TurnLeft", "TurnRight", "TurnAround"} and motion_class in {"turn-in-place", "locomotion-turning"}:
        score += 15
    score += 10 if record["semantic"]["status"] == "confirmed" else 4
    score -= 25 * len(PROP_WORDS.intersection(words(normalized)))
    return score


def write_gameplay_candidates(catalog: Path, records: list[dict]) -> None:
    named = [item for item in records if "error" not in item and item["semantic"].get("displayName")]
    result = {}
    for semantic in GAMEPLAY_QUERIES:
        ranked = sorted(
            ((candidate_score(semantic, item), item) for item in named),
            key=lambda pair: (-pair[0], pair[1]["semantic"]["displayName"].casefold(), pair[1]["id"]),
        )
        result[semantic] = [{
            "score": score,
            "id": item["id"],
            "name": item["semantic"]["displayName"],
            "description": item["semantic"].get("description") or item["technicalDescription"]["ru"],
            "identityStatus": item["semantic"]["status"],
            "source": item["identity"]["relativePath"],
            "technicalClass": item["motion"]["classification"],
            "seconds": item["timing"]["durationSeconds"],
            "pathMeters": item["motion"]["horizontalPathMeters"],
            "turnDegrees": item["motion"]["rootYawDegrees"],
            "likelyLoop": item["motion"]["likelyLoop"],
            "requiresMeshDiscard": item["eligibility"]["requiresMeshDiscard"],
        } for score, item in ranked[:12] if score > 0]
    (catalog / "gameplay-candidates.json").write_text(json.dumps({
        "schemaVersion": 1,
        "warning": "Candidates are ranked search results, not automatic acceptance. Preview and audit before retargeting.",
        "semantics": result,
    }, indent=2, ensure_ascii=False) + "\n")
    lines = ["# Gameplay animation candidates", "", "Ranked discovery list; visual review is mandatory.", ""]
    for semantic, candidates in result.items():
        lines.extend([f"## {semantic}", "", "| Score | Name | Identity | Technical facts | Source |", "|---:|---|---|---|---|"])
        for item in candidates[:8]:
            facts = f"{item['technicalClass']}; {item['seconds']:.3f}s; {item['pathMeters']:.3f}m; {item['turnDegrees']:.1f}deg"
            lines.append(f"| {item['score']} | {item['name']} | {item['identityStatus']} | {facts} | `{item['source']}` |")
        lines.append("")
    (catalog / "gameplay-candidates.md").write_text("\n".join(lines) + "\n")


def write_current_selections(library: Path, records: list[dict]) -> None:
    manifest_path = library.parent / "actions-manifest.json"
    if not manifest_path.exists():
        return
    manifest = json.loads(manifest_path.read_text())
    by_file: dict[str, list[dict]] = defaultdict(list)
    for item in records:
        if "error" not in item:
            by_file[item["identity"]["fileName"]].append(item)
    selections = []
    view = library / "Views" / "Selected"
    view.mkdir(parents=True, exist_ok=True)
    for configured in manifest.get("clips", []):
        candidates = by_file.get(configured["source"], [])
        chosen = sorted(candidates, key=lambda item: ({"official-export": 0, "named-local": 1, "hash-archive": 2}.get(item["identity"]["kind"], 9), item["identity"]["relativePath"]))[0] if candidates else None
        selection = {
            "semantic": configured["semantic"],
            "configuredSource": configured["source"],
            "resolved": chosen is not None,
            "source": chosen["identity"]["relativePath"] if chosen else None,
            "sourceID": chosen["id"] if chosen else None,
            "identityStatus": chosen["semantic"]["status"] if chosen else None,
            "technicalDescription": chosen["technicalDescription"] if chosen else None,
            "configuration": configured,
        }
        selections.append(selection)
        if chosen:
            link = view / f"{configured['semantic']}.fbx"
            target = library / "Sources" / chosen["identity"]["relativePath"]
            if not link.exists() and not link.is_symlink():
                link.symlink_to(os.path.relpath(target, view))
    (library / "Selected" / "current-selections.json").write_text(json.dumps({
        "schemaVersion": 1,
        "sourceManifest": "../../actions-manifest.json",
        "selections": selections,
    }, indent=2, ensure_ascii=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, required=True)
    args = parser.parse_args()
    library = args.library.resolve()
    work = library / "Work"
    catalog = library / "Catalog"
    views = library / "Views" / "ByTechnicalClass"
    sources = library / "Sources"
    catalog.mkdir(parents=True, exist_ok=True)
    views.mkdir(parents=True, exist_ok=True)

    records = load_records(work)
    sha_groups: dict[str, list[dict]] = defaultdict(list)
    motion_groups: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        if "error" in record:
            continue
        sha_groups[record["file"]["sha256"]].append(record)
        fingerprint = f"{record['timing']['sampleCount']}:{record['motion']['angularMotionFingerprint']}"
        motion_groups[fingerprint].append(record)

    # Propagate names only from confirmed first-party receipts and only across
    # an identical extracted motion fingerprint. Filename-only labels remain
    # suggestions and never overwrite a confirmed identity.
    for group in motion_groups.values():
        confirmed = [item for item in group if item["semantic"]["status"] == "confirmed"]
        identities = sorted({
            (item["semantic"]["displayName"], item["identity"].get("sourceID"), item["semantic"].get("description"))
            for item in confirmed
        }, key=lambda identity: tuple(value or "" for value in identity))
        for item in group:
            item["matches"] = {
                "byteIdenticalPaths": sorted(
                    candidate["identity"]["relativePath"]
                    for candidate in sha_groups[item["file"]["sha256"]]
                    if candidate is not item
                ),
                "confirmedMotionIdentities": [
                    {"name": name, "providerID": provider_id, "description": description}
                    for name, provider_id, description in identities
                ],
                "sameMotionPaths": sorted(
                    candidate["identity"]["relativePath"] for candidate in group if candidate is not item
                ),
            }
            if item["semantic"]["status"] == "unclassified" and len(identities) == 1:
                name, provider_id, description = identities[0]
                item["semantic"].update({
                    "status": "fingerprint-confirmed",
                    "displayName": name,
                    "description": description,
                    "providerID": provider_id,
                })

    for record in records:
        if "error" in record:
            continue
        class_dir = views / record["motion"]["classification"]
        class_dir.mkdir(parents=True, exist_ok=True)
        label = record["semantic"].get("displayName") or record["id"]
        safe = "".join(character if character.isalnum() or character in " ._-" else "_" for character in label).strip()
        link = class_dir / f"{safe}__{record['id']}.fbx"
        target = sources / record["identity"]["relativePath"]
        if not link.exists() and not link.is_symlink():
            link.symlink_to(os.path.relpath(target, class_dir))

    summary = {
        "totalRecords": len(records),
        "successful": sum("error" not in item for item in records),
        "errors": sum("error" in item for item in records),
        "sourceKinds": dict(sorted(Counter(item["identity"]["kind"] for item in records).items())),
        "semanticStatus": dict(sorted(Counter(item.get("semantic", {}).get("status", "error") for item in records).items())),
        "technicalClasses": dict(sorted(Counter(item.get("motion", {}).get("classification", "error") for item in records).items())),
        "retargetCandidates": sum(item.get("eligibility", {}).get("retargetCandidate", False) for item in records),
        "requiresMeshDiscard": sum(item.get("eligibility", {}).get("requiresMeshDiscard", False) for item in records),
        "byteDuplicateFiles": sum(max(0, len(group) - 1) for group in sha_groups.values()),
        "confirmedFingerprintMatches": sum(item.get("semantic", {}).get("status") == "fingerprint-confirmed" for item in records),
    }
    document = {
        "schemaVersion": 1,
        "libraryRoot": str(library),
        "identityPolicy": "Extracted facts are authoritative. A semantic name is authoritative only with a first-party receipt or a unique frame-count plus per-bone angular-motion fingerprint match to one confirmed receipt.",
        "referenceCatalog": "../../mixamo-motion-catalog.json",
        "summary": summary,
        "animations": records,
    }
    (catalog / "animation-library.json").write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    (catalog / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")

    columns = [
        "id", "name", "semanticStatus", "description", "sourceKind", "relativePath",
        "technicalClass", "tags", "seconds", "frames", "pathMeters", "netMeters",
        "turnDegrees", "avgSpeedMPS", "likelyLoop", "poseErrorDegrees", "bones",
        "meshes", "retargetCandidate", "confirmedMatches", "sha256",
    ]
    with (catalog / "animation-library.tsv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, dialect="excel-tab")
        writer.writeheader()
        for item in records:
            if "error" in item:
                writer.writerow({"id": item["id"], "sourceKind": "error", "relativePath": item["identity"]["relativePath"]})
                continue
            writer.writerow({
                "id": item["id"],
                "name": item["semantic"].get("displayName"),
                "semanticStatus": item["semantic"]["status"],
                "description": item["semantic"].get("description") or item["technicalDescription"]["ru"],
                "sourceKind": item["identity"]["kind"],
                "relativePath": item["identity"]["relativePath"],
                "technicalClass": item["motion"]["classification"],
                "tags": ",".join(item["semantic"]["tags"]),
                "seconds": item["timing"]["durationSeconds"],
                "frames": item["timing"]["sampleCount"],
                "pathMeters": item["motion"]["horizontalPathMeters"],
                "netMeters": item["motion"]["netHorizontalMeters"],
                "turnDegrees": item["motion"]["rootYawDegrees"],
                "avgSpeedMPS": item["motion"]["averageHorizontalSpeedMPS"],
                "likelyLoop": item["motion"]["likelyLoop"],
                "poseErrorDegrees": item["motion"]["endpointPoseErrorDegrees"],
                "bones": item["skeleton"]["boneCount"],
                "meshes": item["scene"]["meshCount"],
                "retargetCandidate": item["eligibility"]["retargetCandidate"],
                "confirmedMatches": " | ".join(match["name"] for match in item["matches"]["confirmedMotionIdentities"]),
                "sha256": item["file"]["sha256"],
            })

    search = [{
        "id": item["id"],
        "name": item.get("semantic", {}).get("displayName"),
        "description": item.get("semantic", {}).get("description") or item.get("technicalDescription", {}).get("ru"),
        "tags": item.get("semantic", {}).get("tags", []),
        "class": item.get("motion", {}).get("classification"),
        "source": item["identity"]["relativePath"],
    } for item in records if "error" not in item]
    (catalog / "search-index.json").write_text(json.dumps(search, ensure_ascii=False, separators=(",", ":")) + "\n")
    write_gameplay_candidates(catalog, records)
    write_current_selections(library, records)
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
