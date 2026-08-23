#!/usr/bin/env python3
"""Merge partitioned humanoid audits into stable project catalogs."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, nargs="+", required=True)
    parser.add_argument("--old-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rows = []
    old_root = str(args.old_root)
    source_root = str(args.source_root.resolve())
    for input_path in args.input:
        for line in input_path.read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            source_path = row["path"]
            if source_path.startswith(old_root):
                source_path = source_root + source_path[len(old_root):]
            row["path"] = source_path
            try:
                row["relativePath"] = str(Path(source_path).relative_to(args.source_root.resolve()))
            except ValueError:
                row["relativePath"] = source_path
            rows.append(row)
    rows.sort(key=lambda row: row["relativePath"])
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "compatibility-catalog.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    with (args.output / "compatibility-catalog.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(("relativePath", "status", "family", "grade", "bones", "mapped", "actions", "skeleton"))
        for row in rows:
            writer.writerow((
                row.get("relativePath"), row.get("status"), row.get("family"),
                row.get("compatibilityGrade"), row.get("boneCount"),
                row.get("mappedSemanticCount"), row.get("actionCount"),
                row.get("skeletonFingerprint"),
            ))
    actions = []
    for row in rows:
        for action in row.get("actions", []):
            actions.append({
                "relativePath": row["relativePath"], "family": row.get("family"),
                "compatibilityGrade": row.get("compatibilityGrade"), **action,
            })
    (args.output / "action-catalog.json").write_text(
        json.dumps(actions, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    family_counts = Counter(row.get("family", "non-animation-asset") for row in rows)
    grade_counts = Counter(row.get("compatibilityGrade", "not-applicable") for row in rows)
    status_counts = Counter(row.get("status", "unknown") for row in rows)
    root_motion = Counter()
    for action in actions:
        if action.get("rootMotion", {}).get("maxAxisSpan", 0) > 30:
            root_motion[action.get("family", "unknown")] += 1
    summary = {
        "sourceRoot": source_root,
        "filesAudited": len(rows),
        "actionsAudited": len(actions),
        "families": dict(sorted(family_counts.items())),
        "compatibilityGrades": dict(sorted(grade_counts.items())),
        "statuses": dict(sorted(status_counts.items())),
        "rootMotionActionsOver30SourceUnits": dict(sorted(root_motion.items())),
        "nonFiniteActionFiles": sum(
            any(action.get("rootMotion", {}).get("nonFiniteValues", 0) for action in row.get("actions", []))
            for row in rows
        ),
        "skeletonFingerprints": dict(sorted(Counter(
            row.get("skeletonFingerprint") for row in rows if row.get("skeletonFingerprint")
        ).items())),
    }
    (args.output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
