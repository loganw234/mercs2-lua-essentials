#!/usr/bin/env python3
"""build/package.py -- build the release zip for Ess.

Produces dist/Ess-<version>.zip laid out so a user just extracts it into their Mercenaries 2 install and
the framework lands where it belongs:

    data/vz-patch.wad            the UI .gfx movies Ess.UI renders through (menus/toasts/board/chat)
    scripts/OnLoad/1_Ess.lua     the framework itself -- a FRESH build (this runs build/merge.py first)
    Ess-samples/recipes/         the recipe catalog (reference only -- also the smoke test)
    Ess-samples/demos/           the bind-to-a-key demos (CustomMenu, CoopChat, MissionForge, ...) --
                                 reference only, NOT deployed into scripts/OnKey/. A modder who wants one
                                 copies it in themselves and picks their own key; see each file's header.
    Ess-README.txt               what's in the zip + install steps (incl. the lua_loader.ini line)

Only the framework itself (1_Ess.lua + vz-patch.wad) is actually installed by this zip. Earlier releases
also auto-deployed the OnKey demos into scripts/OnKey/ with pre-suggested keys covering all of F1-F12 --
that silently ate every F-key before a new modder had bound their own first mod. Demos are reference-only
now, same tier as the recipes.

Deliberately does NOT bundle a scripts/lua_loader.ini: extracting over a game install would clobber the
user's existing loader config (and their lua-bridge line). The exact [OnLoad] line to MERGE in is in
Ess-README.txt instead -- matching how ContractFramework0.1.zip shipped.

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
TOOLS = ROOT / "tools"


def version():
    txt = (SRC / "00_core.lua").read_text(encoding="utf-8")
    m = re.search(r'Ess\.VERSION\s*=\s*"([^"]+)"', txt)
    return m.group(1) if m else "0.0.0"


def install_notes(ver):
    return (
        "Ess -- foundational Lua library for Mercenaries 2  (v%(ver)s)\n"
        "==========================================================\n\n"
        "WHAT'S IN THIS ZIP\n"
        "  data/vz-patch.wad          the UI .gfx movies Ess.UI renders through (menus/toasts/board/chat)\n"
        "  scripts/OnLoad/1_Ess.lua   the framework itself (one merged file)\n"
        "  Ess-samples/recipes/       short \"how do I X?\" recipe scripts + docs (reference; also the smoke test)\n"
        "  Ess-samples/demos/         bigger bind-to-a-key demos -- reference only, not installed for you (see below)\n"
        "  Ess-GETTING_STARTED.md     install -> your first keypress mod (start here); Ess-CAPABILITIES.md = full API\n"
        "  Ess-TROUBLESHOOTING.md     what to check if something doesn't work\n"
        "  mercs2-lua-ide.html        a browser Lua editor -- double-click it, hit Connect, write Ess in your live game\n\n"
        "INSTALL\n"
        "  1. Extract this zip INTO your Mercenaries 2 folder (the one with Mercenaries2.exe). The data/\n"
        "     and scripts/ folders merge into the game's existing ones; nothing here touches a save.\n"
        "  2. Register Ess in scripts/lua_loader.ini -- ADD this line (MERGE into any existing [OnLoad]\n"
        "     section; do NOT overwrite the file, it also holds your lua-bridge setup):\n\n"
        "        [OnLoad]\n"
        "        1_Ess.lua=5\n\n"
        "  3. Launch the game. \"[Ess] v%(ver)s ready\" appears in scripts/lua_loader_printf.log once it loads.\n"
        "     Nothing? See Ess-TROUBLESHOOTING.md.\n\n"
        "  That's it -- every other mod just reads the global _G.Ess table. Learn the API by example from\n"
        "  Ess-samples/recipes/. Want to try one of the bind-to-a-key demos in Ess-samples/demos/? Copy the\n"
        "  .lua file into scripts/OnKey/ and add a line for it under [OnKey] in lua_loader.ini -- each\n"
        "  file's own header comment says what it does and suggests a key.\n"
    ) % {"ver": ver}


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

        for p in sorted((SAMPLES / "recipes").glob("*.lua")):
            z.write(p, "Ess-samples/recipes/" + p.name); files += 1
        # the bind-to-a-key demos, bundled as REFERENCE ONLY (Ess-samples/, not scripts/OnKey/) -- a
        # modder who wants one copies it into their own scripts/OnKey/ and picks their own key. Earlier
        # releases deployed these directly with pre-suggested keys covering all of F1-F12, which silently
        # claimed every F-key before a new modder had bound their own first mod.
        for p in sorted((SAMPLES / "demos").glob("*.lua")):
            z.write(p, "Ess-samples/demos/" + p.name); files += 1
        # every top-level doc under samples/ (README.md, PORTING_MENUS.md, and anything added later) --
        # a glob so a new sample doc is shipped automatically instead of silently left out of the zip.
        for p in sorted(SAMPLES.glob("*.md")):
            z.write(p, "Ess-samples/" + p.name); files += 1

        # the top-level guides, so a downloaded zip is self-contained for LEARNING, not just installing
        for doc in ("GETTING_STARTED.md", "CAPABILITIES.md", "TROUBLESHOOTING.md"):
            p = ROOT / doc
            if p.exists():
                z.write(p, "Ess-" + doc); files += 1

        # the standalone browser Lua IDE -- a plain double-click .html that writes Ess into a live game over
        # the lua-bridge. Refreshed from its own GitHub release in CI (see release.yml) so the download always
        # ships the current build. Bundled here so users get the editor with the framework.
        ide = TOOLS / "mercs2-lua-ide.html"
        if ide.exists():
            z.write(ide, "mercs2-lua-ide.html"); files += 1

    print("[package] wrote %s (%d files, %d bytes)" % (out, files, out.stat().st_size))
    print("[package] extract it into your Mercenaries 2 folder; install steps are in Ess-README.txt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
