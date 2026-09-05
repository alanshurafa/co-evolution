#!/usr/bin/env python3
"""Build the public observatory from registered, standardized score exports.

No model calls or score recomputation. Legacy pages are never written.
Add future suites to observatory-catalog.json with a code-bench-site/2.0 export.
The output is one portable HTML file, including its data, CSS and JavaScript.
"""
import argparse
import html
import json
import re
from pathlib import Path

SITE = Path(__file__).resolve().parent


def local_file(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing or out-of-root catalog file: {name}")
    return path


def load_catalog(catalog_path, data_dir):
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    if catalog.get("schema") != "eval-observatory-catalog/1.0":
        raise ValueError("Unsupported observatory catalog schema")
    suites, ids = [], set()
    for entry in catalog["suites"]:
        if entry["id"] in ids:
            raise ValueError(f"Duplicate suite: {entry['id']}")
        ids.add(entry["id"])
        data = json.loads(local_file(data_dir, entry["data"]).read_text(encoding="utf-8"))
        if data.get("schema") != "code-bench-site/2.0":
            raise ValueError(f"Unsupported score export: {entry['data']}")
        if data["suite"]["id"] != entry["id"]:
            raise ValueError(f"Suite identity mismatch: {entry['id']}")
        local_file(data_dir, entry["methodology"])
        if entry.get("default_run") not in {r["label"] for r in data["runs"]}:
            raise ValueError(f"Default run missing from {entry['id']}")
        suites.append({**entry, "results": data})
    if catalog["default_suite"] not in ids:
        raise ValueError("Default suite is not registered")
    for archive in catalog.get("archives", []):
        local_file(data_dir, archive["href"])
    return {**catalog, "suites": suites}


def render(catalog):
    template = (SITE / "observatory.html").read_text(encoding="utf-8")
    suite = next(s for s in catalog["suites"] if s["id"] == catalog["default_suite"])
    eligible = [r for r in suite["results"]["rows"] if r.get("score") and r["score"].get("rate") is not None
                and r.get("complete") and r.get("provenance", {}).get("publishable") is True
                and r["run_label"] == suite["default_run"] and r["tier"] == "agentic"]
    fallback = "".join(
        f'<li>{html.escape(r["configuration"])}: '
        f'{r["score"]["rate"]:.0%} ({r["score"]["resolved"]}/{r["score"]["n"]})</li>'
        for r in sorted(eligible, key=lambda r: r["score"]["rate"], reverse=True))
    # A data value can contain </script>; escape before embedding in HTML.
    payload = json.dumps(catalog, ensure_ascii=True, separators=(",", ":"), allow_nan=False)
    payload = payload.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    replacements = {
        "__STYLE__": (SITE / "observatory.css").read_text(encoding="utf-8"),
        "__SCRIPT__": (SITE / "observatory-data.js").read_text(encoding="utf-8") + "\n" + (SITE / "observatory.js").read_text(encoding="utf-8"),
        "__DATA__": payload,
        "__FALLBACK__": fallback or "<li>No completed, publishable results yet.</li>",
    }
    # Single-pass replacement also preserves literal placeholder-like text
    # inside an exported model label or source note.
    return re.sub('|'.join(map(re.escape, replacements)),
                  lambda match: replacements[match.group(0)], template)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=SITE / "observatory-catalog.json")
    parser.add_argument("--data-dir", type=Path, default=SITE / "public")
    parser.add_argument("--output", type=Path, default=SITE / "public" / "index.html")
    args = parser.parse_args()
    catalog = load_catalog(args.catalog, args.data_dir)
    output = render(catalog)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8", newline="\n")
    print(args.output)


if __name__ == "__main__":
    main()
