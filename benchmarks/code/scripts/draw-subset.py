#!/usr/bin/env python3
"""Draw a reproducible random subset of a SWE-bench split.

The existing canary subset was hand-pinned, one instance per repository, which
makes it useful for harness development and useless for estimating a score: a
non-random subset cannot be extrapolated to the full split at any sample size.
This draws a uniform random sample instead, from the same revision the lock file
pins, so the result is an unbiased estimate of the full-split score.

The seed is written into the subset file. Re-running with the same seed and the
same dataset revision reproduces the identical sample.
"""
from __future__ import annotations

import argparse
import json
import random
import urllib.parse
import urllib.request
from pathlib import Path


def get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--suite-id", required=True)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--split", default="test")
    parser.add_argument("--total", type=int, default=500)
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    dataset_id = lock["dataset"]["id"]
    expected = lock["dataset"]["revision"]
    actual = get_json(f"https://huggingface.co/api/datasets/{dataset_id}").get("sha")
    if actual != expected:
        raise SystemExit(f"dataset revision drift: expected {expected}, got {actual}")

    api_id = urllib.parse.quote(dataset_id, safe="")
    population: list[dict] = []
    for offset in range(0, args.total, 100):
        url = (
            "https://datasets-server.huggingface.co/rows"
            f"?dataset={api_id}&config=default&split={args.split}"
            f"&offset={offset}&length=100"
        )
        for wrapped in get_json(url).get("rows", []):
            row = wrapped["row"]
            population.append({
                "instance_id": row["instance_id"],
                "repo": row["repo"],
            })

    if len(population) != args.total:
        raise SystemExit(f"expected {args.total} instances, enumerated {len(population)}")
    if args.size > len(population):
        raise SystemExit("sample size exceeds the split")

    # Sort first so the draw depends only on the seed, never on server row order.
    population.sort(key=lambda r: r["instance_id"])
    sample = random.Random(args.seed).sample(population, args.size)
    sample.sort(key=lambda r: r["instance_id"])

    payload = {
        "schema": "code-bench-subset/1.0",
        "suite_id": args.suite_id,
        "sampling": {
            "method": "uniform-random-without-replacement",
            "seed": args.seed,
            "drawn_from": {"dataset": dataset_id, "revision": expected,
                           "split": args.split, "population": len(population)},
            "note": ("A uniform random draw, so the observed score is an unbiased "
                     "estimate of the full-split score with a binomial interval."),
        },
        "instances": sample,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    repos: dict[str, int] = {}
    for row in sample:
        repos[row["repo"]] = repos.get(row["repo"], 0) + 1
    print(f"WROTE: {len(sample)} of {len(population)} -> {args.output}")
    for repo, count in sorted(repos.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {count:3d}  {repo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
