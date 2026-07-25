#!/usr/bin/env python3
"""build/manifest.py -- generate dist/ess.json, the machine-readable manifest of Ess's public API.

Offline: parses src/*.lua, needs no game (tools/dump_natives.py is the live counterpart that emits
natives.json -- ess.json is "what Ess gives you", natives.json is "what exists at all").

WHY THIS EXISTS
Ess's API surface was described in FOUR hand-maintained places: CAPABILITIES.md's tables, FEATURE_SHEET.md,
96_console.lua's in-game REGISTRY, and ~200 node definitions in the mercs2-ess-visual editor. Every one was
in sync, which is genuinely impressive for 434 functions -- and rests entirely on somebody remembering. That
does not scale, and a silent divergence between the in-game console and the real functions is exactly the
kind of bug nobody notices until a beginner types something that doesn't exist. One generated file, derived
from the source itself, means the others can be generated from it or checked against it.

WHAT IS AUTHORITATIVE
The FUNCTION DEFINITIONS are. A function exists because `function Ess.X.y(...)` appears in src/, full stop --
never because a doc mentions it. Header comments supply the human description and the documented return
shape on top of that. So a helper that exists but is undocumented shows up in the manifest with
`"documented": false` (which is a useful lint in itself), and a doc line naming a function that doesn't exist
is reported by --check as drift rather than being quietly believed.

THE HEADER-COMMENT GRAMMAR it reads, already the de-facto convention in 51 of the 78 src files:

    --   Ess.Foo.bar(arg1, arg2) -> ret1, ret2      one-line description
    --   Ess.Foo.baz(arg)                            description with no documented return
    --                                               a continuation line, indented past the call column

WHAT --check ACTUALLY COVERS, and what it doesn't
Four hand-written surfaces are checked against the real function set: 96_console.lua's in-game REGISTRY,
CAPABILITIES.md's fully-qualified `Ess.X.y(` mentions, every src/ header-comment API line, and every call in
samples/ (recipes and demos -- these are the living documentation and the smoke test, so a rename that
orphans one is a real break, and catching it here takes seconds instead of waiting for a machine with the game
open).

The remaining blind spot, stated plainly: a function that is renamed or deleted while being mentioned NOWHERE
except in prose, or only via an abbreviated `.method` reference inside a CAPABILITIES.md table cell, is not
caught. Both were verified by deliberately breaking them -- an early version of this gate missed a renamed
`Ess.Object.heal` entirely, because its only documentation was the prose comment above it rather than a header
API line. Adding the samples/ sweep closed that particular case (8 call sites flagged), but the general
limitation stands: the gate proves that everything NAMED resolves, not that everything real is named.

Usage:
  python build/manifest.py              # write dist/ess.json
  python build/manifest.py --check      # verify the doc surfaces name only real functions; exit 1 on drift
"""
import argparse
import datetime
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"

# `local M = Ess.Math` at the top of a file, then `function M.clamp(...)` below it. Ten files do this, so a
# parser that only understands `function Ess.` misses whole namespaces (Math, Str, Color, Vec, Layers, Net,
# and all four Contract files).
ALIAS_RE = re.compile(r"^local\s+([A-Za-z_]\w*)\s*=\s*(Ess(?:\.[A-Za-z_]\w*)*)\s*$", re.M)

# `function Ess.Object.spawn(a, b)` / `function Ess.RNG:pick(list)` / `function M.clamp(n)`
# Leading whitespace allowed: a definition can legitimately sit inside an `if` guard (98_stop.lua defines
# Ess.Track:any that way, and the column-zero-only version of this pattern reported it as documented-but-
# undefined). Factory-local object methods (`function sl:add`) are still excluded further down, by the
# owner-must-resolve-to-Ess check rather than by indentation.
DEF_RE = re.compile(r"^[ \t]*function\s+([A-Za-z_][\w.]*)([.:])([A-Za-z_]\w*)\s*\(([^)]*)\)", re.M)

# `Ess.Save.holders = function()` and `Ess.Easy.Objective = setmetatable({}, { __call = function(_, a, b)`
ASSIGN_RE = re.compile(r"^\s*(Ess(?:\.[A-Za-z_]\w*)+)\s*=\s*function\s*\(([^)]*)\)", re.M)
CALLABLE_RE = re.compile(
    r"^\s*(Ess(?:\.[A-Za-z_]\w*)+)\s*=\s*setmetatable\([^)]*\{\s*__call\s*=\s*function\s*\(\s*_\s*,?([^)]*)\)", re.M)

# A plain function-REFERENCE alias: `Ess.Time.since = Ess.Time.elapsed`, `Ess.Squad.on = Ess.Followers.on`.
# Real, working, documented public API that no other pattern here catches, because there is no `function`
# keyword anywhere on the line. Found by --check flagging both of them as documented-but-undefined on its
# very first run -- the gate's first catch was a hole in this parser rather than a bug in the framework.
REF_ALIAS_RE = re.compile(r"^\s*(Ess(?:\.[A-Za-z_]\w*)+)\s*=\s*(Ess(?:\.[A-Za-z_]\w*)+)\s*$", re.M)

# A header-comment API line. Captures: call path, args, optional `-> returns`, trailing description.
DOC_RE = re.compile(
    r"^--\s{2,}(Ess[\w.]*[.:]\w+|Ess)\s*\(([^)]*)\)\s*(?:->\s*([^\s].*?))?(?:\s{2,}(.*))?$")


def tier_of(path):
    if path.startswith("Ess.Easy"):
        return "easy"
    if path.startswith("Ess.Raw"):
        return "raw"
    return "core"


def namespace_of(path):
    parts = path.split(".")
    # Ess.Easy.Mark.enemy -> Ess.Easy.Mark ; Ess.Object.spawn -> Ess.Object ; Ess.State -> Ess
    return ".".join(parts[:-1]) if len(parts) > 1 else "Ess"


def parse_docs(text):
    """-> {callPath: {"args", "returns", "desc"}} from a file's header/section comments."""
    docs = {}
    lines = text.splitlines()
    last = None
    for line in lines:
        m = DOC_RE.match(line)
        if m:
            path = m.group(1).replace(":", ".")
            docs[path] = {
                "args": m.group(2).strip(),
                "returns": (m.group(3) or "").strip().rstrip(" -"),
                "desc": (m.group(4) or "").strip(),
            }
            last = path
            continue
        # Continuation: an indented comment line under a doc entry that had no description yet, or one that
        # wraps. Only joins while the run of comment lines is unbroken.
        if last and re.match(r"^--\s{4,}\S", line) and not line.lstrip("- ").startswith("Ess"):
            extra = line.lstrip("-").strip()
            if extra and not extra.startswith("="):
                d = docs[last]
                d["desc"] = (d["desc"] + " " + extra).strip()
            continue
        if not line.startswith("--"):
            last = None
    return docs


def collect():
    functions, doc_by_path, problems, ref_aliases = {}, {}, [], []
    for path in sorted(SRC.glob("*.lua")):
        text = path.read_text(encoding="utf-8", errors="replace")
        aliases = {m.group(1): m.group(2) for m in ALIAS_RE.finditer(text)}
        doc_by_path.update(parse_docs(text))

        offsets = [0]
        for line in text.splitlines():
            offsets.append(offsets[-1] + len(line) + 1)

        def line_of(pos):
            lo, hi = 0, len(offsets) - 1
            while lo < hi:
                mid = (lo + hi + 1) // 2
                if offsets[mid] <= pos:
                    lo = mid
                else:
                    hi = mid - 1
            return lo + 1

        # The comment block sitting directly above each `function` line, as a fallback description. This
        # matters more than it sounds: this codebase documents most helpers in prose right above the
        # definition rather than in the file-header API list, so header-grammar-only parsing reported 58% of
        # the framework as "undocumented" when it is nothing of the sort. First sentence only -- these blocks
        # run to twenty lines of engine archaeology, which belongs in the source, not a manifest field.
        lines = text.splitlines()
        preceding = {}
        for idx, line in enumerate(lines):
            if not line.startswith("function") and not re.match(r"^\s*Ess[\w.]+\s*=\s*(function|setmetatable)", line):
                continue
            block, j = [], idx - 1
            while j >= 0 and lines[j].lstrip().startswith("--"):
                stripped = lines[j].lstrip()[2:].strip()
                if set(stripped) <= {"=", "-", ""} and stripped:
                    break  # a ==== separator rule: the block above it belongs to the section, not this fn
                block.append(stripped)
                j -= 1
            block.reverse()
            prose = " ".join(b for b in block if b)
            # Drop a leading signature restatement ("Ess.Foo.bar(x) -> y -- real description").
            prose = re.sub(r"^Ess[\w.:]*\([^)]*\)(\s*->[^-]*)?(\s*--\s*)?", "", prose).strip()
            m_sent = re.match(r"(.{15,400}?[.!])(\s|$)", prose)
            if prose:
                preceding[idx + 1] = (m_sent.group(1) if m_sent else prose[:400]).strip()

        found = []
        for m in DEF_RE.finditer(text):
            owner, sep, name, args = m.group(1), m.group(2), m.group(3), m.group(4)
            if owner in aliases:
                owner = aliases[owner]
            elif not owner.startswith("Ess"):
                continue  # a factory-local object method (`function sl:add`) -- not top-level API
            found.append((owner + "." + name, args, sep == ":", m.start()))
        for m in ASSIGN_RE.finditer(text):
            found.append((m.group(1), m.group(2), False, m.start()))
        for m in CALLABLE_RE.finditer(text):
            found.append((m.group(1), m.group(2), False, m.start()))
        # Deferred to a second pass: the target may be defined in a file merged earlier, so it is not
        # necessarily in `functions` yet at this point.
        for m in REF_ALIAS_RE.finditer(text):
            # `Ess.RNG.__index = Ess.RNG` is metatable plumbing for the `:method()` classes, not API -- it
            # matches this pattern exactly but the target is a TABLE, not a function.
            if m.group(1).split(".")[-1].startswith("__"):
                continue
            ref_aliases.append((m.group(1), m.group(2), path.name, line_of(m.start())))

        for full, args, is_method, pos in found:
            if full in functions:
                problems.append("duplicate definition of %s (%s and %s)"
                                % (full, functions[full]["file"], path.name))
            functions[full] = {
                "prose": preceding.get(line_of(pos), ""),
                "namespace": namespace_of(full),
                "tier": tier_of(full),
                "params": [a.strip() for a in args.split(",") if a.strip()],
                "method": is_method,
                "file": path.name,
                "line": line_of(pos),
            }

    # Resolve reference aliases now that every real definition is known. The alias inherits its target's
    # signature (it IS the same function) but keeps its own file/line and records what it points at.
    for name, target, fname, lineno in ref_aliases:
        if name in functions:
            continue
        base = functions.get(target)
        if not base:
            problems.append("%s aliases %s, which is not defined (%s:%d)" % (name, target, fname, lineno))
            continue
        functions[name] = {
            "prose": base.get("prose", ""),
            "namespace": namespace_of(name),
            "tier": tier_of(name),
            "params": list(base["params"]),
            "method": base["method"],
            "alias_of": target,
            "file": fname,
            "line": lineno,
        }

    for full, entry in functions.items():
        doc = doc_by_path.get(full)
        header_desc = (doc or {}).get("desc", "")
        prose = entry.pop("prose", "")
        # The file-header API list wins when it has a description -- it is the deliberately-written one-liner.
        # Prose above the definition is the fallback, and `doc_source` says which you got, so a consumer can
        # tell a curated summary from a scraped first sentence.
        entry["description"] = header_desc or prose
        entry["doc_source"] = "header" if header_desc else ("prose" if prose else "none")
        entry["documented"] = bool(entry["description"])
        entry["returns"] = (doc or {}).get("returns", "")
    return functions, doc_by_path, problems


def build(functions, problems):
    by_ns, by_tier = {}, {"easy": 0, "core": 0, "raw": 0}
    for full, e in functions.items():
        by_ns.setdefault(e["namespace"], []).append(full)
        by_tier[e["tier"]] += 1
    version = re.search(r'Ess\.VERSION\s*=\s*"([^"]+)"',
                        (SRC / "00_core.lua").read_text(encoding="utf-8")).group(1)
    documented = sum(1 for e in functions.values() if e["documented"])
    return {
        "_comment": "Generated by build/manifest.py from src/*.lua. Do not hand-edit -- the function "
                    "definitions in src/ are authoritative, this is derived. natives.json (see "
                    "tools/dump_natives.py) is the companion catalogue of the raw engine surface.",
        "version": version,
        "generated": datetime.date.today().isoformat(),
        "tiers": {
            "easy": "Ess.Easy.* -- guardrails. Intent-named presets, smallest surface, hard to misuse.",
            "core": "Ess.* -- named parameters and full control. The bulk of the framework.",
            "raw": "Ess.Raw.* -- the primitives the other tiers are assembled from.",
        },
        "counts": {
            "functions": len(functions),
            "namespaces": len(by_ns),
            "by_tier": by_tier,
            "documented": documented,
            "undocumented": len(functions) - documented,
        },
        "namespaces": {ns: sorted(v) for ns, v in sorted(by_ns.items())},
        "functions": {k: functions[k] for k in sorted(functions)},
        "parse_problems": problems,
    }


def check(functions, doc_by_path):
    """Verify every OTHER surface that names an Ess function names a real one. This is the actual drift gate:
    ess.json can't drift from src/ (it's generated from it), but the in-game console, CAPABILITIES.md and the
    per-file header comments are all hand-written and CAN."""
    real = set(functions)
    # Namespaces are legitimately referenced without a function name (e.g. "Ess.UI" in prose), and a few
    # entries are callable tables rather than plain functions.
    real_prefixes = {".".join(f.split(".")[:i]) for f in real for i in range(1, len(f.split(".")) + 1)}
    failures = []

    console = (SRC / "96_console.lua").read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r'usage\s*=\s*"([^"]+)"', console):
        for call in re.findall(r"(Ess[\w.]*\.\w+)\s*\(", m.group(1)):
            if call not in real and call not in real_prefixes:
                failures.append("96_console.lua REGISTRY names %s, which is not defined in src/" % call)

    caps = ROOT / "CAPABILITIES.md"
    if caps.exists():
        for m in re.finditer(r"`(Ess[\w.]*\.\w+)\(", caps.read_text(encoding="utf-8", errors="replace")):
            if m.group(1) not in real and m.group(1) not in real_prefixes:
                failures.append("CAPABILITIES.md names %s, which is not defined in src/" % m.group(1))

    for path, _ in doc_by_path.items():
        if path not in real and path not in real_prefixes:
            failures.append("a src/ header comment documents %s, which is not defined" % path)

    # samples/ -- recipes and demos are the framework's living documentation AND its smoke test, so a rename
    # that orphans one is a real break. Catching it statically here means CI reports it in seconds instead of
    # it surfacing as a runtime error on the next machine that happens to have the game open.
    for path in sorted((ROOT / "samples").rglob("*.lua")):
        text = path.read_text(encoding="utf-8", errors="replace")
        code = "\n".join(re.sub(r"--.*$", "", line) for line in text.splitlines())
        for m in re.finditer(r"\b(Ess(?:\.[A-Za-z_]\w*)+)\s*\(", code):
            call = m.group(1)
            if call not in real and call not in real_prefixes:
                failures.append("samples/%s calls %s, which is not defined in src/"
                                % (path.relative_to(ROOT / "samples").as_posix(), call))
    return failures


def main():
    ap = argparse.ArgumentParser(description="Generate or verify dist/ess.json.")
    ap.add_argument("--check", action="store_true",
                    help="verify the hand-written doc surfaces name only real functions; exit 1 on drift")
    args = ap.parse_args()

    functions, doc_by_path, problems = collect()

    if args.check:
        failures = check(functions, doc_by_path) + problems
        if failures:
            print("[manifest] API DRIFT -- %d problem(s):" % len(failures))
            for f in sorted(set(failures)):
                print("  - " + f)
            sys.exit(1)
        print("[manifest] no drift: %d functions, every documented name resolves." % len(functions))
        return

    manifest = build(functions, problems)
    DIST.mkdir(exist_ok=True)
    (DIST / "ess.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    c = manifest["counts"]
    print("[manifest] wrote %s" % (DIST / "ess.json"))
    print("[manifest]   %d functions across %d namespaces (v%s)"
          % (c["functions"], c["namespaces"], manifest["version"]))
    print("[manifest]   tiers: easy %d / core %d / raw %d"
          % (c["by_tier"]["easy"], c["by_tier"]["core"], c["by_tier"]["raw"]))
    print("[manifest]   documented: %d, undocumented: %d" % (c["documented"], c["undocumented"]))
    if problems:
        print("[manifest]   %d parse problem(s) -- see parse_problems in the json" % len(problems))


if __name__ == "__main__":
    main()
