#!/usr/bin/env python3
"""Search the generated DerClou animation library by words and motion facts."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


DEFAULT_CATALOG = Path(__file__).resolve().parents[1] / "Animations/Library/Catalog/animation-library.json"


def tokens(value: str) -> list[str]:
    return re.findall(r"[a-zа-яё0-9]+", value.casefold())


def searchable(item: dict) -> str:
    return " ".join([
        item["semantic"].get("displayName") or "",
        item["semantic"].get("description") or "",
        item["technicalDescription"]["en"],
        item["technicalDescription"]["ru"],
        " ".join(item["semantic"].get("tags", [])),
        item["motion"]["classification"],
        item["identity"]["relativePath"],
    ]).casefold()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("query", nargs="*", help="words from a name, description, tag, or technical class")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--class", dest="motion_class")
    parser.add_argument("--confirmed-only", action="store_true")
    parser.add_argument("--motion-only", action="store_true")
    parser.add_argument("--likely-loop", action="store_true")
    parser.add_argument("--max-seconds", type=float)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    items = json.loads(args.catalog.read_text())["animations"]
    query_tokens = tokens(" ".join(args.query))
    found = []
    for item in items:
        if "error" in item:
            continue
        if args.motion_class and item["motion"]["classification"] != args.motion_class:
            continue
        if args.confirmed_only and item["semantic"]["status"] not in {"confirmed", "fingerprint-confirmed"}:
            continue
        if args.motion_only and not item["eligibility"]["motionOnly"]:
            continue
        if args.likely_loop and not item["motion"]["likelyLoop"]:
            continue
        if args.max_seconds is not None and item["timing"]["durationSeconds"] > args.max_seconds:
            continue
        haystack = searchable(item)
        if query_tokens and not all(token in haystack for token in query_tokens):
            continue
        name = item["semantic"].get("displayName") or item["id"]
        name_text = name.casefold()
        score = sum(40 if token in name_text else 10 for token in query_tokens)
        score += 8 if item["semantic"]["status"] == "confirmed" else 3 if item["semantic"]["status"] == "filename-unverified" else 0
        found.append((score, item))
    found.sort(key=lambda pair: (-pair[0], (pair[1]["semantic"].get("displayName") or pair[1]["id"]).casefold(), pair[1]["id"]))
    selected = [item for _, item in found[:max(0, args.limit)]]

    if args.json:
        print(json.dumps(selected, indent=2, ensure_ascii=False))
        return
    print("ID\tSTATUS\tNAME\tCLASS\tSECONDS\tPATH\tDESCRIPTION")
    for item in selected:
        values = [
            item["id"], item["semantic"]["status"], item["semantic"].get("displayName") or "",
            item["motion"]["classification"], f"{item['timing']['durationSeconds']:.3f}",
            item["identity"]["relativePath"],
            item["semantic"].get("description") or item["technicalDescription"]["ru"],
        ]
        print("\t".join(str(value).replace("\t", " ").replace("\n", " ") for value in values))


if __name__ == "__main__":
    main()
