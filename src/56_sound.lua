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

local Ess = _G.Ess
Ess.Sound = Ess.Sound or {}

-- Ess.Sound.cue(uGuidOrNil, sCueName) -- CONFIRMED pattern (wiki/namespaces/sound.md): a real object guid
-- attaches the sound to that object (e.g. an alarm on a building); nil/0 is the convention used
-- throughout the shipped UI code (mrxguidialogbox.lua etc.) for a plain UI/HUD one-shot with no world
-- position.
function Ess.Sound.cue(uGuidOrNil, sCueName)
    if type(sCueName) ~= "string" or sCueName == "" then return end
    local ok = pcall(Sound.CueSound, uGuidOrNil or 0, sCueName)
    if not ok then Ess.Log("Sound.cue: CueSound failed for '" .. tostring(sCueName) .. "'") end
end

-- Ess.Sound.stop(uGuidOrNil, sCueName) -- must be called with the SAME (uGuid, sCueName) pair a prior
-- cue() used, matching every confirmed real call site.
function Ess.Sound.stop(uGuidOrNil, sCueName)
    if type(sCueName) ~= "string" or sCueName == "" then return end
    pcall(Sound.StopSound, uGuidOrNil or 0, sCueName)
end

function Ess.Sound.ambience(sStreamName)
    if type(sStreamName) ~= "string" or sStreamName == "" then return end
    pcall(Sound.CueAmbience, sStreamName)
end

function Ess.Sound.stopAmbience(sStreamName)
    if type(sStreamName) ~= "string" or sStreamName == "" then return end
    pcall(Sound.StopAmbience, sStreamName)
end

-- Ess.Sound.volume(nLevel, nFadeTime) -- CONFIRMED args: nLevel observed as 0/1 in real scripts (not
-- necessarily a 0..1 float range beyond that), nFadeTime in seconds.
function Ess.Sound.volume(nLevel, nFadeTime)
    pcall(Sound.SetMasterVolume, nLevel, nFadeTime or 0)
end

-- Ess.Easy.Sound.play(sCueName) -- a plain UI one-shot, no guid/opts to think about.
Ess.Easy = Ess.Easy or {}
Ess.Easy.Sound = Ess.Easy.Sound or {}
function Ess.Easy.Sound.play(sCueName)
    Ess.Sound.cue(nil, sCueName)
end
