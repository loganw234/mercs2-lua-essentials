-- Ess/05_sys.lua -- Ess.Sys: what game am I running in, and how is it configured?
--
-- The engine's `Sys` namespace is 64 functions of mixed concerns -- timing, autosave, asset streaming, save
-- versioning, and a big pile of environment/settings getters. Ess already covers the timing half
-- (Ess.Time -> Sys.RealTime/MainTimeStamp/TimeStampMark) and the autosave half (Ess.Save). This file is the
-- ENVIRONMENT half: level identity, build identity, and the player's own option settings.
--
-- Why a script cares: "am I in freeplay or a mission", "are subtitles on so my custom dialogue matches the
-- player's preference", "is the world still streaming in so I should wait before spawning". All previously
-- meant dropping to raw natives.
--
-- Everything here is READ-ONLY and side-effect free -- the Sys mutators (RequestGameState, SetLevelName,
-- StartSingleplayer, AddStringDb, ...) are deliberately excluded; several of them drive the game's own state
-- machine and are recorded in docs/deferred-setters.md instead.
--
-- API:
--   Ess.Sys.level() -> sLevel, sMasterScript      "vz","vz" in freeplay; both may be "" at the bare menu
--   Ess.Sys.version() -> sCode, sData             build code + data version (two values, not one)
--   Ess.Sys.platform() -> n                       engine's own platform enum (3 on this PC build)
--   Ess.Sys.language() -> s                       "English"
--   Ess.Sys.uptime() -> n                         seconds of main-loop time since the process started
--   Ess.Sys.isLoading() -> bool                   loading or streaming right now -- wait before spawning
--   Ess.Sys.settings() -> t                       the player's option settings (see below)
--   Ess.Sys.build() -> t                          build/SKU flags (see below)

local Ess = _G.Ess
Ess.Sys = Ess.Sys or {}

-- Ess.Sys.level() -> sLevelName, sMasterScriptName
-- Both are "vz" in freeplay. At the bare shell menu they can be empty strings rather than nil, so test with
-- `~= ""` and not just for nil-ness.
function Ess.Sys.level()
    local ok,  lvl = Ess.Safe.quiet(Sys.GetLevelName)
    local ok2, ms  = Ess.Safe.quiet(Sys.GetMasterScriptName)
    return (ok and lvl or nil), (ok2 and ms or nil)
end

-- Ess.Sys.version() -> sCode, sData -- TWO values. The corpus reads it as `local sCode, sData =
-- Sys.GetVersion()`; both come back "100000" on this build. Taking only the first is a common misread.
function Ess.Sys.version()
    local ok, code, data = Ess.Safe.quiet(Sys.GetVersion)
    if ok then return code, data end
    return nil, nil
end

-- Ess.Sys.platform() -> n | nil -- the engine's platform enum, NOT a string (3 here). Kept raw rather than
-- mapped to a name, because only one value has ever been observed and inventing labels for the rest would
-- be fiction.
function Ess.Sys.platform()
    local ok, n = Ess.Safe.quiet(Sys.GetPlatform)
    if ok then return n end
    return nil
end

-- Ess.Sys.language() -> s | nil -- "English". Worth branching on for any script that shows text.
function Ess.Sys.language()
    local ok, s = Ess.Safe.quiet(Sys.GetLanguage)
    if ok then return s end
    return nil
end

-- Ess.Sys.uptime() -> n -- seconds of MAIN-LOOP time since the process started (1354.7 in a session that
-- had been up a while). Distinct from Ess.Time.real(): this one is the game's own clock, so it does not
-- advance while the game is paused or loading, which makes it the right base for "how long has the player
-- actually been playing".
function Ess.Sys.uptime()
    local ok, n = Ess.Safe.quiet(Sys.MainTime)
    if ok then return n end
    return 0
end

-- Ess.Sys.isLoading() -> bool -- is the engine loading or streaming right now? The shipped scripts pair it
-- with a character check (`not Player.GetLocalCharacter() or Sys.IsLoadingOrStreaming()`) as the "world
-- isn't ready yet" test -- worth copying that idiom before spawning into a world mid-stream.
function Ess.Sys.isLoading()
    local ok, b = Ess.Safe.quiet(Sys.IsLoadingOrStreaming)
    return (ok and b) and true or false
end

-- Ess.Sys.settings() -> t -- the player's own option settings, in one call:
--   tutorials, subtitles, rumble    bool -- respect these; a mod that ignores `subtitles` is a bug
--   invertY, confirmOnCircle        bool -- input prefs; confirmOnCircle matters for prompt wording
--   noHud                           bool -- HUD hidden, so don't draw HUD-anchored UI
-- Grouped rather than exposed as six predicates because they are read together far more often than singly,
-- and because a single table keeps the six pcalls in one place.
function Ess.Sys.settings()
    local function q(fn)
        local ok, b = Ess.Safe.quiet(fn)
        return (ok and b) and true or false
    end
    return {
        tutorials       = q(Sys.TutorialsEnabled),
        subtitles       = q(Sys.SubtitlesEnabled),
        rumble          = q(Sys.RumbleEnabled),
        invertY         = q(Sys.YAxisInverted),
        confirmOnCircle = q(Sys.IsConfirmOnCircle),
        noHud           = q(Sys.NoHud),
    }
end

-- Ess.Sys.build() -> t -- what KIND of build this is:
--   demo         bool  demo mode
--   german       bool  the censored German SKU (different gore/content rules)
--   finalConfig  bool  a release build rather than a dev one
--   hasProfile   bool  an active player profile is loaded
--   autoLoad     bool  the auto-load-last-save path is armed
-- Several of these are called defensively in shipped scripts (`Sys.IsDemoMode and Sys.IsDemoMode()`), i.e.
-- Pandemic did not trust them to exist in every build. Ess.Safe.quiet makes that moot -- a missing binding
-- yields false rather than throwing -- but it is a hint that these vary by build, so branch on them rather
-- than asserting them.
function Ess.Sys.build()
    local function q(fn)
        local ok, b = Ess.Safe.quiet(fn)
        return (ok and b) and true or false
    end
    return {
        demo        = q(Sys.IsDemoMode),
        german      = q(Sys.IsGermanSKU),
        finalConfig = q(Sys.IsFinalConfig),
        hasProfile  = q(Sys.HaveActiveProfile),
        autoLoad    = q(Sys.AutoLoad),
    }
end
