-- Ess/56_sound.lua -- Ess.Sound: the raw one-shot sound-effect/ambience layer, wrapping the `Sound`
-- engine namespace's confirmed direct-cueing primitives. Distinct from music: Ess.Contract's `music`
-- support effect (82_contract_encounter.lua) already wraps the higher-level MrxMusic resident module's
-- dynamic-music state machine -- this is the "just play a sound effect" layer every mod eventually needs
-- and had nothing wrapping it anywhere in the framework until now.
--
-- API:
--   Ess.Sound.cue(uGuidOrNil, sCueName)     -- Sound.CueSound; nil/0 = UI/HUD-attached one-shot
--   Ess.Sound.stop(uGuidOrNil, sCueName)    -- Sound.StopSound
--   Ess.Sound.ambience(sStreamName)          -- Sound.CueAmbience
--   Ess.Sound.stopAmbience(sStreamName)      -- Sound.StopAmbience
--   Ess.Sound.volume(nLevel, nFadeTime)      -- Sound.SetMasterVolume
--
-- The mixer and cue validation, added 2026-07-26 and all verified through GETTERS rather than by ear:
--   Ess.Sound.duration(sCue) / .isCue(sCue) / .isLooping(sCue)
--   Ess.Sound.categoryVolume(sCat) / .setCategoryVolume(sCat, n)   -- get and set are NOT symmetric
--   Ess.Sound.categoryPitch(sCat)  / .setCategoryPitch(sCat, n)
--   Ess.Sound.duck(sCat, n [,fade]) / .unduck(sCat [,fade]) / .clearDucking()
--   Ess.Sound.info()                          -- lib version, audio dir, mixer snapshot, music flags
--   Ess.Sound.CATEGORIES                      -- sfx, music, ambience, vo

local Ess = _G.Ess
Ess.Sound = Ess.Sound or {}

-- Ess.Sound.cue(uGuidOrNil, sCueName) -- CONFIRMED pattern (wiki/namespaces/sound.md): a real object guid
-- attaches the sound to that object (e.g. an alarm on a building); nil/0 is the convention used
-- throughout the shipped UI code (mrxguidialogbox.lua etc.) for a plain UI/HUD one-shot with no world
-- position.
function Ess.Sound.cue(uGuidOrNil, sCueName)
    if type(sCueName) ~= "string" or sCueName == "" then return end
    local ok = Ess.Safe.quiet(Sound.CueSound, uGuidOrNil or 0, sCueName)
    if not ok then Ess.Log("Sound.cue: CueSound failed for '" .. tostring(sCueName) .. "'") end
end

-- Ess.Sound.stop(uGuidOrNil, sCueName) -- must be called with the SAME (uGuid, sCueName) pair a prior
-- cue() used, matching every confirmed real call site.
function Ess.Sound.stop(uGuidOrNil, sCueName)
    if type(sCueName) ~= "string" or sCueName == "" then return end
    Ess.Safe.quiet(Sound.StopSound, uGuidOrNil or 0, sCueName)
end

function Ess.Sound.ambience(sStreamName)
    if type(sStreamName) ~= "string" or sStreamName == "" then return end
    Ess.Safe.quiet(Sound.CueAmbience, sStreamName)
end

function Ess.Sound.stopAmbience(sStreamName)
    if type(sStreamName) ~= "string" or sStreamName == "" then return end
    Ess.Safe.quiet(Sound.StopAmbience, sStreamName)
end

-- Ess.Sound.volume(nLevel, nFadeTime) -- CONFIRMED args: nLevel observed as 0/1 in real scripts (not
-- necessarily a 0..1 float range beyond that), nFadeTime in seconds.
function Ess.Sound.volume(nLevel, nFadeTime)
    Ess.Safe.quiet(Sound.SetMasterVolume, nLevel, nFadeTime or 0)
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE MIXER, AND CUE VALIDATION -- everything below was measured, none of it needed hearing anything
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Audio is the one area where an agent cannot check its own work, so the useful discovery here is how much
-- of it is answerable through GETTERS. Sound has real ones, and between them a mod can validate a cue name,
-- read the mixer, and confirm a change landed -- without anyone listening.
--
-- ── CATEGORIES NEST, AND GET/SET ARE NOT SYMMETRIC ─────────────────────────────────────────────────────
-- This is the trap. GetCategoryVolume returns the EFFECTIVE volume -- the category's own level multiplied
-- by its parent's -- while SetCategoryVolume sets the category's OWN level. So setting ambience to 0.42 and
-- reading back 0.3148 is not a failed write; it is 0.42 x its parent.
--
-- The measured shape, from setting each category and watching what moved:
--   * "music" and "vo" are TOP LEVEL. Set music to 0.5 and it reads back exactly 0.5.
--   * "ambience" IS A CHILD OF "sfx". Its own level is 1.0 by default, which is why it normally reads the
--     same as sfx; ducking sfx to 0.15 dragged ambience to 0.1499 with it, while music did not move.
--
-- The practical consequence: NEVER RESTORE A CATEGORY TO A REMEMBERED READING. Reading ambience as 0.7495
-- and writing 0.7495 back sets its own level to 0.7495 and leaves it audibly quieter than it started;
-- restoring own-level 1.0 reproduced the original reading to the last digit. Remember what you SET, or
-- reset to 1.0.
--
-- ── A SETTER'S EFFECT IS NOT VISIBLE UNTIL THE NEXT FRAME ──────────────────────────────────────────────
-- Set-then-get in one chunk always returns the OLD value. This cost a wrong conclusion during the sweep --
-- SetCategoryVolume and the whole fade path were written off as inert on exactly that evidence, and both
-- work fine when sampled a frame later. Never verify an audio write in the chunk that made it.
--
-- ── FADES ARE A STACK, NOT A LEVEL ─────────────────────────────────────────────────────────────────────
-- Each duck() pushes and each unduck() pops ONE. Unbalanced calls leave the category partially ducked with
-- no obvious way back, which is why clearDucking() exists and why duck/unduck are named as a pair.
Ess.Sound.CATEGORIES = { "sfx", "music", "ambience", "vo" }

-- Ess.Sound.duration(sCue) -> nSeconds | -1 | nil
--   > 0   a real, currently-resolvable cue, and this is its length
--   -1    a real cue with NO fixed length -- a loop (measured on an alarm cue)
--   nil   not resolvable: either the name is wrong, or its bank is not loaded right now
--
-- The last case is why this is not quite an existence test. The engine returns 0 for an unresolvable cue,
-- normalised to nil here because 0 would otherwise read as "a zero-length sound". A cue that is real but
-- whose bank has not streamed in is indistinguishable from a typo -- confirmed, several cues the corpus
-- definitely uses returned 0 while others returned real durations. So a nil means "cannot answer", not
-- "does not exist".
function Ess.Sound.duration(sCue)
    if type(sCue) ~= "string" or sCue == "" then
        Ess.Safe.reject("Ess.Sound.duration", "sCue must be a non-empty string")
        return nil
    end
    local ok, v = Ess.Safe.quiet(Sound.GetMaxDuration, sCue)
    if not ok or type(v) ~= "number" or v == 0 then return nil end
    return v
end

-- Ess.Sound.isCue(sCue) -- whether the engine can resolve this cue RIGHT NOW. Useful before cueing a name
-- built at runtime, since a bad cue is otherwise completely silent -- no error, no return value, nothing.
function Ess.Sound.isCue(sCue)
    return Ess.Sound.duration(sCue) ~= nil
end

-- Ess.Sound.isLooping(sCue) -- a cue with no fixed duration. Worth checking before cueing something you do
-- not intend to stop, because a loop will run until Ess.Sound.stop is called with the same (guid, cue).
function Ess.Sound.isLooping(sCue)
    return Ess.Sound.duration(sCue) == -1
end

-- Ess.Sound.categoryVolume(sCategory) -> the EFFECTIVE volume (own level x parent). See the note above.
function Ess.Sound.categoryVolume(sCategory)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Sound.categoryVolume", "sCategory must be one of Ess.Sound.CATEGORIES")
        return nil
    end
    local ok, v = Ess.Safe.quiet(Sound.GetCategoryVolume, sCategory)
    if ok and type(v) == "number" then return v end
    return nil
end

-- Ess.Sound.setCategoryVolume(sCategory, nLevel) -- sets the category's OWN level, 0..1. Reading it back
-- returns own x parent, and not until the next frame.
function Ess.Sound.setCategoryVolume(sCategory, nLevel)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Sound.setCategoryVolume", "sCategory must be one of Ess.Sound.CATEGORIES")
        return false
    end
    local v = tonumber(nLevel)
    if not v then
        Ess.Safe.reject("Ess.Sound.setCategoryVolume", "nLevel must be a number, got " .. type(nLevel))
        return false
    end
    Ess.Safe.quiet(Sound.SetCategoryVolume, sCategory, v)
    return true
end

function Ess.Sound.categoryPitch(sCategory)
    if type(sCategory) ~= "string" or sCategory == "" then
        -- Its four mixer siblings all reject here; this one returned a bare nil, so a typo'd category was
        -- invisible even with Ess.DEBUG on -- exactly the silence the reject channel exists to break.
        Ess.Safe.reject("Ess.Sound.categoryPitch", "sCategory must be one of Ess.Sound.CATEGORIES")
        return nil
    end
    local ok, v = Ess.Safe.quiet(Sound.GetCategoryPitch, sCategory)
    if ok and type(v) == "number" then return v end
    return nil
end

function Ess.Sound.setCategoryPitch(sCategory, nPitch)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Sound.setCategoryPitch", "sCategory must be one of Ess.Sound.CATEGORIES")
        return false
    end
    local v = tonumber(nPitch)
    if not v then
        Ess.Safe.reject("Ess.Sound.setCategoryPitch", "nPitch must be a number (1 = normal)")
        return false
    end
    Ess.Safe.quiet(Sound.SetCategoryPitch, sCategory, v)
    return true
end

-- Ess.Sound.duck(sCategory, nLevel [,nFade]) / .unduck(sCategory [,nFade]) -- the game's own ducking, used
-- to drop the mix under dialogue. This is the path the shipped scripts take (mrxsoundcategories.lua), and
-- it animates over nFade seconds rather than snapping.
--
-- PAIR THESE. Each duck pushes a level and each unduck pops exactly one; three ducks and one unduck leaves
-- the category two levels down. clearDucking() is the escape hatch.
function Ess.Sound.duck(sCategory, nLevel, nFade)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Sound.duck", "sCategory must be one of Ess.Sound.CATEGORIES")
        return false
    end
    Ess.Safe.quiet(Sound.FadeCategoryDown, sCategory, tonumber(nLevel) or 0.2, tonumber(nFade) or 0.5)
    return true
end

function Ess.Sound.unduck(sCategory, nFade)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Sound.unduck", "sCategory must be one of Ess.Sound.CATEGORIES")
        return false
    end
    Ess.Safe.quiet(Sound.FadeCategoryUp, sCategory, tonumber(nFade) or 0.5)
    return true
end

-- Ess.Sound.clearDucking() -- drop every pushed fade level at once, for when the stack has got away from you.
function Ess.Sound.clearDucking()
    Ess.Safe.quiet(Sound.ClearFadeCategories)
    Ess.Safe.quiet(Sound.ClearPitchCategories)
    return true
end

-- Ess.Sound.info() -> table -- what the audio system will tell you about itself. All measured present:
-- nLibVersion 12 on this build (mrxmusic gates features on >= 11), sAudioDir ".\Data\Audios".
function Ess.Sound.info()
    local t = {}
    local ok, v
    ok, v = Ess.Safe.quiet(Sound._GetLibVersion);       if ok then t.nLibVersion = v end
    ok, v = Ess.Safe.quiet(Sound.GetAudioDir);          if ok then t.sAudioDir = v end
    ok, v = Ess.Safe.quiet(Sound.IsDynamicMusic);       if ok then t.bDynamicMusic = v end
    ok, v = Ess.Safe.quiet(Sound.IsFactionLockedMusic); if ok then t.bFactionLocked = v end
    ok, v = Ess.Safe.quiet(Sound.IsActionLevelLockedMusic); if ok then t.bActionLocked = v end
    for _, c in ipairs(Ess.Sound.CATEGORIES) do
        t[c] = Ess.Sound.categoryVolume(c)
    end
    return t
end

-- Ess.Easy.Sound.play(sCueName) -- a plain UI one-shot, no guid/opts to think about.
Ess.Easy = Ess.Easy or {}
Ess.Easy.Sound = Ess.Easy.Sound or {}
function Ess.Easy.Sound.play(sCueName)
    Ess.Sound.cue(nil, sCueName)
end
