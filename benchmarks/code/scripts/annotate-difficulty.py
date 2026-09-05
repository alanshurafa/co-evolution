#!/usr/bin/env python3
"""Attach SWE-bench Verified difficulty labels to a frozen subset.

SWE-bench Verified carries a human estimate of how long each fix would take:
"<15 min fix", "15 min - 1 hour", "1-4 hours", ">4 hours". The label is a
public field of the dataset (not a gold patch or a hidden test), so it can be
written into the subset file next to each instance. It is what a stratified
draw and a by-difficulty breakdown key on.

The label is read from the same dataset revision the lock file pins, and the
subset records where it came from and when, so a reader can check any label
against the dataset row.
"""
from __future__ import annotations

import argparse
import datetime
import json
import urllib.parse
import urllib.request
from pathlib import Path

BUCKETS = ("<15 min fix", "15 min - 1 hour", "1-4 hours", ">4 hours")


def get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def fetch_labels(dataset_id: str, expected_revision: str, split: str, total: int) -> dict:
    actual = get_json(f"https://huggingface.co/api/datasets/{dataset_id}").get("sha")
    if actual != expected_revision:
        raise SystemExit(f"dataset revision drift: expected {expected_revision}, got {actual}")
    api_id = urllib.parse.quote(dataset_id, safe="")
    labels: dict[str, str] = {}
    for offset in range(0, total, 100):
        url = ("https://datasets-server.huggingface.co/rows"
               f"?dataset={api_id}&config=default&split={split}&offset={offset}&length=100")
        for wrapped in get_json(url).get("rows", []):
            row = wrapped["row"]
            labels[row["instance_id"]] = row.get("difficulty")
    return labels


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--subset", type=Path, action="append", required=True)
    parser.add_argument("--total", type=int, default=500)
    parser.add_argument("--labels-json", type=Path, default=None,
                        help="use a saved {instance_id: difficulty} map instead of the network")
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    dataset = lock["dataset"]
    if args.labels_json:
        labels = json.loads(args.labels_json.read_text(encoding="utf-8"))
        source = str(args.labels_json)
    else:
        labels = fetch_labels(dataset["id"], dataset["revision"], dataset["split"], args.total)
        source = "datasets-server.huggingface.co rows API, field `difficulty`"

    today = datetime.date.today().isoformat()
    for subset_path in args.subset:
        subset = json.loads(subset_path.read_text(encoding="utf-8"))
        missing = []
        for row in subset["instances"]:
            label = labels.get(row["instance_id"])
            if label not in BUCKETS:
                missing.append(row["instance_id"])
                continue
            row["difficulty"] = label
        if missing:
            raise SystemExit(f"{subset_path}: no difficulty label for {', '.join(missing)}")
        counts: dict[str, int] = {}
        for row in subset["instances"]:
            counts[row["difficulty"]] = counts.get(row["difficulty"], 0) + 1
        subset.setdefault("annotations", {})["difficulty"] = {
            "source": source,
            "dataset": dataset["id"],
            "revision": dataset["revision"],
            "fetched_on": today,
            "buckets": list(BUCKETS),
            "counts": {bucket: counts.get(bucket, 0) for bucket in BUCKETS},
            "note": ("Human time-to-fix estimate shipped with SWE-bench Verified. "
                     "A public field, not a gold patch or hidden test."),
        }
        subset_path.write_text(json.dumps(subset, indent=2) + "\n", encoding="utf-8")
        print(f"WROTE: {subset_path} " + ", ".join(
            f"{bucket}={counts.get(bucket, 0)}" for bucket in BUCKETS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
