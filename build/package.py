#!/usr/bin/env python3
"""build/package.py -- build the release zip for Ess.

Produces dist/Ess-<version>.zip laid out in the GAME'S OWN folder structure, so a user just extracts it
into their Mercenaries 2 install and every file lands where it belongs:

    data/vz-patch.wad            the UI .gfx movies Ess.UI renders through (menus/toasts/board/chat)
    scripts/OnLoad/1_Ess.lua     the framework itself -- a FRESH build (this runs build/merge.py first)
    scripts/OnKey/*.lua          the bind-to-a-key demos (CustomMenu, CoopChat, MissionForge, ...)
    Ess-samples/                 the recipe catalog + docs (reference only -- Ess-* prefixed so it's
                                 obviously separate from the files that deploy into the game)
    Ess-README.txt               what's in the zip + install steps (incl. the lua_loader.ini lines)

Deliberately does NOT bundle a scripts/lua_loader.ini: extracting over a game install would clobber the
user's existing loader config (and their lua-bridge line). The exact [OnLoad]/[OnKey] lines to MERGE in
are in Ess-README.txt instead -- matching how ContractFramework0.1.zip shipped.

Usage: python build/package.py   (run from anywhere -- paths resolve off this file's own location)
Output: dist/Ess-<version>.zip
"""
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"
DATA = ROOT / "data"
SAMPLES = ROOT / "samples"

# the bind-to-a-key demos to ship (deployable into scripts/OnKey/). Kept as an explicit list, not a glob,
# so adding a WIP demo to samples/OnKey/ doesn't silently ship it in a release.
ONKEY = ["CustomMenu.lua", "CoopChat.lua", "MissionForge.lua", "CinematicDemo.lua", "CarStunt.lua"]

# the suggested key bindings shown in the install notes (must match samples/README.md's OnKey table).
ONKEY_KEYS = {
    "CustomMenu.lua": "F4", "CoopChat.lua": "F2", "MissionForge.lua": "F7",
    "CinematicDemo.lua": "F9", "CarStunt.lua": "F10",
}


def version():
    txt = (SRC / "00_core.lua").read_text(encoding="utf-8")
    m = re.search(r'Ess\.VERSION\s*=\s*"([^"]+)"', txt)
    return m.group(1) if m else "0.0.0"


def install_notes(ver):
    onkey_lines = "\n".join("        %s=%s" % (n, ONKEY_KEYS[n]) for n in ONKEY)
    return (
        "Ess -- foundational Lua library for Mercenaries 2  (v%(ver)s)\n"
        "==========================================================\n\n"
        "WHAT'S IN THIS ZIP\n"
        "  data/vz-patch.wad          the UI .gfx movies Ess.UI renders through (menus/toasts/board/chat)\n"
        "  scripts/OnLoad/1_Ess.lua   the framework itself (one merged file)\n"
        "  scripts/OnKey/*.lua        optional demos you bind to keys (see below)\n"
        "  Ess-samples/               short \"how do I X?\" recipe scripts + docs (reference; also the smoke test)\n\n"
        "INSTALL\n"
        "  1. Extract this zip INTO your Mercenaries 2 folder (the one with Mercenaries2.exe). The data/\n"
        "     and scripts/ folders merge into the game's existing ones; nothing here touches a save.\n"
        "  2. Register the scripts in scripts/lua_loader.ini -- ADD these lines (MERGE into any existing\n"
        "     [OnLoad]/[OnKey] sections; do NOT overwrite the file, it also holds your lua-bridge setup):\n\n"
        "        [OnLoad]\n"
        "        1_Ess.lua=5\n\n"
        "        [OnKey]\n"
        "%(onkey)s\n\n"
        "  3. Launch the game. \"[Ess] v%(ver)s ready\" appears in scripts/lua_loader_printf.log once it loads.\n\n"
        "  Only 1_Ess.lua + data/vz-patch.wad are required; the OnKey demos are optional. Every other mod\n"
        "  just reads the global _G.Ess table. Learn the API by example from Ess-samples/recipes/.\n"
    ) % {"ver": ver, "onkey": onkey_lines}


def main():
    print("[package] building a fresh dist/Ess.lua ...")
    if subprocess.run([sys.executable, str(ROOT / "build" / "merge.py")]).returncode != 0:
        print("[package] merge.py failed -- aborting")
        return 1

    ess = DIST / "Ess.lua"
    wad = DATA / "vz-patch.wad"
    for required in (ess, wad):
        if not required.exists():
            print("[package] required file missing: %s" % required)
            return 1

    ver = version()
    out = DIST / ("Ess-%s.zip" % ver)
    files = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("Ess-README.txt", install_notes(ver)); files += 1
        z.write(ess, "scripts/OnLoad/1_Ess.lua"); files += 1
        z.write(wad, "data/vz-patch.wad"); files += 1

        for name in ONKEY:
            p = SAMPLES / "OnKey" / name
            if p.exists():
                z.write(p, "scripts/OnKey/" + name); files += 1
            else:
                print("[package] WARN: OnKey demo not found, skipping: %s" % name)

        for p in sorted((SAMPLES / "recipes").glob("*.lua")):
            z.write(p, "Ess-samples/recipes/" + p.name); files += 1
        # every top-level doc under samples/ (README.md, PORTING_MENUS.md, and anything added later) --
        # a glob so a new sample doc is shipped automatically instead of silently left out of the zip.
        for p in sorted(SAMPLES.glob("*.md")):
            z.write(p, "Ess-samples/" + p.name); files += 1

    print("[package] wrote %s (%d files, %d bytes)" % (out, files, out.stat().st_size))
    print("[package] extract it into your Mercenaries 2 folder; install steps are in Ess-README.txt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
