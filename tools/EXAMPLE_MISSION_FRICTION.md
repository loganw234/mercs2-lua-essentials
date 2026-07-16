# Example-mission friction log

Authoring a full example mission end-to-end (a new-ish user's perspective) to shake out where the Ess
framework + the MissionForge → web-tool → Ess.Contract pipeline are awkward, missing a helper, or force raw
calls. Each friction point gets logged here; the ones worth fixing get fixed and marked ✅.

**The mission:** an Allied oil refinery under assault by China, with the player siding with China to take the
oil ("The Allies have too much oil, we'd like you to relieve them of it"). Opens with a cinematic — helis fly
in and the player watches the attack kick off from a vantage before getting involved.

## Friction points

1. ✅ **No faction-vs-faction relations preset.** `Ess.Easy.Relations.makeHostile` only means "hostile to
   PMC (you)", so it can't express "China attacks the Allies" — the entire premise. A new user reaching for
   the Easy tier hits a wall on step one. **Fixed:** added `Ess.Easy.Relations.war(a, b)` and
   `.sideWith(friend, foe)` (commit `f65f160`); `sideWith("China","Allied")` is the whole stance in one call.

## Known gaps we expect to hit (from the pipeline survey, not yet reached in authoring)

- **Web tool emits `Contract.Register{}`, not `Ess.Contract.Register{}`** — the in-game MissionForge half is
  on Ess, the browser generator isn't. Will need updating when we round-trip a mission through it.
- **No cinematic authoring in MissionForge / the web tool** — the intro cutscene (`def.cinematic`) has no
  in-game shot-placement or web-tool timeline yet; it'll have to be hand-authored as Ess.Cinematic steps for
  now (which itself is a friction data point).
