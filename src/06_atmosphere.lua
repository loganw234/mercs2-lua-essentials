-- Ess/06_atmosphere.lua -- Ess.Atmosphere: sky, light and time-of-day, and the region system that keeps
-- overwriting them.
--
-- Ess.Easy.World already has beginner verbs for this (tint/brightness/hellscape). This is the CORE tier
-- underneath: the transaction model, the value vocabulary, and an honest account of why atmosphere changes
-- do not stick -- all established by live measurement 2026-07-26, because none of it is guessable from the
-- native names.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE THREE THINGS THAT MAKE THIS NAMESPACE CONFUSING
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- 1. IT IS TRANSACTIONAL. Graphics.Atmosphere.GetValue returns nil outside a Begin()/End() pair -- not an
--    error, just nil. The one call site in the decompiled corpus reads like an ordinary standalone getter,
--    so copying it verbatim silently returns nothing. Every function here opens and closes the transaction
--    for you, which is most of the reason this file exists.
--
--    Side effect worth knowing: IsInterpolating() reads TRUE from inside an open transaction, because a
--    transaction IS an interpolation as far as the engine is concerned. Measured false -> (Begin) true ->
--    (End) false with nothing else running. So never sample that flag from inside a Begin block; .blending()
--    below deliberately does not.
--
-- 2. VALUE KEYS ARE NOT VALIDATED. A nonsense key raises no error and returns no failure signal -- inside a
--    transaction it just reads 0. Since 0 is a legitimate value for several real keys, you CANNOT use that
--    to test whether a key exists. A typo is a silent no-op forever.
--
--    Worse, the engine's own spelling contains a mistake you have to reproduce: it is
--    "fBloomContastMultiplier" and "fBloomContastLimit" -- Contast, not Contrast. Spell it correctly and it
--    silently does nothing. Use Ess.Atmosphere.KEYS below rather than typing any of these by hand.
--
-- 3. THE REGION SYSTEM OWNS THE ATMOSPHERE, NOT YOU. The map is divided into named atmosphere regions
--    (rgn_atmo_caracas, rgn_atmo_Maracaibo, rgn_atmo_Angelfalls, rgn_atmo_interior, rgn_atmo_PMCinterior,
--    rgn_atmo_carmonaislandrain). There are FORTY of them, not six -- the script corpus only names the six
--    that shipped missions touch, while the full set lives in the LEVEL data (layers_static) and includes
--    rgn_atmo_Merida, _Shanty, _Islands, _OilRig, _Amazon, the _Industrial* family and more, all verified
--    to resolve live. Name lookup is case-insensitive, which is why the extracted list holds 41 strings for
--    40 regions (rgn_atmo_caracas and rgn_atmo_Caracas are one guid). Crossing into one starts
--    an INTERPOLATED BLEND, about a second long, from wherever the atmosphere currently is to that region's
--    own settings.
--
--    So a manual change is not "overwritten" so much as used as the STARTING POINT of a blend the engine is
--    driving somewhere else. Measured across one crossing: fLightIntensity 1.15 -> 1.02 -> 1.0 and
--    fAtmosphereForce 1.0 -> 2.30 -> 2.5, settling over roughly a second, with a night sky fading back to
--    daylight over the same interval.
--
--    This is why re-applying on a timer fights the symptom: if you re-apply DURING the blend you are just
--    feeding new input to the thing overwriting you. Wait for .blending() to go false first -- which is
--    exactly what the shipped scripts do (`bSafeToBegin = not Graphics.Atmosphere.IsInterpolating()`).
--
--    The real fix is probably Graphics.Atmosphere.ChangeLineRegionSetting(uRegion, sSetting) -- reconfigure
--    what the region APPLIES, so crossing it does the right thing unaided. Deliberately not wrapped yet:
--    the only setting name observed anywhere is "default", the valid set per region is unknown, and passing
--    an unrecognised one could leave a region misconfigured for the rest of the session. .region() below
--    resolves the guids so that work can start from solid ground.
--
-- API:
--   Ess.Atmosphere.get(sKey) -> n | nil                 float value (opens/closes the transaction)
--   Ess.Atmosphere.set(tKeyToValue, nFadeSeconds) -> bool   set one or many in ONE transaction
--   Ess.Atmosphere.setColor(sKey, r, g, b, a, nFade) -> bool
--   Ess.Atmosphere.setTime(n) -> bool                   0..1 through the day; 0.95 is night
--   Ess.Atmosphere.setTimeSpeed(n) -> bool              0 freezes the day/night cycle
--   Ess.Atmosphere.blending() -> bool                   is a region blend running RIGHT NOW
--   Ess.Atmosphere.setting() -> uSetting                the active setting handle (identity-comparable)
--   Ess.Atmosphere.region(sName) -> uGuid | nil         resolve an rgn_atmo_* region
--   Ess.Atmosphere.KEYS / .COLOR_KEYS / .REGIONS        the vocabularies, so nothing is typed by hand

local Ess = _G.Ess
Ess.Atmosphere = Ess.Atmosphere or {}

-- Float keys, harvested from every SetValue/GetValue call site in the corpus. Note the engine's own
-- misspelling of "Contrast" -- reproduced deliberately; see point 2 above.
Ess.Atmosphere.KEYS = {
    lightIntensity              = "fLightIntensity",
    atmosphereForce             = "fAtmosphereForce",
    atmosphereLimit             = "fAtmosphereLimit",
    timeRestore                 = "fTimeRestore",
    bloomAmount                 = "fBloomAmount",
    bloomMultiplier             = "fBloomMultiplier",
    bloomThreshold              = "fBloomThreshold",
    bloomBlurRadius             = "fBloomBlurRadius",
    bloomTargetLuminance        = "fBloomTargetLuminance",
    bloomContrastMultiplier     = "fBloomContastMultiplier",   -- engine typo, intentional
    bloomContrastLimit          = "fBloomContastLimit",        -- engine typo, intentional
    bloomAdaptiveLuminanceScale = "fBloomAdaptiveLuminanceScale",
    bloomAdaptiveLuminancePct   = "fBloomAdaptiveLuminancePercent",
}

Ess.Atmosphere.COLOR_KEYS = {
    ambient     = "uiAmbientColor",
    rim         = "uiRimColor",
    ambientCube = { "uiAmbientCube0", "uiAmbientCube1", "uiAmbientCube2",
                    "uiAmbientCube3", "uiAmbientCube4", "uiAmbientCube5" },
}

-- THE FULL REGION LIST, not the six the script corpus happens to name.
--
-- The names are not in the scripts at all -- they are in the LEVEL data (layers_static), which is why an
-- earlier pass concluded there were only six and that the rest "cannot be addressed". They can: 20 of these
-- were checked against Pg.GetGuidByName live and every one resolved, including the ones a corpus-only view
-- never sees (Merida, Shanty, Islands, OilRig, Amazon, the Industrial family, "GR Cave", "PMC Outpost").
-- A deliberately bogus name in the same batch was the only failure, so the check was real.
--
-- Lookup is CASE-INSENSITIVE, so rgn_atmo_caracas and rgn_atmo_Caracas are one region -- the extracted data
-- holds both spellings. Names with spaces are correct as written.
Ess.Atmosphere.REGIONS = {
    "rgn_atmo_ALHQ", "rgn_atmo_Alta-Gracia", "rgn_atmo_Amazon", "rgn_atmo_Amazon_North",
    "rgn_atmo_Angelfalls", "rgn_atmo_CHOutpost", "rgn_atmo_Cumana", "rgn_atmo_Cumana_South",
    "rgn_atmo_Estate", "rgn_atmo_Fort", "rgn_atmo_GR Cave", "rgn_atmo_GR Outpost",
    "rgn_atmo_GRHQ", "rgn_atmo_GRstripmine", "rgn_atmo_Guanare",
    "rgn_atmo_Industrial", "rgn_atmo_Industrial_E", "rgn_atmo_Industrial_Guanare",
    "rgn_atmo_Industrial_NW", "rgn_atmo_Industrial_SW",
    "rgn_atmo_Islands", "rgn_atmo_MarVillage", "rgn_atmo_Maracaibo", "rgn_atmo_Merida",
    "rgn_atmo_Meridastadium", "rgn_atmo_OCDepotbase", "rgn_atmo_OilRig",
    "rgn_atmo_PMC Outpost", "rgn_atmo_PMCinterior", "rgn_atmo_PR Outpost",
    "rgn_atmo_Shanty", "rgn_atmo_Shanty_Caracas", "rgn_atmo_VZ_Airport", "rgn_atmo_VZ_Fortifiedbase",
    "rgn_atmo_caracas", "rgn_atmo_carmonaisland", "rgn_atmo_carmonaislandrain",
    "rgn_atmo_carmonaislandtop", "rgn_atmo_interior", "rgn_atmo_margarita", "rgn_atmo_marsh",
}

-- Ess.Atmosphere.get(sKey) -> n | nil -- read one float. Opens and closes the transaction, without which
-- the native returns nil. Accepts either a raw engine key ("fLightIntensity") or a KEYS alias.
function Ess.Atmosphere.get(sKey)
    if type(sKey) ~= "string" then return nil end
    local key = Ess.Atmosphere.KEYS[sKey] or sKey
    if not Ess.Safe.quiet(Graphics.Atmosphere.Begin) then return nil end
    local ok, v = Ess.Safe.quiet(Graphics.Atmosphere.GetValue, key)
    Ess.Safe.quiet(Graphics.Atmosphere.End, 0)
    if ok then return v end
    return nil
end

-- Ess.Atmosphere.set(tKeyToValue, nFadeSeconds) -> bool -- set one or many values in ONE transaction, which
-- matters: the fade duration is a property of End(), so separate transactions mean separate fades and a
-- visibly staggered result. Keys may be KEYS aliases or raw engine names.
--
--   Ess.Atmosphere.set({ lightIntensity = 0.2, bloomAmount = 2 }, 1.5)
--
-- Returns whether the transaction completed, NOT whether the keys were real -- the engine does not report
-- an unknown key at all.
function Ess.Atmosphere.set(tKeyToValue, nFadeSeconds)
    if type(tKeyToValue) ~= "table" then return false end
    if not Ess.Safe.quiet(Graphics.Atmosphere.Begin) then return false end
    for k, v in pairs(tKeyToValue) do
        local key = Ess.Atmosphere.KEYS[k] or k
        Ess.Safe.quiet(Graphics.Atmosphere.SetValue, key, v)
    end
    local ok = Ess.Safe.quiet(Graphics.Atmosphere.End, nFadeSeconds or 0.5)
    return ok and true or false
end

-- Ess.Atmosphere.setColor(sKey, r, g, b, a, nFadeSeconds) -> bool -- colour channels are 0..255 and alpha
-- defaults to 255, matching every corpus call site.
function Ess.Atmosphere.setColor(sKey, r, g, b, a, nFadeSeconds)
    if type(sKey) ~= "string" then return false end
    local key = Ess.Atmosphere.COLOR_KEYS[sKey] or sKey
    if type(key) ~= "string" then return false end   -- guard the ambientCube TABLE alias
    if not Ess.Safe.quiet(Graphics.Atmosphere.Begin) then return false end
    Ess.Safe.quiet(Graphics.Atmosphere.SetColorValue, key, r or 255, g or 255, b or 255, a or 255)
    local ok = Ess.Safe.quiet(Graphics.Atmosphere.End, nFadeSeconds or 0.5)
    return ok and true or false
end

-- Ess.Atmosphere.setTime(n) -> bool -- time of day as 0..1. 0.95 is night; live-confirmed to visibly change
-- the sky. Pair it with .setTimeSpeed(0) or the cycle carries on from wherever you put it.
--
-- ⚠ A region crossing blends this away along with everything else -- see point 3 in the header. Confirmed:
-- a night sky faded back to daylight over about a second on crossing a boundary.
function Ess.Atmosphere.setTime(n)
    if type(n) ~= "number" then return false end
    local ok = Ess.Safe.quiet(Graphics.Atmosphere.SetTime, n)
    return ok and true or false
end

-- Ess.Atmosphere.setTimeSpeed(n) -> bool -- rate of the day/night cycle; 0 freezes it.
function Ess.Atmosphere.setTimeSpeed(n)
    if type(n) ~= "number" then return false end
    local ok = Ess.Safe.quiet(Graphics.Atmosphere.SetTimeSpeed, n)
    return ok and true or false
end

-- Ess.Atmosphere.blending() -> bool -- is a region blend running right now?
--
-- Use it to decide when it is safe to apply: applying mid-blend just hands new input to the thing that is
-- overwriting you. Same guard the shipped scripts use before beginning their own changes.
--
-- ⚠⚠ DO NOT CALL THIS IN THE SAME FRAME AS .get() / .set() / .setColor(). Those open a transaction, and a
-- transaction leaves the interpolating flag SET for the remainder of that frame -- it does not clear until
-- the next one. Measured: a bare call reads false, the same call immediately after a .get() reads TRUE, and
-- a bare call one chunk later reads false again. So
--
--     local v = Ess.Atmosphere.get("lightIntensity")
--     if not Ess.Atmosphere.blending() then ... end        -- ALWAYS false, every time
--
-- is a trap. Sample this FIRST, before touching anything else, or sample it on a later tick (an Ess.Loop
-- heartbeat is the natural place -- that is also where you would be waiting for a blend to finish anyway).
function Ess.Atmosphere.blending()
    local ok, b = Ess.Safe.quiet(Graphics.Atmosphere.IsInterpolating)
    return (ok and b) and true or false
end

-- Ess.Atmosphere.setting() -> uSetting | nil -- handle for the currently-active atmosphere setting.
--
-- ⚠ The native returns TWO userdata values and only the FIRST changes on a region crossing; this returns
-- that one. Compare handles with == to detect a transition. Do NOT tostring() the raw native result --
-- tostring() with two arguments returns a FUNCTION on this build, which is an easy way to convince yourself
-- a stored handle has become something else.
function Ess.Atmosphere.setting()
    local ok, s = Ess.Safe.quiet(Graphics.Atmosphere.GetCurrentSetting)
    if ok then return s end
    return nil
end

-- Ess.Atmosphere.region(sName) -> uGuid | nil -- resolve an rgn_atmo_* region name to its guid. Every name
-- in REGIONS resolves in the vz level (sampled live, see that table). Provided for the
-- ChangeLineRegionSetting work described in the header; there is nothing else to do with the guid yet.
function Ess.Atmosphere.region(sName)
    if type(sName) ~= "string" then return nil end
    return Ess.Guid(sName)
end
