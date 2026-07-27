# data/vz-patch.wad — the movies Ess.UI renders through

`Ess.UI` does not draw with engine primitives. Every widget is a clip inside a Scaleform movie, and
those movies have to be inside a patch WAD the game loads at startup. `data/vz-patch.wad` is that
file; `build/package.py` ships it to `data/vz-patch.wad` in the release zip, which the user extracts
over their install.

The only movie the kit actually uses is **`ess_ui`** — one runtime movie whose AS2 payload draws
every widget from theme parameters. The other ten are the pre-rewrite per-widget movies, kept
because `Ess.UI.FILES.panel` and friends are published surface a third-party script may reference.

## The gotcha that shipped a broken release

**Assets are registered under their bare stem, but loaded with the extension.** `Ess.UI.FILES` says
`"ess_ui.gfx"` and `SetSwfFile` takes `"ess_ui.gfx"`, yet the wad's ASET holds
`pandemic_hash_m2("ess_ui")` — the extension is stripped before hashing. Injecting a movie as
`ess_ui.gfx` registers a name the engine will never look up, and the failure is **silent**: the
widget host constructs fine, so nothing errors, nothing logs, and the UI simply never appears.

v0.5.1 shipped without `ess_ui` at all — the wad had been committed once, before the UI rewrite, and
`package.py` only checked that the file existed. It did not reproduce in development because the dev
install had the movie injected by hand. `check_wad()` in `build/package.py` now parses the ASET and
fails the build if any name in `Ess.UI.FILES` is absent.

## Injecting a movie

Uses [`mercs2-gfx-tool`](https://github.com/loganw234/mercs2-gfx-tool). `--wad` is the retail
`vz.wad` (the source of the container/type layout `--template` copies), `--merge` is the existing
patch wad to add to. Note the bare `--name`:

```bash
gfx_tool new --wad "<game>/data/vz.wad" --name ess_ui --movie ess_ui.gfx --merge data/vz-patch.wad --out /tmp/vz-patch-new.wad
```

Write to a scratch `--out` and verify before overwriting `data/vz-patch.wad`:

```bash
gfx_tool extract --wad /tmp/vz-patch-new.wad --name ess_ui --out /tmp/roundtrip.gfx
```

The extracted bytes must equal the movie you injected. `python build/package.py` then re-runs the
ASET gate as a final check.

## Where the movie comes from

`ess_ui.gfx` is authored in **gfxforge-web** (`examples/mercs2/ess_ui.js` compiles to
`examples/mercs2/ess_ui.gfx`), not in this repo. That split is why the release went stale: a rebuild
there does not touch anything here. **After changing the movie, re-inject and commit the wad** — the
gate proves the asset is present, not that it is current.
