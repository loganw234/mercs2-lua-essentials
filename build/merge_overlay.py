#!/usr/bin/env python3
"""build/merge_overlay.py -- assemble per-namespace overlay fragments into api/nodes.overlay.json.

The node overlay (the hand-authored half of the node definitions -- see build/nodes.py) is written in
batches, one per namespace group, because that is the only way to actually READ the source for 548 functions
rather than guess at them. This merges those fragments into the single committed overlay, and refuses to
merge anything that doesn't match the real API.

It validates BEFORE writing, not after, and it validates against dist/ess.json rather than against itself:
  * a fragment naming a function that doesn't exist        -> rejected
  * a fragment giving a function a param it doesn't have   -> rejected
  * two fragments claiming the same function               -> rejected (a batching mistake, not a merge)
  * a type or kind outside the allowed vocabulary          -> rejected

That matters because the fragments are written from source-reading, and source-reading can misremember a
parameter name. Nothing hand-written reaches the overlay without being checked against the generated truth.

Usage:
  python build/merge_overlay.py <fragment.json> [more.json ...]     # merge into api/nodes.overlay.json
  python build/merge_overlay.py --dir DIR                           # merge every *.overlay.json in DIR
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = ROOT / "api"
DIST = ROOT / "dist"
OUT = API / "nodes.overlay.json"

VALID_TYPES = {"number", "string", "guid", "bool", "table", "function", "lua"}
VALID_KINDS = {"action", "getter"}


def check_fragment(name, frag, real, claimed):
    problems = []
    for call, entry in sorted(frag.items()):
        if call.startswith("_"):
            continue
        if call not in real:
            problems.append("%s: %s is not a real function" % (name, call))
            continue
        if call in claimed:
            problems.append("%s: %s was already covered by %s (batching overlap)" % (name, call, claimed[call]))
            continue
        claimed[call] = name
        if not isinstance(entry, dict):
            problems.append("%s: %s is not an object" % (name, call))
            continue
        if entry.get("skip"):
            continue
        real_params = list(real[call]["params"])
        for pname, p in (entry.get("params") or {}).items():
            if pname not in real_params:
                problems.append("%s: %s has no param %r (real signature: %s)"
                                % (name, call, pname, ", ".join(real_params) or "none"))
            elif p.get("type") not in VALID_TYPES:
                problems.append("%s: %s.%s type %r not allowed" % (name, call, pname, p.get("type")))
        if entry.get("kind") and entry["kind"] not in VALID_KINDS:
            problems.append("%s: %s kind %r not allowed" % (name, call, entry["kind"]))
        for r in entry.get("returns") or []:
            if not isinstance(r, dict) or not r.get("name"):
                problems.append("%s: %s has a return with no name" % (name, call))
            elif r.get("type") not in VALID_TYPES:
                problems.append("%s: %s return %r type %r not allowed"
                                % (name, call, r.get("name"), r.get("type")))
    return problems


def main():
    ap = argparse.ArgumentParser(description="Merge node-overlay fragments into api/nodes.overlay.json.")
    ap.add_argument("fragments", nargs="*", help="fragment .json files")
    ap.add_argument("--dir", help="merge every *.overlay.json in this directory instead")
    args = ap.parse_args()

    ess_path = DIST / "ess.json"
    if not ess_path.exists():
        print("[overlay] dist/ess.json missing -- run `python build/manifest.py` first")
        sys.exit(1)
    real = json.loads(ess_path.read_text(encoding="utf-8"))["functions"]

    paths = [pathlib.Path(p) for p in args.fragments]
    if args.dir:
        paths += sorted(pathlib.Path(args.dir).glob("*.overlay.json"))
    paths = [p for p in paths if p.exists()]
    if not paths:
        print("[overlay] no fragments found")
        sys.exit(1)

    merged, claimed, problems = {}, {}, []
    for p in paths:
        try:
            frag = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            problems.append("%s: not valid JSON -- %s" % (p.name, exc))
            continue
        problems += check_fragment(p.name, frag, real, claimed)
        for call, entry in frag.items():
            if not call.startswith("_"):
                merged[call] = entry

    if problems:
        print("[overlay] REFUSING TO MERGE -- %d problem(s):" % len(problems))
        for prob in sorted(set(problems))[:40]:
            print("  - " + prob)
        if len(set(problems)) > 40:
            print("  ... and %d more" % (len(set(problems)) - 40))
        sys.exit(1)

    existing = {}
    if OUT.exists():
        existing = json.loads(OUT.read_text(encoding="utf-8")).get("functions", {})
    existing.update(merged)

    payload = {
        "_comment": "Hand-authored node metadata, merged from per-namespace fragments by "
                    "build/merge_overlay.py and validated against dist/ess.json. build/nodes.py combines "
                    "this with ess.json to produce dist/nodes.json. Edit THIS file (or a fragment), never "
                    "ess.json -- that one is regenerated from src/ on every build.",
        "skip_namespaces": [],
        "functions": dict(sorted(existing.items())),
    }
    API.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")

    skipped = sum(1 for e in existing.values() if e.get("skip"))
    print("[overlay] merged %d fragment(s) -> %s" % (len(paths), OUT))
    print("[overlay] %d functions described (%d marked skip), all validated against ess.json"
          % (len(existing), skipped))


if __name__ == "__main__":
    main()
