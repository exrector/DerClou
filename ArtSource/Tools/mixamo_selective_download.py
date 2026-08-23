#!/usr/bin/env python3
"""Search, download, or resumably archive Mixamo motion-only animations.

Exports are deliberately sequential because Mixamo exposes one monitor per
character: concurrent jobs can otherwise receive each other's result. The
access token is read from MIXAMO_ACCESS_TOKEN or a hidden terminal prompt and
is never written to disk.

Mixamo's web API is not a public compatibility contract. Keep this adapter at
the asset-pipeline boundary and expect it to require maintenance if Adobe
changes the site.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


BASE_URL = "https://www.mixamo.com/api/v1"
API_KEY = "mixamo2"
PAGE_SIZE = 96


class MixamoError(RuntimeError):
    pass


@dataclass(frozen=True)
class Motion:
    identifier: str
    name: str


def safe_filename(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._ -]+", "_", value).strip(" .")
    return cleaned or "mixamo-motion"


class MixamoClient:
    def __init__(self, token: str, timeout: float = 30.0) -> None:
        if not token.strip():
            raise MixamoError("Mixamo access token is empty")
        self.token = token.strip()
        self.timeout = timeout

    def request_json(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = f"{BASE_URL}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        payload = None if body is None else json.dumps(body).encode("utf-8")
        headers = {
            "Accept": "application/json",
            "Authorization": f"Bearer {self.token}",
            "X-Api-Key": API_KEY,
            "X-Requested-With": "XMLHttpRequest",
        }
        if payload is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=payload, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")[:800]
            raise MixamoError(f"Mixamo HTTP {error.code} for {path}: {detail}") from error
        except (urllib.error.URLError, TimeoutError) as error:
            raise MixamoError(f"Mixamo request failed for {path}: {error}") from error

    def primary_character(self) -> tuple[str, str]:
        data = self.request_json("GET", "/characters/primary")
        identifier = data.get("primary_character_id")
        if not identifier:
            raise MixamoError(
                "No primary Mixamo character is selected. Open mixamo.com, "
                "select or upload the target humanoid, then retry."
            )
        return str(identifier), str(data.get("primary_character_name") or identifier)

    def search(self, query_text: str) -> list[Motion]:
        page = 1
        motions: list[Motion] = []
        while True:
            data = self.request_json(
                "GET",
                "/products",
                query={
                    "limit": PAGE_SIZE,
                    "page": page,
                    "type": "Motion",
                    "query": query_text,
                },
            )
            results = data.get("results") or []
            for item in results:
                identifier = item.get("id")
                name = item.get("description") or item.get("name")
                if identifier and name:
                    motions.append(Motion(str(identifier), str(name)))

            pagination = data.get("pagination") or {}
            pages = int(pagination.get("num_pages") or page)
            if page >= pages or not results:
                break
            page += 1
        return motions

    def export_motion(self, motion_id: str, character_id: str) -> tuple[str, str, str]:
        product = self.request_json(
            "GET",
            f"/products/{urllib.parse.quote(motion_id)}",
            query={"similar": 0, "character_id": character_id},
        )
        display_name = str(product.get("name") or product.get("description") or motion_id)
        description = str(product.get("description") or "")
        export_name = str(product.get("description") or product.get("name") or motion_id)
        details = product.get("details") or {}
        gms_hash = dict(details.get("gms_hash") or {})
        if not gms_hash:
            raise MixamoError(f"Motion {motion_id} has no export descriptor")

        parameters = gms_hash.get("params") or []
        if isinstance(parameters, list):
            gms_hash["params"] = ",".join(str(item[-1]) for item in parameters)
        if isinstance(gms_hash.get("trim"), list):
            gms_hash["trim"] = [int(value) for value in gms_hash["trim"]]
        gms_hash["overdrive"] = 0

        self.request_json(
            "POST",
            "/animations/export",
            body={
                "character_id": character_id,
                "product_name": export_name,
                "type": product.get("type") or "Motion",
                "preferences": {
                    "format": "fbx7_2019",
                    "skin": False,
                    "fps": "30",
                    "reducekf": "0",
                },
                "gms_hash": [gms_hash],
            },
        )

        deadline = time.monotonic() + 300.0
        while time.monotonic() < deadline:
            status = self.request_json("GET", f"/characters/{character_id}/monitor")
            state = status.get("status")
            if state == "completed" and status.get("job_result"):
                return display_name, description, str(status["job_result"])
            if state == "failed":
                raise MixamoError(
                    f"Export failed for {display_name}: {status.get('message', 'unknown error')}"
                )
            time.sleep(2.0)
        raise MixamoError(f"Export timed out for {display_name}")

    def download(self, url: str, destination: Path) -> None:
        request = urllib.request.Request(url, headers={"User-Agent": "DerClou-AssetPipeline/1"})
        try:
            with urllib.request.urlopen(request, timeout=120.0) as response:
                temporary = destination.with_suffix(destination.suffix + ".partial")
                with temporary.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
                temporary.replace(destination)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as error:
            raise MixamoError(f"Download failed: {error}") from error


def access_token() -> str:
    token = os.environ.get("MIXAMO_ACCESS_TOKEN", "").strip()
    if token:
        return token
    if not sys.stdin.isatty():
        raise MixamoError("Set MIXAMO_ACCESS_TOKEN or run from an interactive terminal")
    return getpass.getpass("Mixamo access token (not stored): ").strip()


def write_receipt(
    path: Path,
    *,
    motion_id: str,
    motion_name: str,
    motion_description: str,
    character: str,
) -> None:
    receipt = {
        "provider": "Adobe Mixamo",
        "motionID": motion_id,
        "motionName": motion_name,
        "motionDescription": motion_description,
        "exportCharacter": character,
        "format": "FBX 7.4/2019, without skin, 30 fps, no key reduction",
        "acquisition": "authenticated project-owned selective downloader",
        "licenseReference": "https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html",
        "rawRedistributionAllowed": False,
    }
    path.with_suffix(path.suffix + ".source.json").write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Search or selectively download motion-only Mixamo FBX files."
    )
    commands = result.add_subparsers(dest="command", required=True)
    search = commands.add_parser("search", help="List matching motion IDs and names")
    search.add_argument("query")
    download = commands.add_parser("download", help="Download one exact motion ID")
    download.add_argument("motion_id")
    download.add_argument("--output", type=Path, required=True)
    bulk = commands.add_parser(
        "bulk", help="Sequentially download every ID from a captured catalog"
    )
    bulk.add_argument("--catalog", type=Path, required=True)
    bulk.add_argument("--output", type=Path, required=True)
    bulk.add_argument("--require-character", default="Y Bot")
    bulk.add_argument("--delay", type=float, default=0.75)
    bulk.add_argument("--retries", type=int, default=4)
    bulk.add_argument("--limit", type=int, help="Optional smoke-test limit")
    return result


def write_state(path: Path, state: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".partial")
    temporary.write_text(
        json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def bulk_download(client: MixamoClient, args: argparse.Namespace) -> None:
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    motions = catalog.get("items") or []
    if int(catalog.get("uniqueCount") or len(motions)) != len(motions):
        raise MixamoError("Catalog count does not match its item list")
    identifiers = [str(item.get("id") or "") for item in motions]
    if not all(identifiers) or len(set(identifiers)) != len(identifiers):
        raise MixamoError("Catalog contains a missing or duplicate motion UUID")

    character_id, character_name = client.primary_character()
    if args.require_character and args.require_character.casefold() not in character_name.casefold():
        raise MixamoError(
            f"Selected Mixamo character is {character_name!r}, expected "
            f"{args.require_character!r}. Select the expected character and retry."
        )

    args.output.mkdir(parents=True, exist_ok=True)
    state_path = args.output / "_bulk-state.json"
    state = {
        "schemaVersion": 1,
        "catalog": str(args.catalog.resolve()),
        "catalogCount": len(motions),
        "characterID": character_id,
        "characterName": character_name,
        "completed": [],
        "failed": {},
    }
    if state_path.exists():
        previous = json.loads(state_path.read_text(encoding="utf-8"))
        if previous.get("characterID") != character_id:
            raise MixamoError("Existing bulk state belongs to a different character")
        state = previous

    completed = set(state.get("completed") or [])
    queue = [item for item in motions if item["id"] not in completed]
    if args.limit is not None:
        queue = queue[: max(0, args.limit)]
    total = len(motions)

    for index, item in enumerate(queue, start=1):
        motion_id = str(item["id"])
        catalog_name = str(item.get("name") or motion_id)
        destination = args.output / f"{safe_filename(catalog_name)}__{motion_id}.fbx"
        receipt = destination.with_suffix(destination.suffix + ".source.json")
        if destination.exists() and receipt.exists():
            completed.add(motion_id)
            state["completed"] = sorted(completed)
            write_state(state_path, state)
            continue

        print(
            f"[{len(completed) + 1}/{total}; queue {index}/{len(queue)}] "
            f"{catalog_name} ({motion_id})",
            flush=True,
        )
        last_error = None
        for attempt in range(1, args.retries + 1):
            try:
                actual_name, description, url = client.export_motion(motion_id, character_id)
                client.download(url, destination)
                write_receipt(
                    destination,
                    motion_id=motion_id,
                    motion_name=actual_name,
                    motion_description=description,
                    character=character_name,
                )
                completed.add(motion_id)
                state["completed"] = sorted(completed)
                state.setdefault("failed", {}).pop(motion_id, None)
                write_state(state_path, state)
                last_error = None
                break
            except MixamoError as error:
                last_error = str(error)
                state.setdefault("failed", {})[motion_id] = {
                    "name": catalog_name,
                    "error": last_error,
                    "attempt": attempt,
                }
                write_state(state_path, state)
                if "HTTP 401" in last_error or "Oauth token is not valid" in last_error:
                    raise MixamoError(
                        "Mixamo token expired. Progress is saved; obtain a fresh token "
                        "and run the same command to resume."
                    ) from error
                if attempt < args.retries:
                    time.sleep(min(30.0, 2.0 ** attempt))
        if last_error is not None:
            print(f"failed after {args.retries} attempts: {last_error}", file=sys.stderr)
        time.sleep(max(0.0, args.delay))

    print(
        f"Bulk queue finished: {len(completed)}/{total} complete; "
        f"{len(state.get('failed') or {})} failed",
        flush=True,
    )


def main() -> int:
    args = parser().parse_args()
    try:
        client = MixamoClient(access_token())
        if args.command == "search":
            for motion in client.search(args.query):
                print(f"{motion.identifier}\t{motion.name}")
            return 0

        if args.command == "bulk":
            bulk_download(client, args)
            return 0

        character_id, character_name = client.primary_character()
        motion_name, motion_description, url = client.export_motion(
            args.motion_id, character_id
        )
        args.output.mkdir(parents=True, exist_ok=True)
        destination = args.output / f"{safe_filename(motion_name)}.fbx"
        if destination.exists():
            raise MixamoError(f"Refusing to overwrite existing file: {destination}")
        client.download(url, destination)
        write_receipt(
            destination,
            motion_id=args.motion_id,
            motion_name=motion_name,
            motion_description=motion_description,
            character=character_name,
        )
        print(destination)
        return 0
    except MixamoError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
