#!/usr/bin/env python3
"""tools/dump_natives.py -- enumerate the LIVE game's entire Lua function surface and emit natives.json.

Needs the game running with the lua-bridge up (same prerequisite as tools/lua_repl.py and tools/smoke.py).
This is a `tools/` script, not a `build/` step, for exactly that reason: build/ is offline, tools/ needs the
game. `build/manifest.py` (ess.json) is the offline counterpart -- ess.json says "what Ess gives you",
natives.json says "what exists at all", and the gap between them is the interesting part.

WHY A LIVE DUMP AND NOT A CORPUS SCRAPE
The decompiled corpus (docs/mercs2-luacd/src) only shows what the shipped game SCRIPTS call. It cannot show
a C++ native nobody happened to call, and it cannot tell you a namespace's real arity or even that it
exists. A `pairs(_G)` walk inside the running VM is the ground truth for what is actually callable. (The
wiki's own Object reference was built the same way -- and this dump independently reproduces its count of
exactly 87 Object functions, which is the check that says the walk is working.)

WHY THE LOG IS THE TRANSPORT
This engine has no `io` library -- CONFIRMED LIVE 2026-07-25, `type(_G.io) == "nil"` -- so the dumped chunk
cannot write a file itself. And lua_repl.py's own result channel is single-line only. So the chunk emits
tagged `[NDUMP]` lines through Loader.Printf (batched, several names per line) and this script reads them
back out of lua_loader_printf.log by byte offset. Same append-only-file-as-truth design lua_repl.py settled
on, for the same reason.

ENGINE NATIVE vs RESIDENT GAME SCRIPT -- the classification, and the evidence for it
Not everything callable is a C++ native. The game's own resident Lua modules (mrxutil.lua, mrxpmc.lua, ...)
declare BARE GLOBAL functions, and the engine's `import("MrxUtil")` machinery namespaces them into
`MrxUtil.*` at load time. The live `_MODULES` table IS that registry, keyed by lowercase filename -- so a
namespace whose lowercased name appears in `_MODULES` is game script with readable source in the corpus,
and one that doesn't is a genuine C++ native with no source anywhere. Measured on this install: 186 resident
modules (185 with a matching corpus .lua), 43 native namespaces, 18 script-backed ones.

That distinction is the practically useful one. A native is a black box you probe; a script-backed function
has source you can just read.

Usage:
  python tools/dump_natives.py                    # -> api/natives.json (commit it)
  python tools/dump_natives.py --export DIR       # also write a human-readable NATIVES.md there
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# COMMITTED, not in gitignored dist/. natives.json is captured from an external system (a running game), not
# derived from this repo's source -- so CI physically cannot regenerate it, and a gitignored copy would simply
# be absent from every release zip. It also changes essentially never: only if the game or bridge changes.
# ess.json is the opposite case and stays in dist/, regenerated on every build so it can never go stale.
API = ROOT / "api"
SRC = ROOT / "src"
DEFAULT_GAME_DIR = pathlib.Path(r"C:\Games\Mercenaries 2 World in Flames")
CORPUS = pathlib.Path.home() / "Desktop" / "Mercs2_Decompiled_Lua" / "docs" / "mercs2-luacd" / "src"

# Namespaces to leave out of natives.json entirely.
#   Ess          -- this framework; ess.json is its manifest, listing it here would just duplicate it
#   _G           -- _G contains itself, so every namespace also appears as "_G.Whatever". Pure noise.
#   math/string/table/os/coroutine -- Lua's own stdlib, not this engine's surface
# NOTE the capitalised Math/String/Table are NOT excluded: those are separate engine-provided namespaces
# that genuinely exist here alongside the lowercase stdlib ones.
#
# `_MODULES` is deliberately NOT in this list, despite being the classifier and despite its underscore. An
# earlier version excluded it wholesale and silently dropped 104 REAL modules -- antiair, helicopter, hero,
# collectable, ... -- because those are reachable ONLY as `_MODULES.<name>`: they're loaded, but nothing in
# the current game state has `import()`ed them, so no top-level global exists to find them under. They are
# ordinary callable Lua with readable source, so they belong in the manifest. The bare `_MODULES` table
# itself is skipped (it holds only sub-tables, no functions of its own).
EXCLUDE_PREFIX = ("_G", "Ess")
EXCLUDE_EXACT = {"math", "string", "table", "os", "coroutine", "io", "debug", "package", "_MODULES"}

DUMP_CHUNK = r"""
-- Walk _G and emit every namespace's function names through Loader.Printf. Batched several names per line
-- to keep the emitted line count (and so the log-parse cost) sane. Every pairs() over a native-backed table
-- is pcall'd: iterating one is not guaranteed safe on this engine, and a diagnostic dump must never be the
-- thing that takes the game down.
local function emit(prefix, names)
    table.sort(names)
    local buf, n = {}, 0
    for _, nm in ipairs(names) do
        buf[#buf + 1] = nm
        n = n + #nm + 1
        if n > 180 then
            Loader.Printf("[NDUMP] " .. prefix .. "|" .. table.concat(buf, ","))
            buf, n = {}, 0
        end
    end
    if #buf > 0 then Loader.Printf("[NDUMP] " .. prefix .. "|" .. table.concat(buf, ",")) end
end

-- DEDUPE BY TABLE IDENTITY, not by name. The engine's module system (`import("MrxUtil")`) puts the SAME
-- table onto every module that imports it, and every module also self-references as `_THIS` -- so a
-- name-based walk reports MrxUtil eleven times (MrxPmc.MrxUtil, MrxHqManager.MrxUtil, ...), and `oPda` is
-- literally the same table as `Pda` (confirmed live: `oPda == Pda` is true). Meanwhile some same-NAMED
-- tables are genuinely different objects -- also confirmed live, `SubtitleBuffer ~= Pda.SubtitleBuffer` and
-- `ObjectiveTray ~= Hud.ObjectiveTray` -- so deduping on names would have been wrong in both directions.
-- Keying a `seen` set on the table itself is exact and needs no guessing.
local seen = {}

local function collect(tbl)
    local fns, subs = {}, {}
    pcall(function()
        for k, v in pairs(tbl) do
            if type(v) == "function" then fns[#fns + 1] = tostring(k)
            elseif type(v) == "table" and type(k) == "string" then subs[#subs + 1] = k end
        end
    end)
    table.sort(subs)
    return fns, subs
end

local nsNames, topFns = {}, {}
for k, v in pairs(_G) do
    if type(v) == "function" then topFns[#topFns + 1] = tostring(k)
    elseif type(v) == "table" and type(k) == "string" then nsNames[#nsNames + 1] = k end
end
table.sort(nsNames)
emit("_G", topFns)

-- PASS 1: every top-level namespace, alphabetically. Going wide before going deep is what makes the
-- canonical name the top-level one -- `MrxUtil` claims the table before `MrxPmc.MrxUtil` can.
local pending = {}
for _, nsName in ipairs(nsNames) do
    local ns = _G[nsName]
    if seen[ns] then
        Loader.Printf("[NALIAS] " .. nsName .. "|" .. seen[ns])
    else
        seen[ns] = nsName
        local fns, subs = collect(ns)
        if #fns > 0 then emit(nsName, fns) end
        for _, subName in ipairs(subs) do pending[#pending + 1] = { nsName, subName } end
    end
end

-- PASS 2: one level deep. Graphics.Camera / Graphics.Effect / Hud.* are real, separately-namespaced tables
-- Ess already calls through and would otherwise be invisible; the import cross-references that share this
-- shape are filtered out by `seen` rather than by a name heuristic.
for _, pair in ipairs(pending) do
    local nsName, subName = pair[1], pair[2]
    local parent = _G[nsName]
    local sub = parent and parent[subName]
    if type(sub) == "table" then
        local full = nsName .. "." .. subName
        if seen[sub] then
            Loader.Printf("[NALIAS] " .. full .. "|" .. seen[sub])
        else
            seen[sub] = full
            local sfns = collect(sub)
            if #sfns > 0 then emit(full, sfns) end
        end
    end
end
Loader.Printf("[NDUMP] __END__|")
return "dumped"
"""


def log_path(game_dir):
    return pathlib.Path(game_dir) / "scripts" / "lua_loader_printf.log"


def run_dump(game_dir):
    """Send DUMP_CHUNK into the live game, return the log text it produced."""
    log = log_path(game_dir)
    before = log.stat().st_size if log.exists() else 0
    tmp = pathlib.Path(os.environ.get("TEMP", "/tmp")) / "ess_dump_natives_chunk.lua"
    tmp.write_text(DUMP_CHUNK, encoding="utf-8")
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "lua_repl.py"), "--file", str(tmp),
         "--game-dir", str(game_dir)],
        capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    if "OK: dumped" not in out:
        print("[natives] the dump chunk did not report success. lua_repl said:")
        print("  " + out.strip().replace("\n", "\n  "))
        print("[natives] is the game running with the bridge up? try: python tools/lua_repl.py --probe")
        sys.exit(1)
    raw = log.read_bytes()[before:].decode("utf-8", "replace")
    if "__END__" not in raw:
        print("[natives] dump looks truncated -- no __END__ marker in the new log content.")
        sys.exit(1)
    return raw


def parse_dump(raw):
    """-> ({namespace: [fn, ...]}, {aliasName: canonicalName})"""
    ns = {}
    for m in re.finditer(r"\[NDUMP\] ([^|\r\n]+)\|([^\r\n]*)", raw):
        key, names = m.group(1), [n for n in m.group(2).split(",") if n]
        if key == "__END__":
            continue
        ns.setdefault(key, set()).update(names)
    aliases = {m.group(1): m.group(2)
               for m in re.finditer(r"\[NALIAS\] ([^|\r\n]+)\|([^\r\n]*)", raw)}
    return {k: sorted(v) for k, v in ns.items()}, aliases


def ess_called_names():
    """Every `Namespace.Fn` that Ess's own source references -- the coverage signal.

    Matches a bare REFERENCE, not just a call. That distinction is the whole ballgame here: Ess's dominant
    shape is `pcall(Object.GetPosition, char)`, which passes the function as a value with a COMMA after it,
    not a `(`. An earlier version of this required a following paren and so counted only 7 of Object's 87
    functions as covered, when the real figure is several times that -- it was silently measuring "direct
    calls" and labelling the answer "coverage".

    Comments are stripped first, so a function named only in a doc header doesn't count as called.
    """
    called = set()
    ref = re.compile(r"\b([A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)?)\.([A-Za-z_]\w*)\b")
    for p in SRC.glob("*.lua"):
        text = p.read_text(encoding="utf-8", errors="replace")
        code = "\n".join(re.sub(r"--.*$", "", line) for line in text.splitlines())
        for m in ref.finditer(code):
            if not m.group(1).startswith("Ess"):
                called.add(m.group(1) + "." + m.group(2))
    return called


def build(dump, aliases, game_dir):
    modules = sorted({k.split(".", 1)[1].lower() for k in dump if k.startswith("_MODULES.")})
    # _MODULES itself is aliased away by the identity dedupe if it was seen first, so also recover module
    # names from the alias log -- otherwise the classifier silently loses its evidence base.
    for a, canon in aliases.items():
        for name in (a, canon):
            if name.startswith("_MODULES."):
                modules.append(name.split(".", 1)[1].lower())
    modules = sorted(set(modules))
    corpus_stems = {}
    if CORPUS.exists():
        for p in CORPUS.rglob("*.lua"):
            corpus_stems.setdefault(p.stem.lower(), str(p.relative_to(CORPUS)).replace("\\", "/"))
    called = ess_called_names()

    out = {}
    counts = {k: 0 for k in ("engine", "game_script", "internal",
                             "engine_fns", "game_script_fns", "internal_fns")}
    for key, fns in sorted(dump.items()):
        root = key.split(".", 1)[0]
        # EXCLUDE_EXACT matches the FULL key, never the root: `_MODULES` the bare registry is excluded while
        # `_MODULES.antiair` -- a real module underneath it -- is not. Matching on root here is what made an
        # earlier pass drop all 104 registry-only modules even after they were deliberately un-excluded.
        if root in EXCLUDE_PREFIX or key in EXCLUDE_EXACT:
            continue
        # `_MODULES.<name>` is a resident Lua module reachable only through the registry (see EXCLUDE_PREFIX's
        # note) -- game script, not an internal. Checked BEFORE the underscore rule, which would otherwise
        # misfile all 104 of them.
        stem = None
        if root == "_MODULES":
            kind, stem = "game_script", key.split(".", 1)[1].lower()
        elif root.startswith("_") or ".__" in key:
            # A leading underscore is this codebase's own "internal" marker (_GuiInternal, _SYS,
            # _OFMETATABLE). Kept rather than dropped -- silently discarding 100+ real functions would make
            # the file quietly wrong -- but bucketed so it stays out of the lists anyone actually browses.
            kind = "internal"
        elif root.lower() in modules:
            kind, stem = "game_script", root.lower()
        else:
            kind = "engine"
        entry = {
            "kind": kind,
            "count": len(fns),
            "functions": fns,
            # Which of these Ess already references -- so the remainder IS the coverage gap, without anyone
            # having to diff two files by hand.
            "called_by_ess": sorted(f for f in fns if key + "." + f in called),
        }
        if stem and stem in corpus_stems:
            entry["source"] = corpus_stems[stem]
        if root == "_MODULES":
            entry["note"] = ("loaded but not import()ed in the sampled game state, so it has no top-level "
                             "global -- reach it as %s, or import() it first" % key)
        out[key] = entry
        counts[kind] += 1
        counts[kind + "_fns"] += len(fns)

    # Aliases are recorded, not dropped: "why is MrxPmc.MrxUtil missing" has an answer in the file itself.
    alias_out = {a: c for a, c in sorted(aliases.items())
                 if not a.split(".", 1)[0] in EXCLUDE_PREFIX}

    return {
        "aliases": alias_out,
        "aliases_note": "name -> the canonical name holding the SAME table. The module system puts an "
                        "imported module's table onto every importer (MrxPmc.MrxUtil is MrxUtil), and each "
                        "module self-references as _THIS. Deduped by table identity, not by name: some "
                        "same-named tables are genuinely distinct (SubtitleBuffer ~= Pda.SubtitleBuffer).",
        "_comment": "Every Lua function callable in the live game, dumped from a running VM. "
                    "See tools/dump_natives.py for how, and why the engine/game_script split is "
                    "evidence-based rather than guessed. Ess's own surface is in ess.json, not here.",
        "generated": datetime.date.today().isoformat(),
        "source": "live pairs(_G) walk via lua-bridge",
        "game_dir": str(game_dir),
        "kinds": {
            "engine": "a C++ native. No source exists anywhere -- probe it, or check the wiki.",
            "game_script": "a resident Lua module's global function, namespaced by import(). "
                           "`source` is its file in the decompiled corpus -- you can just read it.",
        },
        "counts": counts,
        "namespaces": out,
    }


def write_markdown(manifest, dest):
    L = ["# Mercenaries 2 — complete live Lua function surface", ""]
    c = manifest["counts"]
    L += [f"Dumped from a running game on {manifest['generated']} by a `pairs(_G)` walk inside the live VM "
          f"(`tools/dump_natives.py` in mercs2-lua-essentials). Deduped by table identity, so nothing is "
          f"listed twice under an import alias.", "",
          f"- **{c['engine_fns']} functions** across **{c['engine']} engine namespaces** — C++ natives. No source exists anywhere; probe them or check the wiki.",
          f"- **{c['game_script_fns']} functions** across **{c['game_script']} game-script namespaces** — resident Lua, namespaced by `import()`. Source is in the decompiled corpus, listed per namespace below.",
          f"- **{c['internal_fns']} functions** across **{c['internal']} internal namespaces** — underscore-prefixed engine internals, in an appendix at the end.",
          "", "Each namespace notes how many of its functions the **Ess framework already reaches**; the rest "
          "is uncovered surface. Ess's own API is catalogued separately in `ess.json`.", "",
          "---", ""]

    def section(kind, title, blurb=None):
        rows = sorted((k, e) for k, e in manifest["namespaces"].items() if e["kind"] == kind)
        L.append(f"## {title}")
        L.append("")
        if blurb:
            L.extend([blurb, ""])
        # An index first -- 91 namespaces is too many to find anything in by scrolling.
        L.append(" · ".join(f"[{k}](#{k.lower().replace('.', '').replace('_', '')})" for k, _ in rows))
        L.append("")
        for key, e in rows:
            head = f"### {key} — {e['count']} function" + ("s" if e["count"] != 1 else "")
            L.extend([head, ""])
            meta = []
            if e.get("source"):
                meta.append(f"source: `{e['source']}`")
            if e["called_by_ess"]:
                meta.append(f"**Ess reaches {len(e['called_by_ess'])} of {e['count']}**: "
                            + ", ".join("`%s`" % f for f in e["called_by_ess"]))
            else:
                meta.append("*not reached by Ess at all*")
            L.extend(["  \n".join(meta), ""])
            L.append(", ".join("`%s`" % f for f in e["functions"]))
            L.append("")

    section("engine", "Engine natives (C++ — no source)")
    section("game_script", "Resident game script (Lua — source available)",
            "These are ordinary Lua functions. When one does something you want, you can read exactly how "
            "it does it in the corpus file named under each namespace.")
    if manifest["aliases"]:
        L += ["---", "", "## Appendix: aliases", "",
              "Each of these names holds the *same table* as its canonical name — the module system puts an "
              "imported module onto every importer, and each module self-references as `_THIS`. Listed so "
              "\"why isn't `MrxPmc.MrxUtil` in here\" has an answer.", ""]
        for a, canon in sorted(manifest["aliases"].items()):
            L.append(f"- `{a}` → `{canon}`")
        L.append("")
    section("internal", "Appendix: engine internals",
            "Underscore-prefixed. Listed for completeness; not intended as a public surface.")
    dest.write_text("\n".join(L), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description="Dump the live game's whole Lua function surface to natives.json.")
    ap.add_argument("--game-dir", default=str(DEFAULT_GAME_DIR))
    ap.add_argument("--export", metavar="DIR",
                    help="also write a human-readable NATIVES.md into this directory")
    args = ap.parse_args()

    print("[natives] dumping from the live game...")
    dump, aliases = parse_dump(run_dump(args.game_dir))
    print(f"[natives] parsed {len(dump)} distinct tables, {sum(len(v) for v in dump.values())} functions, "
          f"{len(aliases)} aliases folded away")
    # Self-check against a known-good value: the wiki's own live dump of Object found exactly 87.
    if len(dump.get("Object", [])) != 87:
        print(f"[natives] WARNING: Object has {len(dump.get('Object', []))} functions, expected 87 "
              f"-- the walk may be incomplete, or the game genuinely changed.")

    manifest = build(dump, aliases, args.game_dir)
    DIST.mkdir(exist_ok=True)
    (DIST / "natives.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    c = manifest["counts"]
    print(f"[natives] wrote {DIST / 'natives.json'}")
    print(f"[natives]   engine:      {c['engine']:3} namespaces, {c['engine_fns']:5} functions")
    print(f"[natives]   game script: {c['game_script']:3} namespaces, {c['game_script_fns']:5} functions")
    print(f"[natives]   internal:    {c['internal']:3} namespaces, {c['internal_fns']:5} functions")

    if args.export:
        dest = pathlib.Path(args.export).expanduser() / "NATIVES.md"
        dest.parent.mkdir(parents=True, exist_ok=True)
        write_markdown(manifest, dest)
        print(f"[natives] wrote {dest}")


if __name__ == "__main__":
    main()
