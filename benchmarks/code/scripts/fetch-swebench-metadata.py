#!/usr/bin/env python3
"""Fetch only public SWE-bench task inputs for the frozen canary subset."""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path


SAFE_FIELDS = (
    "instance_id",
    "repo",
    "base_commit",
    "problem_statement",
    "created_at",
    "version",
)


def get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--subset", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    subset = json.loads(args.subset.read_text(encoding="utf-8"))
    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    wanted = [item["instance_id"] for item in subset["instances"]]
    wanted_set = set(wanted)

    dataset_id = lock["dataset"]["id"]
    dataset_info = get_json(f"https://huggingface.co/api/datasets/{dataset_id}")
    actual_revision = dataset_info.get("sha")
    expected_revision = lock["dataset"]["revision"]
    if actual_revision != expected_revision:
        raise SystemExit(
            f"dataset revision drift: expected {expected_revision}, got {actual_revision}"
        )

    api_id = urllib.parse.quote(dataset_id, safe="")
    found: dict[str, dict] = {}
    for offset in range(0, 500, 100):
        url = (
            "https://datasets-server.huggingface.co/rows"
            f"?dataset={api_id}&config=default&split=test&offset={offset}&length=100"
        )
        for wrapped in get_json(url).get("rows", []):
            row = wrapped["row"]
            if row.get("instance_id") in wanted_set:
                found[row["instance_id"]] = {key: row.get(key) for key in SAFE_FIELDS}

    missing = [instance for instance in wanted if instance not in found]
    if missing:
        raise SystemExit(f"missing frozen instances: {', '.join(missing)}")

    payload = {
        "schema": "code-bench-public-inputs/1.0",
        "dataset": lock["dataset"],
        "instances": [found[instance] for instance in wanted],
    }
    forbidden = {"patch", "test_patch", "FAIL_TO_PASS", "PASS_TO_PASS"}
    if any(forbidden.intersection(instance) for instance in payload["instances"]):
        raise SystemExit("refusing to write gold or hidden-test fields")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE: {len(wanted)} public task inputs -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
