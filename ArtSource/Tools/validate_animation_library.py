#!/usr/bin/env python3
"""Validate source/catalog consistency for the local animation library."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


DEFAULT_LIBRARY = Path(__file__).resolve().parents[1] / "Animations/Library"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument("--deep", action="store_true", help="recompute SHA-256 for every FBX")
    args = parser.parse_args()
    library = args.library.resolve()
    sources = library / "Sources"
    document = json.loads((library / "Catalog/animation-library.json").read_text())
    records = document["animations"]
    failures = []
    seen = set()
    for item in records:
        relative = item["identity"]["relativePath"]
        if relative in seen:
            failures.append(f"duplicate catalog path: {relative}")
        seen.add(relative)
        path = sources / relative
        if not path.is_file():
            failures.append(f"missing source: {relative}")
            continue
        if "error" in item:
            failures.append(f"audit error: {relative}: {item['error']['message']}")
            continue
        if path.stat().st_size != item["file"]["bytes"]:
            failures.append(f"size mismatch: {relative}")
        if args.deep and sha256(path) != item["file"]["sha256"]:
            failures.append(f"sha256 mismatch: {relative}")
    source_paths = {path.relative_to(sources).as_posix() for path in sources.rglob("*.fbx")}
    for relative in sorted(source_paths.difference(seen)):
        failures.append(f"uncataloged source: {relative}")
    for relative in sorted(seen.difference(source_paths)):
        failures.append(f"catalog-only source: {relative}")

    broken_links = [path for path in (library / "Views").rglob("*.fbx") if path.is_symlink() and not path.resolve().is_file()]
    failures.extend(f"broken view link: {path.relative_to(library)}" for path in broken_links)
    selections_path = library / "Selected/current-selections.json"
    selections = json.loads(selections_path.read_text())["selections"] if selections_path.exists() else []
    unresolved = [item["semantic"] for item in selections if not item["resolved"]]

    report = {
        "catalogRecords": len(records),
        "sourceFBX": len(source_paths),
        "deepSHA256": args.deep,
        "brokenViewLinks": len(broken_links),
        "currentSelections": len(selections),
        "unresolvedCurrentSelections": unresolved,
        "failures": failures,
        "valid": not failures,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
